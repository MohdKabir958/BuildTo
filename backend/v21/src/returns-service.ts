import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {executeIdempotently} from './idempotency';
import {serializable} from './transaction';
import {publishOutbox} from './outbox';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';

type Tx=Prisma.TransactionClient;
const returnSelect={
 id:true,supplierOrderId:true,customerId:true,reason:true,status:true,
 resolutionNote:true,createdAt:true,updatedAt:true,
 items:{select:{supplierOrderItemId:true,quantity:true},orderBy:{supplierOrderItemId:'asc' as const}},
 evidence:{select:{mediaId:true},orderBy:{createdAt:'asc' as const}}
} as const;
function dto(r:any){
 return {id:r.id,supplierOrderId:r.supplierOrderId,customerId:r.customerId,
  reason:r.reason,status:r.status,resolutionNote:r.resolutionNote,
  createdAt:r.createdAt.toISOString(),updatedAt:r.updatedAt.toISOString(),
  items:r.items.map((i:any)=>({orderItemId:i.supplierOrderItemId,quantity:i.quantity.toString()})),
  evidenceMediaIds:r.evidence.map((e:any)=>e.mediaId),
  financialStatus:'NOT_REFUNDED'};
}
function uuid(v:unknown):string{
 if(!isUuid(v))throw new ApiError(404,'NOT_FOUND','Resource not found.');
 return v;
}
function inputRecord(v:unknown,fields:string[]):Record<string,unknown>{
 if(!v||typeof v!=='object'||Array.isArray(v)||
   Object.keys(v).some(k=>!fields.includes(k)))
  throw new ApiError(400,'INVALID_RETURN_REQUEST','Unexpected return request fields.');
 return v as Record<string,unknown>;
}
function text(v:unknown,min:number,max:number){
 if(typeof v!=='string'||v.trim().length<min||v.trim().length>max||
    /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v))
  throw new ApiError(400,'INVALID_RETURN_REASON','Reason or resolution note has an invalid format.');
 return v.trim();
}
function decimal(v:unknown){
 if(typeof v!=='string'||!/^[0-9]{1,14}(?:\.[0-9]{1,3})?$/.test(v))
  throw new ApiError(400,'INVALID_RETURN_QUANTITY','Quantity must be an exact positive decimal string.');
 const n=new Prisma.Decimal(v);
 if(!n.gt(0))throw new ApiError(400,'INVALID_RETURN_QUANTITY','Quantity must be positive.');
 return n;
}
async function lockParent(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
}
async function event(tx:Tx,entityId:string,actorId:string,action:string,role:string){
 await tx.auditEvent.create({data:{entityType:'ReturnRequest',entityId,
  actorUserId:actorId,actorRole:role,action}});
 await publishOutbox(tx,{eventKey:'return:'+randomUUID(),eventType:action,
  aggregateType:'ReturnRequest',aggregateId:entityId,payload:{returnId:entityId}});
}
function parse(body:unknown){
 const data=inputRecord(body,['supplierOrderId','reason','items','evidenceMediaIds']);
 const supplierOrderId=uuid(data.supplierOrderId);
 const reason=text(data.reason,12,300);
 if(!Array.isArray(data.items)||data.items.length===0||data.items.length>40)
  throw new ApiError(400,'RETURN_LINES_REQUIRED','Provide 1-40 return lines.');
 const seen=new Set<string>();
 const items=data.items.map(x=>{
  const v=inputRecord(x,['orderItemId','quantity']);
  const orderItemId=uuid(v.orderItemId);
  if(seen.has(orderItemId))throw new ApiError(400,'RETURN_ITEM_DUPLICATE','Duplicate order line.');
  seen.add(orderItemId);
  return {orderItemId,quantity:decimal(v.quantity)};
 });
 const evidenceMediaIds=data.evidenceMediaIds===undefined?[]:data.evidenceMediaIds;
 if(!Array.isArray(evidenceMediaIds)||evidenceMediaIds.length>8||
    evidenceMediaIds.some(x=>!isUuid(x))||
    new Set(evidenceMediaIds).size!==evidenceMediaIds.length)
  throw new ApiError(400,'INVALID_RETURN_EVIDENCE','Invalid evidence identifiers.');
 return {supplierOrderId,reason,items,evidenceMediaIds:evidenceMediaIds as string[]};
}
/** Single parent-order lock serializes independent requests for the same delivered units. */
export async function createReturn(db:PrismaClient,customerId:string,orderId:string,key:string,body:unknown){
 uuid(orderId);
 const cmd=parse(body);
 const result=await executeIdempotently(db,{actorId:customerId,
  scope:'returns:'+orderId,requestKey:key,requestPayload:body,
  expiresAt:new Date(Date.now()+24*60*60*1000),
  execute:async tx=>{
   await lockParent(tx,orderId);
   const child=await tx.supplierOrder.findFirst({where:{
    id:cmd.supplierOrderId,purchaseOrderId:orderId,purchaseOrder:{customerId}
   },select:{id:true,status:true,items:{select:{
    id:true,quantity:true,shipmentLines:{select:{
     deliveredQty:true,returnedQty:true,shipment:{select:{status:true}}}}
   }}}});
   if(!child)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
   if(!['PARTIALLY_DELIVERED','DELIVERED'].includes(child.status))
    throw new ApiError(409,'RETURN_NOT_DELIVERED','Only delivered quantities are eligible for return review.');
   const existing=await tx.returnItem.findMany({where:{
    orderItem:{supplierOrderId:child.id},
    returnRequest:{status:{notIn:['REJECTED','CANCELLED']}}
   },select:{supplierOrderItemId:true,quantity:true}});
   const allocated=new Map<string,Prisma.Decimal>();
   for(const x of existing)allocated.set(x.supplierOrderItemId,
    (allocated.get(x.supplierOrderItemId)??new Prisma.Decimal(0)).plus(x.quantity));
   const owned=new Map(child.items.map(i=>[i.id,i]));
   for(const line of cmd.items){
    const item=owned.get(line.orderItemId);
    if(!item)throw new ApiError(404,'NOT_FOUND','Return line does not belong to this supplier order.');
    const delivered=item.shipmentLines
      .filter(s=>s.shipment.status==='DELIVERED')
      .reduce((sum,s)=>sum.plus(s.deliveredQty.minus(s.returnedQty)),new Prisma.Decimal(0));
    if(delivered.lt(line.quantity.plus(allocated.get(line.orderItemId)??new Prisma.Decimal(0))))
     throw new ApiError(409,'RETURN_QUANTITY_EXCEEDED','Requested units exceed available delivered, unclaimed quantities.');
   }
   if(cmd.evidenceMediaIds.length){
    const media=await tx.mediaAsset.findMany({where:{
     id:{in:cmd.evidenceMediaIds},ownerUserId:customerId
    },select:{id:true}});
    if(media.length!==cmd.evidenceMediaIds.length)
     throw new ApiError(404,'NOT_FOUND','Owned return evidence not found.');
   }
   const created=await tx.returnRequest.create({data:{
    supplierOrderId:child.id,customerId,reason:cmd.reason,
    items:{create:cmd.items.map(i=>({supplierOrderItemId:i.orderItemId,quantity:i.quantity}))},
    ...(cmd.evidenceMediaIds.length?{evidence:{create:cmd.evidenceMediaIds.map(mediaId=>({mediaId}))}}:{})
   },select:{id:true}});
   await event(tx,created.id,customerId,'CUSTOMER_RETURN_REQUESTED','CUSTOMER');
   return {result:created.id,resultRef:created.id,responseCode:201};
  }});
 const found=await db.returnRequest.findFirst({where:{id:result.resultRef,customerId,
  supplierOrder:{purchaseOrderId:orderId}},select:returnSelect});
 if(!found)throw new ApiError(404,'NOT_FOUND','Return not found.');
 return {value:dto(found),replayed:result.kind==='replayed'};
}
export async function customerReturns(db:PrismaClient,customerId:string,orderId:string){
 uuid(orderId);
 const owned=await db.purchaseOrder.findFirst({where:{id:orderId,customerId},select:{id:true}});
 if(!owned)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const rows=await db.returnRequest.findMany({where:{customerId,
  supplierOrder:{purchaseOrderId:orderId}},select:returnSelect,
  orderBy:{createdAt:'desc'},take:100});
 return rows.map(dto);
}
export async function supplierReturns(db:PrismaClient,userId:string,supplierId:string,childId:string){
 uuid(supplierId);uuid(childId);
 await requireSupplierPermission(db,userId,supplierId,'SUPPLIER_READ');
 const child=await db.supplierOrder.findFirst({where:{id:childId,supplierId},select:{id:true}});
 if(!child)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 const rows=await db.returnRequest.findMany({where:{supplierOrderId:childId},
  select:returnSelect,orderBy:{createdAt:'desc'},take:100});
 return rows.map(dto);
}
export async function customerCancelReturn(db:PrismaClient,customerId:string,returnId:string){
 uuid(returnId);
 return serializable(db,async tx=>{
  const found=await tx.returnRequest.findFirst({where:{id:returnId,customerId},
   select:{id:true,status:true,supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Return not found.');
  await lockParent(tx,found.supplierOrder.purchaseOrderId);
  const current=await tx.returnRequest.findUniqueOrThrow({where:{id:returnId}});
  if(current.status==='CANCELLED')return {id:returnId,status:'CANCELLED',replayed:true};
  if(current.status!=='REQUESTED')
   throw new ApiError(409,'RETURN_REVIEW_STARTED','A return under review cannot be cancelled without support.');
  await tx.returnRequest.update({where:{id:returnId},data:{status:'CANCELLED'}});
  await event(tx,returnId,customerId,'CUSTOMER_RETURN_CANCELLED','CUSTOMER');
  return {id:returnId,status:'CANCELLED',replayed:false};
 });
}
export async function adminReturns(db:PrismaClient,adminId:string){
 await requireAdminPermission(db,adminId,'SUPPORT_MANAGE');
 const rows=await db.returnRequest.findMany({where:{
  status:{in:['REQUESTED','UNDER_REVIEW','APPROVED','IN_TRANSIT','RECEIVED']}
 },select:returnSelect,orderBy:{createdAt:'asc'},take:100});
 return rows.map(dto);
}
/** Support reviews the claim only. No refund or credit note is created here. */
export async function adminReviewReturn(db:PrismaClient,adminId:string,returnId:string,body:unknown){
 uuid(returnId);
 const input=inputRecord(body,['decision','note']);
 const decision=input.decision;
 if(!['REVIEW','APPROVE','REJECT'].includes(decision))
  throw new ApiError(400,'INVALID_RETURN_DECISION','Use REVIEW, APPROVE or REJECT.');
 const note=text(input.note,12,500);
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,adminId,'SUPPORT_MANAGE');
  const found=await tx.returnRequest.findUnique({where:{id:returnId},
   select:{id:true,status:true,supplierOrder:{select:{purchaseOrderId:true,supplierId:true}}}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Return not found.');
  await lockParent(tx,found.supplierOrder.purchaseOrderId);
  const current=await tx.returnRequest.findUniqueOrThrow({where:{id:returnId}});
  if(!['REQUESTED','UNDER_REVIEW'].includes(current.status))
   throw new ApiError(409,'RETURN_ALREADY_DECIDED','Return has already been decided.');
  const member=await tx.supplierMember.findUnique({where:{
   supplierId_userId:{supplierId:found.supplierOrder.supplierId,userId:adminId}},
   select:{active:true,revokedAt:true}});
  if(member?.active&&!member.revokedAt)
   throw new ApiError(403,'INDEPENDENT_RETURN_REVIEW_REQUIRED','Supplier personnel cannot approve their own return claims.');
  const next=decision==='REVIEW'?'UNDER_REVIEW':decision==='APPROVE'?'APPROVED':'REJECTED';
  await tx.returnRequest.update({where:{id:returnId},data:{status:next,resolutionNote:note}});
  await event(tx,returnId,adminId,'RETURN_'+next,'ADMIN_SUPPORT');
  return {id:returnId,status:next,financialStatus:'NOT_REFUNDED'};
 });
}
/** Physical receipt, not payment, must never restock goods without inspection. */
export async function supplierReceiveReturn(db:PrismaClient,userId:string,supplierId:string,returnId:string,body:unknown){
 uuid(supplierId);uuid(returnId);inputRecord(body,[]);
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const found=await tx.returnRequest.findFirst({where:{
   id:returnId,supplierOrder:{supplierId}
  },select:{id:true,status:true,supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Return not found.');
  await lockParent(tx,found.supplierOrder.purchaseOrderId);
  const current=await tx.returnRequest.findUniqueOrThrow({where:{id:returnId}});
  if(current.status==='RECEIVED')return {id:returnId,status:'RECEIVED',replayed:true,financialStatus:'NOT_REFUNDED'};
  if(!['APPROVED','IN_TRANSIT'].includes(current.status))
   throw new ApiError(409,'RETURN_NOT_APPROVED','Return must be independently approved before receipt.');
  await tx.returnRequest.update({where:{id:returnId},data:{status:'RECEIVED'}});
  await event(tx,returnId,userId,'SUPPLIER_RETURN_PHYSICALLY_RECEIVED','SUPPLIER_FULFILLMENT');
  return {id:returnId,status:'RECEIVED',replayed:false,financialStatus:'NOT_REFUNDED'};
 });
}
