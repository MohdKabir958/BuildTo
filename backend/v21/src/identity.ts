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
}

function invalidSession():ApiError {return new ApiError(401,'INVALID_SESSION','Authentication required or session expired.');}
const validSubject=(s:unknown):s is string=>typeof s==='string' && /^user_[a-zA-Z0-9]{6,150}$/.test(s);
const validSession=(s:unknown):s is string=>typeof s==='string' && /^sess_[a-zA-Z0-9]{6,150}$/.test(s);

export function assertAuthorizedParty(party:unknown,o:Pick<ClerkOptions,'authorizedParties'|'allowNativeWithoutAzp'>):void {
 if(party===undefined && o.allowNativeWithoutAzp===true)return;
 if(typeof party!=='string'||!o.authorizedParties.includes(party))throw invalidSession();
}

export function createClerkIdentityVerifier(o:ClerkOptions):IdentityVerifier {
  validateClerkOptions(o);
  // Bounded positive cache for a single API process; never caches failed checks.
  // Clerk revocations/bans may be observed up to 15 seconds later. Local DB
  // account and membership checks remain live on every authenticated request.
  const positive=new Map<string,number>();
  const TTL_MS=15_000, MAX_ENTRIES=1000;
  return {async verify(token:string):Promise<VerifiedClerkIdentity> {
    if(!token || token.length>8192)throw invalidSession();
    let claims;
    try {
      claims=await verifyToken(token,{
        issuer:o.issuer,secretKey:o.secretKey,jwtKey:o.jwtKey,
        ...(o.audience?{audience:o.audience}:{}),clockSkewInMs:5000,
      });
    }catch {throw invalidSession();}
    if(!validSubject(claims.sub)||!validSession(claims.sid)||claims.iss!==o.issuer)throw invalidSession();
    const party=(claims as {azp?:unknown}).azp;
    assertAuthorizedParty(party,o);
    // JWT signature, expiration and audience above are verified on every call.
    const key=claims.sub+':'+claims.sid;
    const now=Date.now();
    if((positive.get(key)??0)>now)return {subject:claims.sub,sessionId:claims.sid};
    positive.delete(key);
    // Provider failures fail closed for non-cached sessions.
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
    if(positive.size>=MAX_ENTRIES) {
      for(const [k,expiry] of positive)if(expiry<=now)positive.delete(k);
      if(positive.size>=MAX_ENTRIES) {
        const oldest=positive.keys().next().value;
        if(oldest!==undefined)positive.delete(oldest);
      }
    }
    positive.set(key,Date.now()+TTL_MS);
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
  let user=await db.user.findUnique({
    where:{clerkUserId:identity.subject},
    select:{id:true,displayName:true,status:true,deletedAt:true},
  });
  if(!user){
    try {
      const clerkUser = await clerkClient.users.getUser(identity.subject);
      if(clerkUser.banned)throw invalidSession();
      const email = clerkUser.primaryEmailAddress?.verification?.status==='verified'?clerkUser.primaryEmailAddress.emailAddress:null;
      const displayName = [clerkUser.firstName, clerkUser.lastName].filter(Boolean).join(' ') || clerkUser.username || email?.split('@')[0] || 'Supplier User';
      const phone = clerkUser.primaryPhoneNumber?.verification?.status==='verified'?clerkUser.primaryPhoneNumber.phoneNumber:null;
      const created = await (db as PrismaClient).user.create({
        data: {
          clerkUserId: identity.subject,
          displayName,
          email,
          phoneE164: phone,
          status: 'ACTIVE',
        },
        select: {id:true,displayName:true,status:true,deletedAt:true},
      });
      user = created;
    } catch {
      user = await db.user.findUnique({
        where:{clerkUserId:identity.subject},
        select:{id:true,displayName:true,status:true,deletedAt:true},
      });
    }
  }
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
