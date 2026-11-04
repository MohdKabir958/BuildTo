import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';
import {publishOutbox} from './outbox';
import type {PayoutEvidenceGateway,PayoutProviderRecord} from './payout-gateway';

type Tx=Prisma.TransactionClient;
const uuid=(x:unknown):string=>{
 if(!isUuid(x))throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
 return x;
};
const input=(raw:unknown,fields:string[]):Record<string,unknown>=>{
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||
  Object.keys(raw).some(k=>!fields.includes(k)))
  throw new ApiError(400,'INVALID_PAYOUT_COMMAND','Unexpected payout fields.');
 return raw as Record<string,unknown>;
};
const selection={
 id:true,settlementId:true,payoutAccountId:true,requestKey:true,providerRef:true,
 amountPaise:true,status:true,failureCode:true,completedAt:true,createdAt:true,
 account:{select:{supplierId:true,bankAccountLast4:true,providerTokenRef:true}},
 settlement:{select:{supplierId:true,status:true,paidAt:true}}
} as const;
type PayoutView=Prisma.PayoutTransferGetPayload<{select:typeof selection}>;
const ref=(id:string)=>'BT'+id.replaceAll('-','').toUpperCase();
function dto(p:PayoutView){
 return {id:p.id,settlementId:p.settlementId,supplierId:p.settlement.supplierId,
  amountPaise:p.amountPaise.toString(),currency:'INR',
  status:p.status,providerPayoutId:p.providerRef,
  externalReferenceId:ref(p.id),maskedBankAccount:p.account.bankAccountLast4?
   '****'+p.account.bankAccountLast4:null,
  createdAt:p.createdAt.toISOString(),completedAt:p.completedAt?.toISOString()??null,
  settlementStatus:p.settlement.status,bankEvidenceType:'PROVIDER_ONLY',
  payoutExecutionByBuildtoApi:false,
  payoutStatusMeaning:p.status==='SUCCEEDED'?'RAZORPAYX_PROCESSED':
   p.status==='PENDING'?'AWAITING_EXTERNAL_ACTION':'PROVIDER_REVIEW_REQUIRED'};
}
async function independence(tx:Tx,userId:string,supplierId:string){
 await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
 const m=await tx.supplierMember.findUnique({where:{
  supplierId_userId:{supplierId,userId}},select:{active:true,revokedAt:true}});
 if(m?.active&&!m.revokedAt)
  throw new ApiError(403,'INDEPENDENT_PAYOUT_FINANCE_REQUIRED',
   'Supplier staff cannot authorize or reconcile their own payout.');
}
async function lockSettlement(tx:Tx,id:string){
 const x=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
 SELECT id FROM "Settlement" WHERE id=${id}::uuid FOR UPDATE`);
 if(!x.length)throw new ApiError(404,'NOT_FOUND','Settlement unavailable.');
}
async function event(tx:Tx,userId:string,payoutId:string,action:string,
 afterState:Prisma.InputJsonObject){
 await tx.auditEvent.create({data:{
  entityType:'PayoutTransfer',entityId:payoutId,actorRole:'ADMIN_FINANCE',
  actorUserId:userId,action,afterState}});
 await publishOutbox(tx,{eventKey:'payout:'+randomUUID(),eventType:action,
  aggregateType:'PayoutTransfer',aggregateId:payoutId,payload:{payoutId}});
}
async function verifySettlementForPayout(tx:Tx,settlementId:string,userId:string){
 const s=await tx.settlement.findUnique({where:{id:settlementId},
  select:{id:true,supplierId:true,approvedById:true,status:true,
   grossPaise:true,commissionPaise:true,refundPaise:true,adjustmentPaise:true,
   payablePaise:true,transfers:{select:{id:true}},
   supplier:{select:{approval:true,suspendedAt:true}},
   lines:{select:{supplierOrderId:true,grossPaise:true,commissionPaise:true,
    refundPaise:true,adjustmentPaise:true,netPaise:true,
    supplierOrder:{select:{status:true,purchaseOrderId:true,
     returnRequests:{where:{status:{notIn:['CANCELLED','REJECTED']}},select:{id:true}}}}
   }}
  }});
 if(!s||s.status!=='APPROVED'||!s.approvedById||s.approvedById===userId||
   s.supplier.approval!=='APPROVED'||s.supplier.suspendedAt)
  throw new ApiError(409,'PAYOUT_SETTLEMENT_NOT_APPROVED',
   'An approved supplier settlement and different payout reviewer are required.');
 await independence(tx,userId,s.supplierId);
 if(!s.lines.length||s.transfers.length||
  s.refundPaise!==0n||s.adjustmentPaise!==0n||
  s.grossPaise<=0n||s.payablePaise<=0n||
  s.grossPaise-s.commissionPaise!==s.payablePaise||
  s.lines.some(l=>l.supplierOrder.status!=='DELIVERED'||l.supplierOrder.returnRequests.length||
   l.refundPaise!==0n||l.adjustmentPaise!==0n||
   l.grossPaise-l.commissionPaise!==l.netPaise)||
  s.lines.reduce((n,l)=>n+l.netPaise,0n)!==s.payablePaise)
  throw new ApiError(409,'PAYOUT_FINANCIAL_MISMATCH',
   'Payout blocked by return, adjustment, duplicate allocation or unreconciled total.');
 const parents=[...new Set(s.lines.map(l=>l.supplierOrder.purchaseOrderId))].sort();
 for(const parentId of parents){
  await tx.$queryRaw(Prisma.sql`SELECT id FROM "PurchaseOrder"
    WHERE id=${parentId}::uuid FOR UPDATE`);
 }
 const refund=await tx.refundRequest.findFirst({where:{purchaseOrderId:{in:parents},
  status:{not:'REJECTED'}},select:{id:true}});
 if(refund)throw new ApiError(409,'PAYOUT_REFUND_HOLD',
  'Payout blocked by existing provider refund claim for this parent order.');
 const due=await tx.supplierCommissionReceivable.findFirst({where:{
  supplierId:s.supplierId,status:{in:['OPEN','PARTIALLY_OFFSET']}
 },select:{id:true}});
 if(due)throw new ApiError(409,'PAYOUT_COD_COMMISSION_HOLD',
  'Uncollected supplier-held COD commission requires a separately approved netting process.');
 const attested=await tx.auditEvent.findFirst({where:{entityType:'Settlement',
  entityId:settlementId,action:'SETTLEMENT_RECONCILIATION_ATTESTED'},
  select:{actorUserId:true}});
 const memo=await tx.ledgerJournal.findUnique({where:{
  referenceKey:'settlement:accrual:'+settlementId},select:{postedAt:true}});
 if(!attested?.actorUserId||!memo?.postedAt)
  throw new ApiError(409,'PAYOUT_SETTLEMENT_EVIDENCE_MISSING',
   'Independent settlement attestation and posted accrued payable are required.');
 return s;
}
/** A PENDING payout intent is NOT execution. No bank account or gateway POST. */
export async function reservePayout(db:PrismaClient,userId:string,settlementId:string,
 key:string,raw:unknown){
 uuid(settlementId);
 const data=input(raw,['payoutAccountId']);
 const accountId=uuid(data.payoutAccountId);
 const result=await executeIdempotently(db,{actorId:userId,
  scope:'finance:payout:'+settlementId,requestKey:key,requestPayload:raw,
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
   await lockSettlement(tx,settlementId);
   const s=await verifySettlementForPayout(tx,settlementId,userId);
   const bank=await tx.supplierPayoutAccount.findFirst({where:{
    id:accountId,supplierId:s.supplierId,
    active:true,verifiedAt:{not:null},validationRef:{not:null},
    providerTokenRef:{not:null}},select:{
     id:true,registeredById:true,approvedById:true}});
   if(!bank||!bank.registeredById||!bank.approvedById||
     bank.registeredById===bank.approvedById||bank.approvedById===userId)
    throw new ApiError(409,'PAYOUT_BENEFICIARY_NOT_APPROVED',
     'A distinct finance administrator must validate beneficiary bank details before payout.');
   const created=await tx.payoutTransfer.create({data:{
    settlementId,payoutAccountId:accountId,amountPaise:s.payablePaise,
    requestKey:key,status:'PENDING'
   },select:{id:true}});
   await event(tx,userId,created.id,'PAYOUT_INTENT_RESERVED_NOT_SENT',{
    settlementId,supplierId:s.supplierId,externalReferenceId:ref(created.id),
    amountPaise:s.payablePaise.toString(),bankProviderPostExecuted:false,
    bankStatementVerifiedByApi:false});
   return {result:created.id,resultRef:created.id,responseCode:201};
  }});
 const saved=await db.payoutTransfer.findUnique({where:{id:result.resultRef},select:selection});
 if(!saved)throw new ApiError(404,'NOT_FOUND','Payout unavailable.');
 return {payout:dto(saved),replayed:result.kind==='replayed'};
}
export async function supplierPayouts(db:PrismaClient,userId:string,supplierId:string){
 uuid(supplierId);
 await requireSupplierPermission(db,userId,supplierId,'FINANCE_READ');
 const payouts=await db.payoutTransfer.findMany({where:{settlement:{supplierId}},
  select:selection,orderBy:{createdAt:'desc'},take:100});
 return payouts.map(dto);
}
export async function adminPayoutQueue(db:PrismaClient,userId:string){
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 const payouts=await db.payoutTransfer.findMany({where:{status:{
  in:['PENDING','PROCESSING','FAILED']}},select:selection,
  orderBy:{createdAt:'asc'},take:100});
 return payouts.map(dto);
}
export {selection as payoutSelection,dto as payoutDTO,ref as payoutExternalRef,
 lockSettlement,independence,event as payoutEvent};
