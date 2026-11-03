import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';

export interface ClerkWebhookHeaders {
 id:string|undefined;
 timestamp:string|undefined;
 signature:string|undefined;
}
export type ClerkSyncEvent={type:'user.created'|'user.updated'|'user.deleted';subject:string;displayName:string};
export interface VerifiedClerkWebhook {
 messageId:string;event:ClerkSyncEvent;digest:string;
}
function invalidWebhook():ApiError {
  return new ApiError(401,'INVALID_WEBHOOK_SIGNATURE','Invalid webhook signature.');
}
export function verifyClerkWebhook(
 body:Buffer,headers:ClerkWebhookHeaders,secret:string,nowMs=Date.now()
):VerifiedClerkWebhook|null {
  if(!Buffer.isBuffer(body)||body.length===0||body.length>65536)throw invalidWebhook();
  const {id,timestamp,signature}=headers;
  if(!id||!/^msg_[A-Za-z0-9_-]{5,120}$/.test(id) || !timestamp ||
     !/^[0-9]{10}$/.test(timestamp) || !signature || signature.length>2000)throw invalidWebhook();
  const age=Math.abs(nowMs-Number(timestamp)*1000);
  if(!Number.isFinite(age)||age>300_000)throw invalidWebhook();
  if(!secret.startsWith('whsec_'))throw new Error('V21_CLERK_WEBHOOK_SECRET_INVALID');
  const key=Buffer.from(secret.slice(6),'base64');
  if(key.length<24)throw new Error('V21_CLERK_WEBHOOK_SECRET_INVALID');
  const digest=createHmac('sha256',key).update(id+'.'+timestamp+'.').update(body).digest();
  let valid=false;
  for(const part of signature.split(' ')){
    const match=/^v1,([a-zA-Z0-9+/=]{40,})$/.exec(part);
    if(!match)continue;
    const candidate=Buffer.from(match[1],'base64');
    if(candidate.length===digest.length && timingSafeEqual(candidate,digest))valid=true;
  }
  if(!valid)throw invalidWebhook();
  let payload:unknown;
  try {payload=JSON.parse(body.toString('utf8'));}catch{throw new ApiError(400,'INVALID_WEBHOOK_PAYLOAD','Invalid webhook payload.');}
  if(!payload || typeof payload!=='object'||Array.isArray(payload))throw new ApiError(400,'INVALID_WEBHOOK_PAYLOAD','Invalid webhook payload.');
  const p=payload as {type?:unknown;data?:unknown};
  if(p.type!=='user.created'&&p.type!=='user.updated'&&p.type!=='user.deleted')return null;
  if(!p.data||typeof p.data!=='object'||Array.isArray(p.data))throw new ApiError(400,'INVALID_WEBHOOK_PAYLOAD','Invalid user data.');
  const data=p.data as {id?:unknown;first_name?:unknown;last_name?:unknown};
  if(typeof data.id!=='string'||!/^user_[a-zA-Z0-9]{6,150}$/.test(data.id))
    throw new ApiError(400,'INVALID_WEBHOOK_PAYLOAD','Invalid provider user subject.');
  const normalizeName=(v:unknown)=>typeof v==='string'?v.replace(/[\x00-\x1f\x7f]/g,' ').trim().slice(0,70):'';
  const displayName=[normalizeName(data.first_name),normalizeName(data.last_name)].filter(Boolean).join(' ').slice(0,160)||'Buildto customer';
  return {
    messageId:id,
    digest:createHash('sha256').update(body).digest('hex'),
    event:{type:p.type,subject:data.id,displayName}
  };
}
export async function synchronizeClerkWebhook(db:PrismaClient,verified:VerifiedClerkWebhook):
 Promise<{duplicate:boolean;action:string}> {
  const {event,messageId,digest}=verified;
  const eventKey='clerk.receipt:'+createHash('sha256').update(messageId).digest('hex');
  return db.$transaction(async tx=>{
    // Distributed race protection for provider retries and out-of-order updates per subject.
    await tx.$queryRaw(Prisma.sql`SELECT pg_advisory_xact_lock(hashtextextended(${event.subject}, 18371)) IS NULL AS locked`);
    const previous=await tx.outboxEvent.findUnique({where:{eventKey},select:{payload:true}});
    if(previous) {
      const previousDigest=(previous.payload as {digest?:unknown})?.digest;
      if(previousDigest!==digest)throw new ApiError(409,'WEBHOOK_REPLAY_CONFLICT','Webhook replay conflicts with previous delivery.');
      return {duplicate:true,action:'duplicate'};
    }
    const existing=await tx.user.findUnique({where:{clerkUserId:event.subject},select:{id:true,status:true,deletedAt:true}});
    let userId:string;
    let action:string;
    if(event.type==='user.deleted') {
      const deletionTime=new Date();
      if(!existing){
        const created=await tx.user.create({data:{
          clerkUserId:event.subject,displayName:'Deleted account',status:'CLOSED',deletedAt:deletionTime,
        },select:{id:true}});
        userId=created.id;
      }else{
        userId=existing.id;
        if(existing.status!=='CLOSED'||!existing.deletedAt)await tx.user.update({
          where:{id:existing.id},data:{status:'CLOSED',deletedAt:deletionTime}
        });
      }
      await tx.adminMembership.updateMany({where:{userId,active:true},data:{active:false,revokedAt:deletionTime}});
      await tx.supplierMember.updateMany({where:{userId,active:true},data:{active:false,revokedAt:deletionTime}});
      action='CLERK_USER_DELETED';
    }else if(!existing){
      const created=await tx.user.create({data:{
        clerkUserId:event.subject,displayName:event.displayName,status:'ACTIVE'
      },select:{id:true}});
      userId=created.id;action='CLERK_USER_PROVISIONED';
    }else{
      userId=existing.id;
      // Deletion is terminal; stale user.updated/created must NEVER reopen a deleted account.
      if(existing.deletedAt||existing.status==='CLOSED')action='CLERK_UPDATE_IGNORED_CLOSED';
      else{
        if(event.type==='user.updated')await tx.user.update({where:{id:userId},data:{displayName:event.displayName}});
        action='CLERK_USER_SYNCED';
      }
    }
    // Explicit replay receipt not delivered by generic outbox workers. Never includes PII/raw payload.
    await tx.outboxEvent.create({data:{
      eventKey,eventType:'CLERK_WEBHOOK_RECEIPT',aggregateType:'User',aggregateId:userId,
      payload:{digest,type:event.type},status:'DELIVERED',deliveredAt:new Date(),
    }});
    await tx.auditEvent.create({data:{
      action,entityType:'User',entityId:userId,actorUserId:null,actorRole:'CLERK_SIGNED_WEBHOOK',
    }});
    return {duplicate:false,action};
  },{isolationLevel:Prisma.TransactionIsolationLevel.Serializable,maxWait:5000,timeout:10000});
}
