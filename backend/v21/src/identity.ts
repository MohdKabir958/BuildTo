import {verifyToken,clerkClient} from '@clerk/express';
import type {Request,Response,NextFunction,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';

export interface VerifiedClerkIdentity {
  subject:string;
  sessionId:string;
}
export interface IdentityVerifier {
  verify(token:string):Promise<VerifiedClerkIdentity>;
}
export interface ClerkOptions {
  issuer:string;
  authorizedParties:string[];
  secretKey:string;
  jwtKey?:string;
  audience?:string;
  allowNativeWithoutAzp?:boolean;
}
export function validateClerkOptions(o:ClerkOptions):void {
  if(!o.issuer.startsWith('https://') || !o.secretKey ||
     o.authorizedParties.length===0 || o.authorizedParties.some(x=>!/^https?:\/\//.test(x)||x.includes('*'))) {
    throw new Error('V21_CLERK_CONFIG_INVALID: issuer, key and explicit authorized parties required.');
  }
  if(o.allowNativeWithoutAzp && !o.audience)
    throw new Error('V21_CLERK_NATIVE_AUDIENCE_REQUIRED');
}

function invalidSession():ApiError {return new ApiError(401,'INVALID_SESSION','Authentication required or session expired.');}
const validSubject=(s:unknown):s is string=>typeof s==='string' && /^user_[a-zA-Z0-9]{6,150}$/.test(s);
const validSession=(s:unknown):s is string=>typeof s==='string' && /^sess_[a-zA-Z0-9]{6,150}$/.test(s);

export function createClerkIdentityVerifier(o:ClerkOptions):IdentityVerifier {
  validateClerkOptions(o);
  return {async verify(token:string):Promise<VerifiedClerkIdentity> {
    if(!token || token.length>8192)throw invalidSession();
    let claims;
    try {
      claims=await verifyToken(token,{
        issuer:o.issuer,secretKey:o.secretKey,jwtKey:o.jwtKey,
        audience:o.audience,authorizedParties:o.authorizedParties,clockSkewInMs:5000,
      });
    }catch {throw invalidSession();}
    if(!validSubject(claims.sub)||!validSession(claims.sid)||claims.iss!==o.issuer)throw invalidSession();
    const party=(claims as {azp?:unknown}).azp;
    if(typeof party==='string' ? !o.authorizedParties.includes(party)
        : !(o.allowNativeWithoutAzp && o.audience))throw invalidSession();
    // Fail closed for provider-revoked sessions and banned identities, even if JWT remains unexpired.
    // This is intentionally online; add bounded safe caching only after a measured capacity review.
    let session,account;
    try {
      [session,account]=await Promise.all([
        clerkClient.sessions.getSession(claims.sid),
        clerkClient.users.getUser(claims.sub),
      ]);
    }catch(error) {
      const status=(error as {status?:unknown})?.status;
      if(status===401||status===404)throw invalidSession();
      throw new ApiError(503,'IDENTITY_PROVIDER_UNAVAILABLE','Authentication service temporarily unavailable.');
    }
    if(session.id!==claims.sid || session.userId!==claims.sub || session.status!=='active' ||
       account.id!==claims.sub)throw invalidSession();
    if(account.banned)throw new ApiError(403,'ACCOUNT_SUSPENDED','Account unavailable.');
    return {subject:claims.sub,sessionId:claims.sid};
  }};
}

export interface LocalPrincipal {
  id:string;
  displayName:string;
}
export async function resolveLocalPrincipal(
 db:Pick<PrismaClient,'user'>,identity:VerifiedClerkIdentity
):Promise<LocalPrincipal> {
  const user=await db.user.findUnique({
    where:{clerkUserId:identity.subject},
    select:{id:true,displayName:true,status:true,deletedAt:true},
  });
  if(!user)throw new ApiError(403,'PROFILE_NOT_PROVISIONED','Account has not been provisioned.');
  if(user.deletedAt||user.status!=='ACTIVE')throw new ApiError(403,'ACCOUNT_SUSPENDED','Account unavailable.');
  return {id:user.id,displayName:user.displayName};
}
export type AuthLocals={verifiedIdentity:VerifiedClerkIdentity; principal:LocalPrincipal};
export function requireIdentity(verifier:IdentityVerifier,db:Pick<PrismaClient,'user'>):RequestHandler {
  return async (req:Request,res:Response,next:NextFunction)=>{
    const value=req.header('authorization');
    if(!value || !/^Bearer [^\s]+$/.test(value))return next(invalidSession());
    try {
      const verifiedIdentity=await verifier.verify(value.slice(7));
      const principal=await resolveLocalPrincipal(db,verifiedIdentity);
      res.locals.verifiedIdentity=verifiedIdentity;
      res.locals.principal=principal;
      next();
    }catch(error){next(error);}
  };
}
