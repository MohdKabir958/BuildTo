import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {publishOutbox} from './outbox';
import {isUuid,requireAdminPermission} from './permissions';

export type Tx=Prisma.TransactionClient;
export function uuid(x:unknown):string{
 if(!isUuid(x))throw new ApiError(404,'NOT_FOUND','Refund unavailable.');
 return x;
}
export function input(x:unknown,fields:string[]):Record<string,unknown>{
 if(!x||typeof x!=='object'||Array.isArray(x)||
  Object.keys(x).some(k=>!fields.includes(k)))
  throw new ApiError(400,'INVALID_REFUND_COMMAND','Unexpected refund fields.');
 return x as Record<string,unknown>;
}
export const refundSelect={
 id:true,purchaseOrderId:true,paymentAttemptId:true,returnRequestId:true,
 amountPaise:true,status:true,providerRefundRef:true,reason:true,
 approvedAt:true,completedAt:true,createdAt:true
} as const;
export function refundDTO(row:{id:string;purchaseOrderId:string;returnRequestId:string|null;
 amountPaise:bigint;status:string;providerRefundRef:string|null;reason:string;
 approvedAt:Date|null;completedAt:Date|null;createdAt:Date}){
 return {id:row.id,orderId:row.purchaseOrderId,returnRequestId:row.returnRequestId,
  status:row.status,provider:'RAZORPAY',currency:'INR',
  amountPaise:row.amountPaise.toString(),providerRefundId:row.providerRefundRef,
  approvalAt:row.approvedAt?.toISOString()??null,
  providerCompletedAt:row.completedAt?.toISOString()??null,
  customerBankCredit:'NOT_VERIFIED',
  createdAt:row.createdAt.toISOString(),reason:row.reason};
}
export async function lockParent(tx:Tx,orderId:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
 SELECT id FROM "PurchaseOrder" WHERE id=${orderId}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Refund order unavailable.');
}
export async function independent(tx:Tx,userId:string,supplierId:string){
 const member=await tx.supplierMember.findUnique({where:{
  supplierId_userId:{supplierId,userId}},select:{active:true,revokedAt:true}});
 if(member?.active&&!member.revokedAt)
  throw new ApiError(403,'INDEPENDENT_REFUND_FINANCE_REQUIRED',
   'Supplier personnel cannot authorize refunds against their own seller.');
}
export async function refundEvent(tx:Tx,userId:string,refundId:string,action:string,fields?:Prisma.InputJsonObject){
 await tx.auditEvent.create({data:{entityType:'RefundRequest',entityId:refundId,
  actorUserId:userId,actorRole:'ADMIN_FINANCE',action,
  ...(fields?{afterState:fields}:{})}});
 await publishOutbox(tx,{eventKey:'refund:'+randomUUID(),eventType:action,
  aggregateType:'RefundRequest',aggregateId:refundId,payload:{refundId}});
}
export type RefundEvidence={
 returnId:string;supplierId:string;purchaseOrderId:string;amountPaise:bigint;
 paymentId:string;providerPayRef:string;creditNoteId:string;sourceInvoiceId:string;
};
/** Complete physical return + legal GST note + one verified parent Razorpay capture. */
export async function refundEvidence(tx:Tx,returnId:string):Promise<RefundEvidence>{
 const r=await tx.returnRequest.findUnique({where:{id:returnId},select:{
  id:true,status:true,customerId:true,
  supplierOrder:{select:{supplierId:true,purchaseOrderId:true,status:true,
   totalPaise:true,
   settlementLines:{where:{settlement:{status:{not:'CANCELLED'}}},select:{id:true}},
   purchaseOrder:{select:{currency:true,totalPaise:true,customerId:true,
    payments:{select:{id:true,provider:true,status:true,capturedPaise:true,
     amountPaise:true,providerPayRef:true,verifiedAt:true}}
   }}
  }},
  creditNote:{select:{id:true,kind:true,status:true,sourceInvoiceId:true,
   totalPaise:true,taxablePaise:true,taxPaise:true,sourceInvoice:{select:{
    id:true,kind:true,status:true,totalPaise:true}}}}
 }});
 if(!r||r.status!=='RECEIVED'||!r.creditNote||
   r.supplierOrder.status!=='DELIVERED'||r.creditNote.kind!=='CREDIT_NOTE'||
   r.creditNote.status!=='ISSUED'||!r.creditNote.sourceInvoice||
   r.creditNote.sourceInvoice.kind!=='TAX_INVOICE'||
   r.creditNote.sourceInvoice.status!=='ISSUED'||
   r.creditNote.sourceInvoice.totalPaise!==r.creditNote.totalPaise||
   r.creditNote.taxablePaise+r.creditNote.taxPaise!==r.creditNote.totalPaise||
   r.creditNote.totalPaise!==r.supplierOrder.totalPaise||
   r.customerId!==r.supplierOrder.purchaseOrder.customerId||
   r.supplierOrder.settlementLines.length)
  throw new ApiError(409,'REFUND_EVIDENCE_INCOMPLETE',
   'Verified full return, issued statutory credit note and unsettled seller required.');
 const order=r.supplierOrder.purchaseOrder;
 if(order.currency!=='INR'||order.payments.length!==1)
  throw new ApiError(409,'REFUND_VERIFIED_CAPTURE_REQUIRED','One exact capture is required.');
 const payment=order.payments[0];
 if(payment.provider!=='RAZORPAY'||payment.status!=='CAPTURED'||
   !payment.verifiedAt||!payment.providerPayRef||
   payment.amountPaise!==order.totalPaise||payment.capturedPaise!==order.totalPaise)
  throw new ApiError(409,'REFUND_VERIFIED_CAPTURE_REQUIRED',
   'Supplier-held COD and unverified Razorpay attempts are not online refunds.');
 return {returnId:r.id,supplierId:r.supplierOrder.supplierId,
  purchaseOrderId:r.supplierOrder.purchaseOrderId,
  amountPaise:r.supplierOrder.totalPaise,paymentId:payment.id,
  providerPayRef:payment.providerPayRef,creditNoteId:r.creditNote.id,
  sourceInvoiceId:r.creditNote.sourceInvoiceId!};
}
export async function requestFullRefund(db:PrismaClient,userId:string,
 returnId:string,key:string,body:unknown){
 uuid(returnId);input(body,[]);
 const result=await executeIdempotently(db,{actorId:userId,
  scope:'finance:refund:'+returnId,requestKey:key,requestPayload:body,
  expiresAt:new Date(Date.now()+86400000),execute:async tx=>{
   await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
   const found=await tx.returnRequest.findUnique({where:{id:returnId},
    select:{supplierOrder:{select:{purchaseOrderId:true}}}});
   if(!found)throw new ApiError(404,'NOT_FOUND','Return unavailable.');
   await lockParent(tx,found.supplierOrder.purchaseOrderId);
   const proof=await refundEvidence(tx,returnId);
   await independent(tx,userId,proof.supplierId);
   if(await tx.refundRequest.findUnique({where:{returnRequestId:returnId}}))
    throw new ApiError(409,'RETURN_REFUND_ALREADY_REQUESTED','One refund per returned supplier order.');
   const row=await tx.refundRequest.create({data:{
    purchaseOrderId:proof.purchaseOrderId,paymentAttemptId:proof.paymentId,
    returnRequestId:returnId,requestKey:key,amountPaise:proof.amountPaise,
    reason:'Full supplier-order return: '+returnId,status:'REQUESTED'
   },select:{id:true}});
   await refundEvent(tx,userId,row.id,'REFUND_REQUESTED_RESERVED',{
    returnRequestId:returnId,creditNoteId:proof.creditNoteId,
    amountPaise:proof.amountPaise.toString(),providerRefundCreated:false});
   return {result:row.id,resultRef:row.id,responseCode:201};
  }});
 const row=await db.refundRequest.findUnique({where:{id:result.resultRef},select:refundSelect});
 if(!row)throw new ApiError(404,'NOT_FOUND','Refund unavailable.');
 return {refund:refundDTO(row),replayed:result.kind==='replayed'};
}
export async function approveFullRefund(db:PrismaClient,userId:string,refundId:string,body:unknown){
 uuid(refundId);input(body,[]);
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  const before=await tx.refundRequest.findUnique({where:{id:refundId},
   select:{returnRequestId:true,purchaseOrderId:true,status:true,
    amountPaise:true,paymentAttemptId:true}});
  if(!before?.returnRequestId)throw new ApiError(404,'NOT_FOUND','Refund unavailable.');
  await lockParent(tx,before.purchaseOrderId);
  const proof=await refundEvidence(tx,before.returnRequestId);
  await independent(tx,userId,proof.supplierId);
  const maker=await tx.auditEvent.findFirst({where:{
   entityType:'RefundRequest',entityId:refundId,action:'REFUND_REQUESTED_RESERVED'
  },select:{actorUserId:true}});
  if(!maker||maker.actorUserId===userId)
   throw new ApiError(403,'INDEPENDENT_REFUND_APPROVAL_REQUIRED','Requester cannot approve own refund.');
  if(before.status!=='REQUESTED')
   throw new ApiError(409,'REFUND_ALREADY_DECIDED','Only requested refunds may be approved.');
  if(before.amountPaise!==proof.amountPaise||
   before.paymentAttemptId!==proof.paymentId||
   before.purchaseOrderId!==proof.purchaseOrderId)
   throw new ApiError(409,'REFUND_SNAPSHOT_MISMATCH','Refund amount or capture changed.');
  const approved=await tx.refundRequest.update({where:{id:refundId},
   data:{status:'APPROVED',approvedById:userId,approvedAt:new Date()},
   select:refundSelect});
  await refundEvent(tx,userId,refundId,'REFUND_INDEPENDENTLY_APPROVED',{
   creditNoteId:proof.creditNoteId,sourceInvoiceId:proof.sourceInvoiceId,
   providerRefundCreated:false,refundExecution:'EXTERNAL_MANUAL_ONLY'});
  return refundDTO(approved);
 });
}
export async function customerRefunds(db:PrismaClient,userId:string,orderId:string){
 uuid(orderId);
 const order=await db.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},
  select:{id:true}});
 if(!order)throw new ApiError(404,'NOT_FOUND','Order unavailable.');
 const rows=await db.refundRequest.findMany({where:{purchaseOrderId:orderId,
  returnRequestId:{not:null}},select:refundSelect,
  orderBy:{createdAt:'desc'},take:50});
 return rows.map(refundDTO);
}
export async function financeRefundQueue(db:PrismaClient,userId:string){
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 const rows=await db.refundRequest.findMany({where:{returnRequestId:{not:null},
  status:{in:['REQUESTED','APPROVED','PROCESSING','MANUAL_REVIEW']}},
  select:refundSelect,orderBy:{createdAt:'asc'},take:100});
 return rows.map(refundDTO);
}
