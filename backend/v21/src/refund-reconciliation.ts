import {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission} from './permissions';
import type {PaymentGateway,GatewayRefund} from './payment-gateway';
import {uuid,input,refundSelect,refundDTO,lockParent,independent,
 refundEvent,refundEvidence,Tx} from './refund-service';

/** This API ONLY looks up a refund created outside Buildto in Razorpay Dashboard.
 * It cannot issue a provider refund POST. No network call inside Postgres TX.
 * A matching pending refund is NOT a success; customer bank credit is not attested.
 */
export async function reconcileRefund(db:PrismaClient,userId:string,
 refundId:string,body:unknown,gateway:PaymentGateway|undefined){
 uuid(refundId);
 const b=input(body,['providerRefundId']);
 if(typeof b.providerRefundId!=='string'||!/^rfnd_[A-Za-z0-9]{8,60}$/.test(b.providerRefundId))
  throw new ApiError(400,'INVALID_PROVIDER_REFUND_ID','Valid Razorpay refund ID required.');
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 if(!gateway?.lookupRefund)
  throw new ApiError(503,'REFUND_PROVIDER_LOOKUP_REQUIRED','Configured read-only Razorpay refund lookup is mandatory.');
 const before=await db.refundRequest.findUnique({where:{id:refundId},
  select:{id:true,status:true,returnRequestId:true,amountPaise:true,
   providerRefundRef:true,purchaseOrderId:true,
   paymentAttempt:{select:{providerPayRef:true,provider:true,status:true}}}});
 if(!before?.returnRequestId)throw new ApiError(404,'NOT_FOUND','Refund unavailable.');
 if(!['APPROVED','PROCESSING','SUCCEEDED'].includes(before.status))
  throw new ApiError(409,'REFUND_NOT_APPROVED','Refund requires independent approval.');
 if(before.providerRefundRef&&before.providerRefundRef!==b.providerRefundId)
  throw new ApiError(409,'REFUND_PROVIDER_REF_CONFLICT','Provider refund identity is immutable.');
 const provider=await gateway.lookupRefund(b.providerRefundId);
 if(provider.id!==b.providerRefundId||provider.currency!=='INR'||
   provider.amount!==before.amountPaise||
   provider.paymentId!==before.paymentAttempt.providerPayRef||
   before.paymentAttempt.provider!=='RAZORPAY'||
   before.paymentAttempt.status!=='CAPTURED'||
   !['processed','pending','failed'].includes(provider.status))
  throw new ApiError(409,'REFUND_PROVIDER_EVIDENCE_MISMATCH',
   'Razorpay payment, refund status, currency and exact paise must match authorized refund.');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  await lockParent(tx,before.purchaseOrderId);
  const state=await tx.refundRequest.findUniqueOrThrow({where:{id:refundId},
   select:refundSelect});
  const proof=await refundEvidence(tx,before.returnRequestId!);
  await independent(tx,userId,proof.supplierId);
  if(state.amountPaise!==proof.amountPaise||
   state.paymentAttemptId!==proof.paymentId||
   state.purchaseOrderId!==proof.purchaseOrderId)
   throw new ApiError(409,'REFUND_SNAPSHOT_CHANGED','Source payment or invoice changed.');
  if(state.providerRefundRef&&state.providerRefundRef!==provider.id)
   throw new ApiError(409,'REFUND_PROVIDER_REF_CONFLICT','Refund belongs to another provider reference.');
  if(state.status==='SUCCEEDED'){
   if(state.providerRefundRef!==provider.id||provider.status!=='processed')
    throw new ApiError(409,'REFUND_FINALIZED','Verified refund status is immutable.');
   return {refund:refundDTO(state),replayed:true,providerStatus:'processed'};
  }
  if(!['APPROVED','PROCESSING'].includes(state.status))
   throw new ApiError(409,'REFUND_NOT_APPROVED','Invalid refund reconciliation transition.');
  const next=provider.status==='processed'?'SUCCEEDED':
   provider.status==='pending'?'PROCESSING':'MANUAL_REVIEW';
  if(next==='SUCCEEDED')await postRefundMemo(tx,refundId,proof.supplierId,
   proof.amountPaise,provider);
  const saved=await tx.refundRequest.update({where:{id:refundId},data:{
   status:next,providerRefundRef:provider.id,
   ...(next==='SUCCEEDED'?{completedAt:new Date()}:{})
  },select:refundSelect});
  await refundEvent(tx,userId,refundId,next==='SUCCEEDED'?
   'RAZORPAY_REFUND_PROCESSED_CONFIRMED':next==='PROCESSING'?
   'RAZORPAY_REFUND_PENDING':'RAZORPAY_REFUND_MANUAL_REVIEW',{
   providerRefundId:provider.id,providerStatus:provider.status,
   amountPaise:provider.amount.toString(),customerBankCreditVerified:false,
   refundCreatedByBuildto:false});
  return {refund:refundDTO(saved),replayed:false,providerStatus:provider.status};
 });
}
async function postRefundMemo(tx:Tx,refundId:string,supplierId:string,
 amount:bigint,provider:GatewayRefund){
 const suffix=supplierId.replaceAll('-','');
 const info=[
  {code:'CUSTOMER_REFUND_CLEAR_'+suffix,
   name:'Razorpay processed refund memorandum clearing'},
  {code:'ONLINE_REFUND_OUTFLOW_'+suffix,
   name:'Provider refunded amount memorandum contra'}
 ];
 const accounts:string[]=[];
 for(const item of info){
  const a=await tx.ledgerAccount.upsert({where:{code:item.code},
   create:{code:item.code,name:item.name,active:true,currency:'INR'},update:{},
   select:{id:true,active:true,currency:true}});
  if(!a.active||a.currency!=='INR')
   throw new ApiError(409,'REFUND_LEDGER_ACCOUNT_CLOSED','Refund ledger is unavailable.');
  accounts.push(a.id);
 }
 const posted=await tx.ledgerJournal.create({data:{
  referenceKey:'refund:processed:'+refundId,
  eventType:'RAZORPAY_REFUND_PROCESSED_MEMORANDUM',
  lines:{create:[
   {lineNumber:1,accountId:accounts[0],debitPaise:amount,
    memo:'Razorpay refund processed; bank credit to customer not directly verified'},
   {lineNumber:2,accountId:accounts[1],creditPaise:amount,
    memo:'Provider reference '+provider.id}
  ]}},select:{id:true}});
 await tx.ledgerJournal.update({where:{id:posted.id},data:{postedAt:new Date()}});
}
