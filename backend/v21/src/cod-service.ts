import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {commitOrderItemStock} from './inventory-reservations';
import {requireSupplierPermission,requireAdminPermission,isUuid} from './permissions';
import {publishOutbox} from './outbox';

type Tx=Prisma.TransactionClient;
const keyValid=(s:unknown):s is string=>typeof s==='string'&&/^[A-Za-z0-9:_-]{8,140}$/.test(s);
const record=(body:unknown,keys:string[]):Record<string,unknown>=>{
 if(!body||typeof body!=='object'||Array.isArray(body)||
  Object.keys(body).some(k=>!keys.includes(k)))
  throw new ApiError(400,'INVALID_COD_REQUEST','Unexpected COD request fields.');
 return body as Record<string,unknown>;
};
function requiredText(v:unknown,field:string,min:number,max:number,pattern:RegExp){
 if(typeof v!=='string'||v.trim().length<min||v.trim().length>max||!pattern.test(v.trim()))
  throw new ApiError(400,'INVALID_'+field.toUpperCase(),field+' has an invalid format.');
 return v.trim();
}
async function lockParent(tx:Tx,id:string) {
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
 SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE
 `);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
}
async function event(tx:Tx,aggregateId:string,actorId:string,action:string,role:string) {
 await tx.auditEvent.create({data:{
  action,entityType:'PurchaseOrder',entityId:aggregateId,
  actorUserId:actorId,actorRole:role
 }});
 await publishOutbox(tx,{eventKey:'cod:'+randomUUID(),eventType:action,
  aggregateType:'PurchaseOrder',aggregateId,payload:{orderId:aggregateId}});
}

/** Customer chooses COD once, before any gateway attempt. This is not payment evidence. */
export async function selectCod(db:PrismaClient,customerId:string,orderId:string,key:string,body:unknown) {
 if(!isUuid(orderId))throw new ApiError(400,'INVALID_ORDER_ID','Invalid order reference.');
 if(!keyValid(key))throw new ApiError(400,'BAD_IDEMPOTENCY_KEY','Idempotency-Key is required.');
 record(body,[]);
 return serializable(db,async tx=>{
  await lockParent(tx,orderId);
  const order=await tx.purchaseOrder.findFirst({where:{id:orderId,customerId},
   select:{id:true,status:true,currency:true,totalPaise:true,
    supplierOrders:{select:{id:true,status:true,items:{select:{
     listingId:true,quantity:true,reservations:{
      select:{id:true,state:true,quantity:true,expiresAt:true}
     }}}}},payments:{select:{id:true,provider:true,paymentMethod:true,
      idempotencyKey:true,status:true}}}});
  if(!order)throw new ApiError(404,'NOT_FOUND','Order not found.');
  const replay=order.payments.find(p=>p.provider==='MANUAL'&&p.paymentMethod==='COD'&&p.idempotencyKey===key);
  if(replay)return {orderId,method:'COD' as const,status:'COLLECTION_DUE' as const,
   amountPaise:order.totalPaise.toString(),replayed:true};
  // A timed-out gateway order can capture later; do NOT allow mixing COD with
  // any previous gateway attempt, even if it now appears failed.
  if(order.payments.length)
   throw new ApiError(409,'PAYMENT_METHOD_LOCKED','Payment is already selected for this order.');
  if(order.status!=='PLACED'||order.currency!=='INR'||order.totalPaise<=0n||
   order.supplierOrders.length===0)
   throw new ApiError(409,'ORDER_NOT_COD_ELIGIBLE','Order cannot switch to COD.');
  const items=order.supplierOrders.flatMap(s=>s.items);
  if(order.supplierOrders.some(s=>s.status!=='PENDING_ACCEPTANCE')||
   !items.length||items.some(i=>!i.listingId))
   throw new ApiError(409,'COD_STOCK_UNSUPPORTED',
    'COD requires a complete warehouse-backed order pending supplier acceptance.');
  const holds=items.flatMap(i=>i.reservations.filter(r=>r.state==='HELD'));
  if(items.some(i=>!i.reservations.filter(r=>r.state==='HELD')
     .reduce((a,r)=>a.plus(r.quantity),new Prisma.Decimal(0)).eq(i.quantity))||
     holds.some(h=>!h.expiresAt||h.expiresAt.getTime()<=Date.now()+10_000))
   throw new ApiError(409,'STOCK_RESERVATION_EXPIRED','Recreate checkout to obtain new valid stock holds.');
  await tx.paymentAttempt.create({data:{
   purchaseOrderId:orderId,provider:'MANUAL',paymentMethod:'COD',
   idempotencyKey:key,amountPaise:order.totalPaise,status:'PENDING'
  }});
  for(const hold of holds.sort((a,b)=>a.id.localeCompare(b.id)))
   await commitOrderItemStock(tx,hold.id);
  await tx.purchaseOrder.update({where:{id:orderId},data:{status:'CONFIRMED'}});
  await event(tx,orderId,customerId,'ORDER_COD_SELECTED','CUSTOMER_COD');
  return {orderId,method:'COD' as const,status:'COLLECTION_DUE' as const,
   amountPaise:order.totalPaise.toString(),replayed:false};
 });
}
const receiptSelect={
 id:true,supplierOrderId:true,supplierId:true,shipmentId:true,receiptNumber:true,
 collectedPaise:true,status:true,receivedAt:true,verifiedAt:true
} as const;
function receiptDTO(r:{id:string;supplierOrderId:string;supplierId:string;
 shipmentId:string|null;receiptNumber:string;collectedPaise:bigint;
 status:string;receivedAt:Date;verifiedAt:Date|null}) {
 return {id:r.id,supplierOrderId:r.supplierOrderId,supplierId:r.supplierId,
  shipmentId:r.shipmentId,receiptNumber:r.receiptNumber,
  collectedPaise:r.collectedPaise.toString(),currency:'INR',status:r.status,
  receivedAt:r.receivedAt.toISOString(),verifiedAt:r.verifiedAt?.toISOString()??null};
}
/** Supplier record is an unverified CLAIM of cash; never marks an order paid. */
export async function recordCod(db:PrismaClient,userId:string,supplierId:string,
 supplierOrderId:string,key:string,body:unknown) {
 if(!isUuid(supplierId)||!isUuid(supplierOrderId))
  throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 if(!keyValid(key))throw new ApiError(400,'BAD_IDEMPOTENCY_KEY','Idempotency-Key is required.');
 const input=record(body,['shipmentId','receiptNumber','note']);
 const shipmentId=input.shipmentId;
 if(!isUuid(shipmentId))throw new ApiError(400,'INVALID_SHIPMENT_ID','A delivered shipment is required.');
 const receiptNumber=requiredText(input.receiptNumber,'receipt_number',3,100,/^[A-Za-z0-9][A-Za-z0-9./_-]{2,99}$/);
 const note=input.note===undefined?null:requiredText(input.note,'note',8,300,/^[^\x00-\x1f\x7f]{8,300}$/);
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const lookup=await tx.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
   select:{purchaseOrderId:true}});
  if(!lookup)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
  await lockParent(tx,lookup.purchaseOrderId);
  const order=await tx.supplierOrder.findUniqueOrThrow({where:{id:supplierOrderId},
   select:{id:true,supplierId:true,status:true,totalPaise:true,codRecordedPaise:true,
    purchaseOrder:{select:{id:true,payments:{select:{provider:true,paymentMethod:true,status:true}}}},
    shipments:{where:{id:shipmentId},select:{id:true,status:true,deliveredAt:true,
     handoverMethod:true,otpVerifiedAt:true,exceptionApprovedAt:true}}
   }});
  const existing=await tx.codCollection.findUnique({where:{
   supplierOrderId_idempotencyKey:{supplierOrderId,idempotencyKey:key}
  },select:receiptSelect});
  if(existing){
   if(existing.receiptNumber!==receiptNumber||existing.shipmentId!==shipmentId)
    throw new ApiError(409,'IDEMPOTENCY_KEY_REUSED','COD receipt differs from previous request.');
   return {receipt:receiptDTO(existing),replayed:true};
  }
  if(order.status!=='DELIVERED'||order.totalPaise<=0n)
   throw new ApiError(409,'COD_NOT_DELIVERED','COD collection requires a delivered supplier order.');
  if(order.purchaseOrder.payments.length!==1||
   !order.purchaseOrder.payments.some(p=>p.provider==='MANUAL'&&p.paymentMethod==='COD'&&p.status==='PENDING'))
   throw new ApiError(409,'COD_NOT_SELECTED','Customer has not selected COD.');
  const shipment=order.shipments[0];
  if(!shipment||shipment.status!=='DELIVERED'||!shipment.deliveredAt||
   !((shipment.handoverMethod==='OTP'&&shipment.otpVerifiedAt)||
    (shipment.handoverMethod==='APPROVED_EXCEPTION'&&shipment.exceptionApprovedAt)))
   throw new ApiError(409,'DELIVERY_PROOF_REQUIRED','Verified shipment handover is required.');
  if(order.codRecordedPaise!==0n)
   throw new ApiError(409,'COD_RECEIPT_ALREADY_RECORDED','A COD receipt already exists.');
  // The DB trigger atomically increments SupplierOrder.codRecordedPaise and
  // checks it never exceeds the exact immutable supplier order total.
  const receipt=await tx.codCollection.create({data:{
   supplierOrderId,supplierId,shipmentId,idempotencyKey:key,
   receiptNumber,collectedPaise:order.totalPaise,
   collectedByUserId:userId,collectorName:null,note,
   status:'RECORDED'
  },select:receiptSelect});
  await event(tx,lookup.purchaseOrderId,userId,'SUPPLIER_COD_RECORDED_UNVERIFIED','SUPPLIER_FULFILLMENT');
  return {receipt:receiptDTO(receipt),replayed:false};
 });
}
export async function listSupplierCod(db:PrismaClient,userId:string,supplierId:string,supplierOrderId:string){
 await requireSupplierPermission(db,userId,supplierId,'FINANCE_READ');
 const so=await db.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},select:{id:true}});
 if(!so)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 const entries=await db.codCollection.findMany({where:{supplierOrderId,supplierId},
  select:receiptSelect,orderBy:{receivedAt:'desc'},take:50});
 return entries.map(receiptDTO);
}
/** Independent finance approval posts a balanced supplier-held-cash memorandum.
 * This does NOT record money in Buildto's own bank or Razorpay accounts.
 */
export async function reviewCod(db:PrismaClient,adminId:string,receiptId:string,body:unknown){
 if(!isUuid(receiptId))throw new ApiError(404,'NOT_FOUND','COD receipt not found.');
 const input=record(body,['decision','externalReference']);
 const decision=input.decision;
 if(decision!=='VERIFY'&&decision!=='DISPUTE')
  throw new ApiError(400,'INVALID_COD_DECISION','Use VERIFY or DISPUTE.');
 const externalReference=decision==='VERIFY'?
  requiredText(input.externalReference,'external_reference',8,100,/^[A-Za-z0-9][A-Za-z0-9._:/-]{7,99}$/):null;
 if(decision==='DISPUTE'&&input.externalReference!==undefined)
  throw new ApiError(400,'INVALID_COD_REQUEST','Dispute does not accept a verification reference.');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,adminId,'FINANCE_MANAGE');
  const lookup=await tx.codCollection.findUnique({where:{id:receiptId},
   select:{supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!lookup)throw new ApiError(404,'NOT_FOUND','COD receipt not found.');
  await lockParent(tx,lookup.supplierOrder.purchaseOrderId);
  const r=await tx.codCollection.findUniqueOrThrow({where:{id:receiptId},
   select:{id:true,status:true,collectedByUserId:true,supplierId:true,
    supplierOrderId:true,collectedPaise:true,
    supplierOrder:{select:{totalPaise:true,status:true,codRecordedPaise:true,codVerifiedPaise:true}},
    receiptNumber:true,shipmentId:true,receivedAt:true,verifiedAt:true}});
  if(r.status==='VERIFIED'&&decision==='VERIFY')
   return {receipt:receiptDTO(r),replayed:true};
  if(r.status==='DISPUTED'&&decision==='DISPUTE')
   return {receipt:receiptDTO(r),replayed:true};
  if(r.status!=='RECORDED')
   throw new ApiError(409,'COD_RECEIPT_FINALIZED','COD receipt cannot be changed after review.');
  const member=await tx.supplierMember.findUnique({where:{
   supplierId_userId:{supplierId:r.supplierId,userId:adminId}
  },select:{active:true,revokedAt:true}});
  if(r.collectedByUserId===adminId||(member?.active&&!member.revokedAt))
   throw new ApiError(403,'COD_REQUIRES_INDEPENDENT_REVIEW',
    'Supplier collection and finance verification must be independently staffed.');
  if(decision==='DISPUTE'){
   const updated=await tx.codCollection.update({where:{id:r.id},data:{
    status:'DISPUTED'
   },select:receiptSelect});
   await event(tx,lookup.supplierOrder.purchaseOrderId,adminId,
    'COD_COLLECTION_DISPUTED','ADMIN_FINANCE');
   return {receipt:receiptDTO(updated),replayed:false};
  }
  if(r.supplierOrder.codRecordedPaise!==r.supplierOrder.totalPaise||
   r.supplierOrder.codVerifiedPaise!==0n||
   r.collectedPaise!==r.supplierOrder.totalPaise||
   r.supplierOrder.status!=='DELIVERED')
   throw new ApiError(409,'COD_AMOUNT_MISMATCH','Recorded delivery and COD totals do not reconcile.');
  const cashCode='COD_SUPPLIER_CASH_'+r.supplierId.replaceAll('-','');
  const controlCode='COD_CUSTOMER_RECEIVABLE_'+r.supplierId.replaceAll('-','');
  const cash=await tx.ledgerAccount.upsert({where:{code:cashCode},
   create:{code:cashCode,name:'Supplier-held COD cash memorandum',currency:'INR',active:true},
   update:{},select:{id:true,active:true}});
  const contra=await tx.ledgerAccount.upsert({where:{code:controlCode},
   create:{code:controlCode,name:'COD customer receipt memorandum contra',currency:'INR',active:true},
   update:{},select:{id:true,active:true}});
  if(!cash.active||!contra.active)throw new ApiError(409,'COD_LEDGER_CLOSED','COD ledger is unavailable.');
  const referenceKey='cod:verified:'+r.id;
  // Immutable balanced lines are posted BEFORE the COD trigger verifies the
  // receipt, within the same transaction: all-or-nothing.
  const journal=await tx.ledgerJournal.create({data:{
   referenceKey,eventType:'COD_SUPPLIER_HELD_CASH_MEMORANDUM',
   lines:{create:[
    {lineNumber:1,accountId:cash.id,debitPaise:r.collectedPaise,
     memo:'Independent COD confirmation '+externalReference},
    {lineNumber:2,accountId:contra.id,creditPaise:r.collectedPaise,
     memo:'Not platform bank cash: supplier holds proceeds'}
   ]}
  },select:{id:true}});
  await tx.ledgerJournal.update({where:{id:journal.id},data:{postedAt:new Date()}});
  const updated=await tx.codCollection.update({where:{id:r.id},data:{
   status:'VERIFIED',verifiedByUserId:adminId,verifiedAt:new Date(),
   journalReference:referenceKey
  },select:receiptSelect});
  await event(tx,lookup.supplierOrder.purchaseOrderId,adminId,
   'COD_COLLECTION_INDEPENDENTLY_VERIFIED','ADMIN_FINANCE');
  return {receipt:receiptDTO(updated),replayed:false};
 });
}
