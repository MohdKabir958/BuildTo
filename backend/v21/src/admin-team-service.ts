import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission,isUuid} from './permissions';
import type {AdminRole} from './permissions';

const ROLES:readonly AdminRole[]=['OWNER','OPERATIONS','CATALOG','FINANCE','SUPPORT','AUDITOR'];
const MEMBER_SELECT={
 userId:true,role:true,active:true,createdAt:true,revokedAt:true,
 user:{select:{displayName:true,email:true,status:true,deletedAt:true}},
} as const;
type Member={
 userId:string;role:AdminRole;active:boolean;createdAt:Date;revokedAt:Date|null;
 user:{displayName:string;email:string|null;status:string;deletedAt:Date|null};
};
const present=(x:Member)=>({
 userId:x.userId,role:x.role,active:x.active&&x.revokedAt===null&&x.user.status==='ACTIVE'&&x.user.deletedAt===null,
 displayName:x.user.displayName,email:x.user.email,
 createdAt:x.createdAt.toISOString(),revokedAt:x.revokedAt?.toISOString()??null,
});
const obj=(x:unknown):Record<string,unknown>=>{
 if(!x||typeof x!=='object'||Array.isArray(x))throw new ApiError(400,'INVALID_INPUT','Expected a JSON object.');
 return x as Record<string,unknown>;
};
function fields(x:Record<string,unknown>,names:string[]){
 if(Object.keys(x).some(k=>!names.includes(k)))throw new ApiError(400,'INVALID_INPUT','Unexpected input field.');
}
function role(x:unknown):AdminRole {
 if(typeof x!=='string'||!ROLES.includes(x as AdminRole))throw new ApiError(400,'INVALID_ROLE','Choose an authorized admin role.');
 return x as AdminRole;
}
function reason(x:unknown):string {
 if(typeof x!=='string'||x.trim().length<8||x.trim().length>400)
   throw new ApiError(400,'AUDIT_REASON_REQUIRED','A meaningful 8–400 character reason is required.');
 return x.trim();
}
function email(x:unknown):string {
 if(typeof x!=='string')throw new ApiError(400,'INVALID_EMAIL','Provide a verified email address.');
 const value=x.trim().toLowerCase();
 if(value.length>320||! /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))
   throw new ApiError(400,'INVALID_EMAIL','Provide a verified email address.');
 return value;
}
function uuid(x:string):string {
 if(!isUuid(x))throw new ApiError(404,'NOT_FOUND','Administrator not found.');
 return x;
}
async function lockTeam(tx:Prisma.TransactionClient,actorId:string) {
 // One global short-lived transaction lock prevents concurrent last-owner changes.
 await tx.$queryRaw(Prisma.sql`SELECT pg_advisory_xact_lock(81631121::bigint) IS NULL AS locked`);
 await requireAdminPermission(tx,actorId,'TEAM_MANAGE');
}
async function ensureAnotherOwner(tx:Prisma.TransactionClient,member:{role:AdminRole;active:boolean;revokedAt:Date|null}) {
 if(member.role!=='OWNER'||!member.active||member.revokedAt)return;
 const owners=await tx.adminMembership.count({where:{
   role:'OWNER',active:true,revokedAt:null,user:{status:'ACTIVE',deletedAt:null},
 }});
 if(owners<=1)throw new ApiError(409,'LAST_OWNER','At least one active owner must remain.');
}
const audit=(tx:Prisma.TransactionClient,actorId:string,targetId:string,action:string,before:Prisma.InputJsonObject,after:Prisma.InputJsonObject)=>
 tx.auditEvent.create({data:{
   actorUserId:actorId,actorRole:'ADMIN_OWNER',action,
   entityType:'AdminMembership',entityId:targetId,beforeState:before,afterState:after,
 }});

export async function listAdminTeam(db:PrismaClient,actorId:string,query:{cursor?:string;limit?:number}={}) {
 await requireAdminPermission(db,actorId,'TEAM_MANAGE');
 const limit=query.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>100)
   throw new ApiError(400,'INVALID_LIMIT','Limit must be between 1 and 100.');
 if(query.cursor!==undefined)uuid(query.cursor);
 const members=await db.adminMembership.findMany({
   where:query.cursor?{userId:{gt:query.cursor}}:{},
   select:MEMBER_SELECT,orderBy:{userId:'asc'},take:limit+1,
 });
 const next=members.length>limit;
 const data=members.slice(0,limit);
 return {items:data.map(present),nextCursor:next?data[data.length-1].userId:null};
}

export async function grantAdmin(db:PrismaClient,actorId:string,input:unknown) {
 const data=obj(input);fields(data,['email','role','reason']);
 const targetEmail=email(data.email),newRole=role(data.role),why=reason(data.reason);
 return serializable(db,async tx=>{
   await lockTeam(tx,actorId);
   // Email comes from Clerk's verified primary contact synchronized by signed webhook.
   const user=await tx.user.findUnique({
     where:{email:targetEmail},
     select:{id:true,clerkUserId:true,status:true,deletedAt:true},
   });
   if(!user||!user.clerkUserId||user.status!=='ACTIVE'||user.deletedAt)
     throw new ApiError(404,'USER_NOT_PROVISIONED','An active verified Clerk user with this email is required.');
   if(user.id===actorId)throw new ApiError(409,'SELF_MANAGEMENT_DENIED','Owners cannot modify their own access.');
   await tx.$queryRaw(Prisma.sql`SELECT id FROM "User" WHERE id=${user.id}::uuid FOR SHARE`);
   const previous=await tx.adminMembership.findUnique({where:{userId:user.id}});
   if(previous?.active&&!previous.revokedAt)
     throw new ApiError(409,'ADMIN_ALREADY_ACTIVE','This user already has active administrator access.');
   const saved=await tx.adminMembership.upsert({
     where:{userId:user.id},
     create:{userId:user.id,role:newRole,active:true,grantedById:actorId},
     update:{role:newRole,active:true,revokedAt:null,grantedById:actorId},
     select:MEMBER_SELECT,
   });
   await audit(tx,actorId,user.id,'ADMIN_ACCESS_GRANTED',
     {role:previous?.role??null,active:previous?.active??false},
     {role:newRole,active:true,reason:why});
   return present(saved);
 });
}

export async function changeAdminRole(db:PrismaClient,actorId:string,targetId:string,input:unknown) {
 uuid(targetId);const data=obj(input);fields(data,['role','reason']);
 const newRole=role(data.role),why=reason(data.reason);
 if(targetId===actorId)throw new ApiError(409,'SELF_MANAGEMENT_DENIED','Owners cannot modify their own access.');
 return serializable(db,async tx=>{
   await lockTeam(tx,actorId);
   const existing=await tx.adminMembership.findUnique({where:{userId:targetId}});
   if(!existing||!existing.active||existing.revokedAt)
     throw new ApiError(404,'NOT_FOUND','Active administrator not found.');
   if(existing.role===newRole)throw new ApiError(409,'NO_ROLE_CHANGE','Administrator already has this role.');
   await ensureAnotherOwner(tx,existing);
   const saved=await tx.adminMembership.update({
     where:{userId:targetId},data:{role:newRole,grantedById:actorId},
     select:MEMBER_SELECT,
   });
   await audit(tx,actorId,targetId,'ADMIN_ROLE_CHANGED',
     {role:existing.role,active:true},{role:newRole,active:true,reason:why});
   return present(saved);
 });
}

export async function revokeAdmin(db:PrismaClient,actorId:string,targetId:string,input:unknown) {
 uuid(targetId);const data=obj(input);fields(data,['reason']);
 const why=reason(data.reason);
 if(targetId===actorId)throw new ApiError(409,'SELF_MANAGEMENT_DENIED','Owners cannot revoke themselves.');
 return serializable(db,async tx=>{
   await lockTeam(tx,actorId);
   const existing=await tx.adminMembership.findUnique({where:{userId:targetId}});
   if(!existing||!existing.active||existing.revokedAt)
     throw new ApiError(404,'NOT_FOUND','Active administrator not found.');
   await ensureAnotherOwner(tx,existing);
   const saved=await tx.adminMembership.update({
     where:{userId:targetId},data:{active:false,revokedAt:new Date()},select:MEMBER_SELECT,
   });
   await audit(tx,actorId,targetId,'ADMIN_ACCESS_REVOKED',
     {role:existing.role,active:true},{role:existing.role,active:false,reason:why});
   return present(saved);
 });
}
