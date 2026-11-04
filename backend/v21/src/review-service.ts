import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {publishOutbox} from './outbox';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';

type Tx=Prisma.TransactionClient;
const fields={id:true,customerId:true,supplierOrderId:true,supplierId:true,
 rating:true,comment:true,status:true,createdAt:true} as const;
function dto(r:any,publicView=false){
 return {id:r.id,...(!publicView?{supplierOrderId:r.supplierOrderId}:{}),supplierId:r.supplierId,
  rating:r.rating,comment:r.comment,status:r.status,
  createdAt:r.createdAt.toISOString(),
  ...(!publicView?{customerId:r.customerId}:{})};
}
function uuid(v:unknown){
 if(!isUuid(v))throw new ApiError(404,'NOT_FOUND','Resource not found.');
 return v;
}
function record(v:unknown,allowed:string[]){
 if(!v||typeof v!=='object'||Array.isArray(v)||
   Object.keys(v).some(k=>!allowed.includes(k)))
  throw new ApiError(400,'INVALID_REVIEW_REQUEST','Unexpected review fields.');
 return v as Record<string,unknown>;
}
async function audit(tx:Tx,id:string,actorId:string,action:string,role:string){
 await tx.auditEvent.create({data:{entityType:'Review',entityId:id,
  actorUserId:actorId,actorRole:role,action}});
 await publishOutbox(tx,{eventKey:'review:'+randomUUID(),eventType:action,
  aggregateType:'Review',aggregateId:id,payload:{reviewId:id}});
}
async function lockParent(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
}
/** One review per delivered supplier order. Customer never chooses supplier identity. */
export async function createReview(db:PrismaClient,userId:string,orderId:string,body:unknown){
 uuid(orderId);
 const input=record(body,['supplierOrderId','rating','comment']);
 const supplierOrderId=uuid(input.supplierOrderId);
 if(!Number.isInteger(input.rating)||Number(input.rating)<1||Number(input.rating)>5)
  throw new ApiError(400,'INVALID_RATING','Rating must be an integer from 1 to 5.');
 const comment=input.comment===undefined||input.comment===null?null:input.comment;
 if(comment!==null&&(typeof comment!=='string'||comment.trim().length<8||
   comment.trim().length>1500||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(comment)))
  throw new ApiError(400,'INVALID_REVIEW_COMMENT','Review comment must be 8-1500 characters.');
 return serializable(db,async tx=>{
  await lockParent(tx,orderId);
  const child=await tx.supplierOrder.findFirst({where:{
   id:supplierOrderId,purchaseOrderId:orderId,purchaseOrder:{customerId:userId}
  },select:{id:true,supplierId:true,status:true}});
  if(!child)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
  if(child.status!=='DELIVERED')
   throw new ApiError(409,'REVIEW_NOT_DELIVERED','Review requires completed supplier delivery.');
  const existing=await tx.review.findUnique({where:{supplierOrderId},select:fields});
  if(existing){
   if(existing.customerId!==userId)throw new ApiError(404,'NOT_FOUND','Review not found.');
   throw new ApiError(409,'REVIEW_ALREADY_SUBMITTED','Each supplier order can be reviewed once.');
  }
  const row=await tx.review.create({data:{
   customerId:userId,supplierOrderId,supplierId:child.supplierId,
   rating:input.rating as number,comment:comment===null?null:comment.trim(),status:'PENDING'
  },select:fields});
  await audit(tx,row.id,userId,'CUSTOMER_REVIEW_SUBMITTED','CUSTOMER');
  return dto(row);
 });
}
export async function customerReviews(db:PrismaClient,userId:string,orderId:string){
 uuid(orderId);
 const order=await db.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},select:{id:true}});
 if(!order)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const rows=await db.review.findMany({where:{customerId:userId,
  supplierOrder:{purchaseOrderId:orderId}},select:fields,orderBy:{createdAt:'desc'},take:100});
 return rows.map(r=>dto(r));
}
export async function supplierOwnReviews(db:PrismaClient,userId:string,supplierId:string){
 uuid(supplierId);
 await requireSupplierPermission(db,userId,supplierId,'SUPPLIER_READ');
 const rows=await db.review.findMany({where:{supplierId},
  select:fields,orderBy:{createdAt:'desc'},take:100});
 return rows.map(r=>dto(r));
}
export async function publicSupplierReviews(db:PrismaClient,supplierId:string){
 uuid(supplierId);
 const supplier=await db.supplier.findFirst({where:{id:supplierId,approval:'APPROVED',
  suspendedAt:null},select:{id:true}});
 if(!supplier)throw new ApiError(404,'NOT_FOUND','Supplier not found.');
 const rows=await db.review.findMany({where:{supplierId,status:'PUBLISHED'},
  select:fields,orderBy:{createdAt:'desc'},take:100});
 return rows.map(r=>dto(r,true));
}
export async function adminReviewQueue(db:PrismaClient,adminId:string){
 await requireAdminPermission(db,adminId,'SUPPORT_MANAGE');
 const rows=await db.review.findMany({where:{status:'PENDING'},
  select:fields,orderBy:{createdAt:'asc'},take:100});
 return rows.map(r=>dto(r));
}
export async function moderateReview(db:PrismaClient,adminId:string,reviewId:string,body:unknown){
 uuid(reviewId);
 const input=record(body,['decision']);
 const decision=input.decision;
 if(typeof decision!=='string'||!['PUBLISH','REJECT','HIDE'].includes(decision))
  throw new ApiError(400,'INVALID_REVIEW_DECISION','Use PUBLISH, REJECT or HIDE.');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,adminId,'SUPPORT_MANAGE');
  const found=await tx.review.findUnique({where:{id:reviewId},
   select:{supplierId:true,status:true,supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Review not found.');
  await lockParent(tx,found.supplierOrder.purchaseOrderId);
  const member=await tx.supplierMember.findUnique({where:{
   supplierId_userId:{supplierId:found.supplierId,userId:adminId}},
   select:{active:true,revokedAt:true}});
  if(member?.active&&!member.revokedAt)
   throw new ApiError(403,'INDEPENDENT_MODERATION_REQUIRED',
    'Supplier personnel cannot publish reviews of their own supplier.');
  const target=decision==='PUBLISH'?'PUBLISHED':decision==='REJECT'?'REJECTED':'HIDDEN';
  const previous=await tx.review.findUniqueOrThrow({where:{id:reviewId}});
  if(previous.status===target)return {review:dto(previous),replayed:true};
  if(!((previous.status==='PENDING'&&['PUBLISHED','REJECTED'].includes(target))||
    (previous.status==='PUBLISHED'&&target==='HIDDEN')||
    (previous.status==='HIDDEN'&&target==='PUBLISHED')))
   throw new ApiError(409,'REVIEW_MODERATION_CONFLICT','Review cannot make that moderation transition.');
  const row=await tx.review.update({where:{id:reviewId},
   data:{status:target as 'PUBLISHED'|'REJECTED'|'HIDDEN'},select:fields});
  await audit(tx,reviewId,adminId,'ADMIN_REVIEW_'+target,'ADMIN_SUPPORT');
  return {review:dto(row),replayed:false};
 });
}
