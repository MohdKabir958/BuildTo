import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {requireAdminPermission,isUuid} from './permissions';
import type {PayoutEvidenceGateway} from './payout-gateway';
import {payoutSelection,payoutDTO,payoutExternalRef,lockSettlement,
 independence,payoutEvent} from './payout-service';

type Tx=Prisma.TransactionClient;
async function postMemo(tx:Tx,id:string,supplierId:string,amount:bigint,utr:string){
 const suffix=supplierId.replaceAll('-');
 const defs=[
  {code:'SUPPLIER_PAYABLE_'+suffix,name:'Supplier payable memorandum'},
  {code:'SUPPLIER_PAYOUT_CLEAR_'+suffix,name:'RazorpayX payout clearing memorandum'}
 ];
 const accounts:string[]=[];
 for(const def of defs){
  const account=await tx.ledgerAccount.upsert({where:{code:def.code},
   create:{...def,active:true,currency:'INR'},update:{},
   select:{id:true,active:true,currency:true}});
  if(!account.active||account.currency!=='INR')
   throw new ApiError(409,'PAYOUT_LEDGER_CLOSED','Supplier payout clearing unavailable.');
  accounts.push(account.id);
 }
 const j=await tx.ledgerJournal.create({data:{
  referenceKey:'payout:processed:'+id,
  eventType:'RAZORPAYX_PAYOUT_PROCESSED_MEMORANDUM',
  lines:{create:[
   {lineNumber:1,accountId:accounts[0],debitPaise:amount,
    memo:'Reduction of exact approved supplier payable'},
   {lineNumber:2,accountId:accounts[1],creditPaise:amount,
    memo:'RazorpayX processed payout UTR '+utr}
  ]}},select:{id:true}});
 await tx.ledgerJournal.update({where:{id:j.id},data:{postedAt:new Date()}});
}
/** Read-only external status lookup, no outbound payout POST and no IO within SQL TX. */
export async function reconcilePayout(db:PrismaClient,userId:string,payoutId:string,
 raw:unknown,gateway:PayoutEvidenceGateway|undefined){
 if(!isUuid(payoutId))throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||
  Object.keys(raw).some(k=>k!=='providerPayoutId'))
  throw new ApiError(400,'INVALID_PAYOUT_RECONCILIATION','Only providerPayoutId accepted.');
 const id=(raw as {providerPayoutId?:unknown}).providerPayoutId;
 if(typeof id!=='string'||!/^pout_[A-Za-z0-9]{8,60}$/.test(id))
  throw new ApiError(400,'PAYOUT_PROVIDER_ID_INVALID','RazorpayX payout ID required.');
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 if(!gateway)throw new ApiError(503,'PAYOUT_PROVIDER_REQUIRED','RazorpayX read-only verification required.');
 const before=await db.payoutTransfer.findUnique({where:{id:payoutId},
  select:{settlementId:true,providerRef:true,amountPaise:true,
   account:{select:{providerTokenRef:true}}}});
 if(!before?.account.providerTokenRef)
  throw new ApiError(404,'NOT_FOUND','Payout destination unavailable.');
 if(before.providerRef&&before.providerRef!==id)
  throw new ApiError(409,'PAYOUT_PROVIDER_ID_CHANGED','Provider payout ID is immutable.');
 const result=await gateway.fetchPayout(id);
 if(result.id!==id||result.fundAccountId!==before.account.providerTokenRef||
  result.referenceId!==payoutExternalRef(payoutId)||
  result.amount!==before.amountPaise||result.currency!=='INR'||result.purpose!=='payout')
  throw new ApiError(409,'PAYOUT_PROVIDER_MISMATCH',
   'Provider amount, fund account and exact external reference must match.');
 if(result.status==='processed'&&(!result.utr||
  !/^[A-Za-z0-9_-]{8,60}$/.test(result.utr)))
  throw new ApiError(409,'PAYOUT_UTR_NOT_AVAILABLE',
   'A provider-processed payout requires its verified bank UTR.');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  await lockSettlement(tx,before.settlementId);
  const record=await tx.payoutTransfer.findUnique({where:{id:payoutId},
   select:payoutSelection});
  if(!record)throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
  await independence(tx,userId,record.settlement.supplierId);
  const creator=await tx.auditEvent.findFirst({where:{
   entityType:'PayoutTransfer',entityId:payoutId,
   action:'PAYOUT_INTENT_RESERVED_NOT_SENT'},select:{actorUserId:true}});
  if(!creator||creator.actorUserId===userId)
   throw new ApiError(403,'PAYOUT_INDEPENDENT_RECONCILIATION_REQUIRED',
    'The payout requester may not review its own provider evidence.');
  if(record.providerRef&&record.providerRef!==result.id||
   record.amountPaise!==result.amount||
   record.account.providerTokenRef!==result.fundAccountId||
   record.account.supplierId!==record.settlement.supplierId)
   throw new ApiError(409,'PAYOUT_EVIDENCE_CHANGED','Destination or payout identity changed.');
  if(record.status==='SUCCEEDED'){
   if(record.providerRef!==result.id||result.status!=='processed')
    throw new ApiError(409,'PAYOUT_ALREADY_FINALIZED','Previously processed payout cannot be rewritten.');
   return {payout:payoutDTO(record),replayed:true,providerStatus:result.status};
  }
  if(record.status==='FAILED')
   throw new ApiError(409,'PAYOUT_TERMINAL_REVIEW_REQUIRED',
    'Failed/reversed transfer requires compensating finance review.');
  if(!['APPROVED','PROCESSING'].includes(record.settlement.status))
   throw new ApiError(409,'PAYOUT_SETTLEMENT_STATE_INVALID','Settlement no longer eligible.');
  const next=result.status==='processed'?'SUCCEEDED':
   ['failed','rejected','cancelled','reversed'].includes(result.status)?
   'FAILED':'PROCESSING';
  if(next==='SUCCEEDED')
   await postMemo(tx,payoutId,record.settlement.supplierId,record.amountPaise,result.utr!);
  const saved=await tx.payoutTransfer.update({where:{id:payoutId},data:{
   status:next,providerRef:result.id,
   ...(next==='SUCCEEDED'?{completedAt:new Date()}:
    next==='FAILED'?{failureCode:'PROVIDER_TERMINAL_REVIEW'}:{})
  },select:payoutSelection});
  const state=next==='SUCCEEDED'?'PAID':next==='FAILED'?'FAILED':'PROCESSING';
  await tx.settlement.update({where:{id:record.settlementId},data:{
   status:state,...(next==='SUCCEEDED'?{paidAt:new Date()}:{})}});
  await payoutEvent(tx,userId,payoutId,next==='SUCCEEDED'?
   'PAYOUT_PROVIDER_PROCESSED':next==='FAILED'?
   'PAYOUT_PROVIDER_TERMINAL_FAILURE':'PAYOUT_PROVIDER_PENDING',{
    providerPayoutId:result.id,providerStatus:result.status,
    providerUtr:result.utr??'',amountPaise:result.amount.toString(),
    bankStatementCrossChecked:false,executedByApi:false});
  return {payout:payoutDTO({...saved,settlement:{...saved.settlement,status:state}}),
   replayed:false,providerStatus:result.status};
 });
}
