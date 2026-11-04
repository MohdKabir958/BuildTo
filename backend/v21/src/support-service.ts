import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {publishOutbox} from './outbox';
import {isUuid,requireAdminPermission} from './permissions';

type Tx=Prisma.TransactionClient;
const summarySelect={id:true,publicNumber:true,customerId:true,purchaseOrderId:true,
 subject:true,priority:true,status:true,assigneeId:true,createdAt:true,resolvedAt:true} as const;
const messageSelect={id:true,authorId:true,body:true,internal:true,createdAt:true} as const;
function summary(c:any){return {id:c.id,publicNumber:c.publicNumber,
 orderId:c.purchaseOrderId,subject:c.subject,priority:c.priority,status:c.status,
 createdAt:c.createdAt.toISOString(),resolvedAt:c.resolvedAt?.toISOString()??null};}
function message(m:any){return {id:m.id,authorId:m.authorId,body:m.body,
 internal:m.internal,createdAt:m.createdAt.toISOString()};}
function uuid(v:unknown){if(!isUuid(v))throw new ApiError(404,'NOT_FOUND','Resource not found.');return v;}
function record(v:unknown,allowed:string[]){
 if(!v||typeof v!=='object'||Array.isArray(v)||
   Object.keys(v).some(k=>!allowed.includes(k)))
  throw new ApiError(400,'INVALID_SUPPORT_REQUEST','Unexpected support request fields.');
 return v as Record<string,unknown>;
}
function text(v:unknown,min:number,max:number){
 if(typeof v!=='string'||v.trim().length<min||v.trim().length>max||
  /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v))
  throw new ApiError(400,'INVALID_SUPPORT_TEXT','Support text has an invalid format.');
 return v.trim();
}
async function event(tx:Tx,id:string,actorId:string,action:string,role:string){
 await tx.auditEvent.create({data:{entityType:'SupportCase',entityId:id,
  actorUserId:actorId,actorRole:role,action}});
 await publishOutbox(tx,{eventKey:'support:'+randomUUID(),eventType:action,
  aggregateType:'SupportCase',aggregateId:id,payload:{caseId:id}});
}
async function lock(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "SupportCase" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Support case not found.');
}
export async function createSupportCase(db:PrismaClient,userId:string,key:string,body:unknown){
 const data=record(body,['orderId','subject','message']);
 const orderId=data.orderId===undefined||data.orderId===null?null:uuid(data.orderId);
 const subject=text(data.subject,8,250),initial=text(data.message,8,3000);
 const result=await executeIdempotently(db,{actorId:userId,scope:'support-case',
  requestKey:key,requestPayload:body,expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   if(orderId&&!await tx.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},
      select:{id:true}}))
    throw new ApiError(404,'NOT_FOUND','Order not found.');
   const row=await tx.supportCase.create({data:{
    publicNumber:'SUP-'+randomUUID().replaceAll('-','').slice(0,28).toUpperCase(),
    customerId:userId,purchaseOrderId:orderId,subject,status:'OPEN',
    messages:{create:{authorId:userId,body:initial,internal:false}}
   },select:{id:true}});
   await event(tx,row.id,userId,'CUSTOMER_SUPPORT_CASE_OPENED','CUSTOMER');
   return {result:row.id,resultRef:row.id,responseCode:201};
  }});
 const c=await db.supportCase.findFirst({where:{id:result.resultRef,customerId:userId},
  select:summarySelect});
 if(!c)throw new ApiError(404,'NOT_FOUND','Support case not found.');
 return {value:summary(c),replayed:result.kind==='replayed'};
}
export async function customerCases(db:PrismaClient,userId:string){
 const rows=await db.supportCase.findMany({where:{customerId:userId},
  select:summarySelect,orderBy:{createdAt:'desc'},take:100});
 return rows.map(summary);
}
export async function getSupportCase(db:PrismaClient,userId:string,id:string,admin=false){
 uuid(id);
 if(admin)await requireAdminPermission(db,userId,'SUPPORT_MANAGE');
 const row=await db.supportCase.findFirst({where:{id,...(admin?{}:{customerId:userId})},
  select:{...summarySelect,messages:{
   where:admin?{}:{internal:false},select:messageSelect,
   orderBy:{createdAt:'asc' as const},take:200}}});
 if(!row)throw new ApiError(404,'NOT_FOUND','Support case not found.');
 return {...summary(row),messages:row.messages.map(message)};
}
export async function postSupportMessage(db:PrismaClient,userId:string,id:string,body:unknown,admin=false){
 uuid(id);
 const input=record(body,admin?['message','internal']:['message']);
 const content=text(input.message,2,3000);
 if(admin&&input.internal!==undefined&&typeof input.internal!=='boolean')
  throw new ApiError(400,'INVALID_SUPPORT_VISIBILITY','Internal visibility must be boolean.');
 if(admin)await requireAdminPermission(db,userId,'SUPPORT_MANAGE');
 return serializable(db,async tx=>{
  await lock(tx,id);
  const c=await tx.supportCase.findUniqueOrThrow({where:{id}});
  if(!admin&&c.customerId!==userId)throw new ApiError(404,'NOT_FOUND','Support case not found.');
  if(c.status==='CLOSED')throw new ApiError(409,'SUPPORT_CASE_CLOSED','Closed cases cannot accept messages.');
  if(c.status==='RESOLVED'&&!admin)
   await tx.supportCase.update({where:{id},data:{status:'IN_PROGRESS',resolvedAt:null}});
  const entry=await tx.supportMessage.create({data:{
   caseId:id,authorId:userId,body:content,internal:admin&&input.internal===true
  },select:messageSelect});
  await event(tx,id,userId,admin?'ADMIN_SUPPORT_MESSAGE':'CUSTOMER_SUPPORT_MESSAGE',
   admin?'ADMIN_SUPPORT':'CUSTOMER');
  return message(entry);
 });
}
export async function adminCases(db:PrismaClient,adminId:string){
 await requireAdminPermission(db,adminId,'SUPPORT_MANAGE');
 const rows=await db.supportCase.findMany({where:{status:{not:'CLOSED'}},
  select:summarySelect,orderBy:{createdAt:'asc'},take:100});
 return rows.map(summary);
}
export async function adminUpdateCase(db:PrismaClient,adminId:string,id:string,body:unknown){
 uuid(id);
 const input=record(body,['status','note']);
 const status=input.status;
 if(!['ASSIGNED','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED'].includes(status as string))
  throw new ApiError(400,'INVALID_SUPPORT_STATUS','Invalid support status.');
 const note=input.note===undefined?null:text(input.note,8,3000);
 if((status==='RESOLVED'||status==='CLOSED')&&!note)
  throw new ApiError(400,'SUPPORT_RESOLUTION_NOTE_REQUIRED','A customer-visible resolution note is required.');
 await requireAdminPermission(db,adminId,'SUPPORT_MANAGE');
 return serializable(db,async tx=>{
  await lock(tx,id);
  const c=await tx.supportCase.findUniqueOrThrow({where:{id}});
  if(c.status==='CLOSED')throw new ApiError(409,'SUPPORT_CASE_CLOSED','Closed cases are terminal.');
  if(status==='CLOSED'&&c.status!=='RESOLVED')
   throw new ApiError(409,'SUPPORT_RESOLVE_FIRST','Resolve a case before closing it.');
  if(c.status==='RESOLVED'&&status!=='CLOSED'&&status!=='IN_PROGRESS')
   throw new ApiError(409,'SUPPORT_STATE_CONFLICT','Resolved case cannot skip re-opening.');
  const next=status as 'ASSIGNED'|'IN_PROGRESS'|'WAITING_CUSTOMER'|'RESOLVED'|'CLOSED';
  const updated=await tx.supportCase.update({where:{id},data:{
   status:next,assigneeId:adminId,
   resolvedAt:['RESOLVED','CLOSED'].includes(next)?(c.resolvedAt??new Date()):null
  },select:summarySelect});
  if(note)await tx.supportMessage.create({data:{caseId:id,
   authorId:adminId,body:note,internal:false}});
  await event(tx,id,adminId,'ADMIN_SUPPORT_'+next,'ADMIN_SUPPORT');
  return summary(updated);
 });
}
