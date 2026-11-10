
import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {verifiedCapturedPayment} from './payment-funding';
import {executeIdempotently} from './idempotency';
import {publishOutbox} from './outbox';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';

type Tx=Prisma.TransactionClient;
const blockedReturns=['REQUESTED','UNDER_REVIEW','APPROVED','IN_TRANSIT','RECEIVED'] as const;
const blockedRefunds=['REQUESTED','APPROVED','PROCESSING','SUCCEEDED','MANUAL_REVIEW'] as const;
function uuid(v:unknown):string {
 if(!isUuid(v))throw new ApiError(404,'NOT_FOUND','Resource not found.');
 return v;
}
function body(v:unknown,keys:string[]):Record<string,unknown>{
 if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).some(k=>!keys.includes(k)))
  throw new ApiError(400,'INVALID_FINANCE_REQUEST','Unexpected finance request fields.');
 return v as Record<string,unknown>;
}
function text(v:unknown,min:number,max:number,field:string){
 if(typeof v!=='string'||v.trim().length<min||v.trim().length>max||
   !/^[A-Za-z0-9][A-Za-z0-9_./:\- ]*$/.test(v.trim()))
  throw new ApiError(400,'INVALID_'+field.toUpperCase(),field+' has invalid format.');
 return v.trim();
}
function date(v:unknown):Date {
 if(typeof v!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(v))
  throw new ApiError(400,'INVALID_SETTLEMENT_PERIOD','Use a UTC ISO timestamp.');
 const d=new Date(v);
 if(Number.isNaN(d.getTime()))throw new ApiError(400,'INVALID_SETTLEMENT_PERIOD','Invalid date.');
 return d;
}
async function lockParent(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Purchase order unavailable.');
}
async function audit(tx:Tx,entity:string,entityId:string,userId:string,action:string,afterState?:Prisma.InputJsonObject){
 await tx.auditEvent.create({data:{entityType:entity,entityId,
  actorUserId:userId,actorRole:'ADMIN_FINANCE',action,
  ...(afterState?{afterState}:{})}});
 await publishOutbox(tx,{eventKey:'finance:'+randomUUID(),eventType:action,
  aggregateType:entity,aggregateId:entityId,payload:{entityId}});
}
const settlementSelect={
 id:true,supplierId:true,settlementKey:true,periodStart:true,periodEnd:true,
 status:true,grossPaise:true,commissionPaise:true,refundPaise:true,
 adjustmentPaise:true,payablePaise:true,approvedById:true,paidAt:true,createdAt:true,
 lines:{select:{supplierOrderId:true,grossPaise:true,commissionPaise:true,
  refundPaise:true,adjustmentPaise:true,netPaise:true},orderBy:{supplierOrderId:'asc' as const}},
 transfers:{select:{id:true,status:true,amountPaise:true,createdAt:true}}
} as const;
function settlementDTO(s:any){
 return {id:s.id,supplierId:s.supplierId,settlementKey:s.settlementKey,
  periodStart:s.periodStart.toISOString(),periodEnd:s.periodEnd.toISOString(),
  status:s.status,grossPaise:s.grossPaise.toString(),
  commissionPaise:s.commissionPaise.toString(),
  refundPaise:s.refundPaise.toString(),adjustmentPaise:s.adjustmentPaise.toString(),
  payablePaise:s.payablePaise.toString(),createdAt:s.createdAt.toISOString(),
  approvedById:s.approvedById,paidAt:s.paidAt?.toISOString()??null,
  payoutState:!s.transfers.length?'NOT_DISBURSED':
   s.transfers.length!==1?'DUPLICATE_PAYOUT_MANUAL_REVIEW':
   s.transfers[0].status==='SUCCEEDED'&&s.status==='PAID'?
    'PROVIDER_PROCESSED_BANK_STATEMENT_NOT_API_VERIFIED':
   s.transfers[0].status==='PENDING'?'PAYOUT_INTENT_NOT_SENT':
   s.transfers[0].status==='PROCESSING'?'PROVIDER_PROCESSING':
   'PAYOUT_EXCEPTION_MANUAL_REVIEW',
  lines:s.lines.map((l:any)=>({supplierOrderId:l.supplierOrderId,
   grossPaise:l.grossPaise.toString(),commissionPaise:l.commissionPaise.toString(),
   refundPaise:l.refundPaise.toString(),adjustmentPaise:l.adjustmentPaise.toString(),
   netPaise:l.netPaise.toString()})),
  transfers:s.transfers.map((t:any)=>({id:t.id,status:t.status,
   amountPaise:t.amountPaise.toString(),createdAt:t.createdAt.toISOString()}))};
}
/** Caller must already hold a parent-order lock before checking payment and unresolved claims. */
async function eligibility(tx:Tx,supplierId:string,supplierOrderId:string){
 const s=await tx.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
  select:{id:true,supplierId:true,purchaseOrderId:true,createdAt:true,
   status:true,totalPaise:true,platformFeePaise:true,
   invoices:{where:{status:'ISSUED'},select:{id:true,totalPaise:true,kind:true}},
   items:{select:{id:true,quantity:true,shipmentLines:{select:{
    deliveredQty:true,shipment:{select:{status:true,deliveredAt:true,
     handoverMethod:true,otpVerifiedAt:true,exceptionApprovedAt:true}}}}}},
   returnRequests:{where:{status:{in:[...blockedReturns]}},select:{id:true}},
   purchaseOrder:{select:{currency:true,totalPaise:true,
    payments:{select:{provider:true,status:true,capturedPaise:true,amountPaise:true,
     verifiedAt:true,providerPayRef:true}},
    refunds:{where:{status:{in:[...blockedRefunds]}},select:{id:true}}
   }}
  }});
 if(!s)throw new ApiError(404,'NOT_FOUND','Supplier order unavailable.');
 if(s.status!=='DELIVERED')
  throw new ApiError(409,'SETTLEMENT_DELIVERY_REQUIRED','Supplier order requires completed delivery.');
 if(s.totalPaise<=0n||s.platformFeePaise<0n||s.platformFeePaise>=s.totalPaise)
  throw new ApiError(409,'SETTLEMENT_AMOUNT_INVALID','Supplier financial snapshot cannot be settled.');
 const p=verifiedCapturedPayment(s.purchaseOrder.payments,s.purchaseOrder.totalPaise);
 if(s.purchaseOrder.currency!=='INR'||!p)
  throw new ApiError(409,'SETTLEMENT_CAPTURE_REQUIRED','One exact verified online capture is required; failed attempts do not count.');
 if(s.purchaseOrder.refunds.length||s.returnRequests.length)
  throw new ApiError(409,'SETTLEMENT_DISPUTED','An open return or refund places the entire supplier order on hold.');
 // Only legally issued, exact-value invoices are eligible for a settlement proposal.
 if(s.invoices.length!==1||s.invoices[0].totalPaise!==s.totalPaise)
  throw new ApiError(409,'SETTLEMENT_INVOICE_REQUIRED','An exact issued invoice is required.');
 if(!s.items.length||s.items.some(i=>!i.shipmentLines.length||!
  i.shipmentLines.filter(l=>['DELIVERED','PARTIALLY_DELIVERED'].includes(l.shipment.status)&&l.shipment.deliveredAt&&
    (l.shipment.handoverMethod==='OTP'&&l.shipment.otpVerifiedAt||
     l.shipment.handoverMethod==='APPROVED_EXCEPTION'&&l.shipment.exceptionApprovedAt))
  .reduce((n,l)=>n.plus(l.deliveredQty),new Prisma.Decimal(0)).eq(i.quantity)))
  throw new ApiError(409,'SETTLEMENT_HANDOVER_REQUIRED','Full verified shipment handover is required.');
 const duplicate=await tx.settlementLine.findFirst({where:{
  supplierOrderId:s.id,settlement:{status:{not:'CANCELLED'}}
 },select:{id:true}});
 if(duplicate)throw new ApiError(409,'SETTLEMENT_ORDER_ALREADY_ALLOCATED',
  'This supplier order already belongs to an uncancelled settlement.');
 return s;
}
function readDateWindow(raw:Record<string,unknown>){
 const start=date(raw.periodStart),end=date(raw.periodEnd);
 if(start>=end||end.getTime()>Date.now()+86400000||end.getTime()-start.getTime()>366*86400000)
  throw new ApiError(400,'INVALID_SETTLEMENT_PERIOD','Period must be ordered, not future, and at most 366 days.');
 return {start,end};
}
/** Proposals stay ON_HOLD: a Razorpay capture does not establish bank-settled funds. */
export async function createSettlementDraft(db:PrismaClient,userId:string,key:string,raw:unknown){
 const v=body(raw,['supplierId','settlementKey','periodStart','periodEnd','supplierOrderIds']);
 const supplierId=uuid(v.supplierId);
 const settlementKey=text(v.settlementKey,8,100,'settlement_key');
 const {start,end}=readDateWindow(v);
 if(!Array.isArray(v.supplierOrderIds)||v.supplierOrderIds.length<1||
  v.supplierOrderIds.length>50||v.supplierOrderIds.some(x=>!isUuid(x))||
  new Set(v.supplierOrderIds).size!==v.supplierOrderIds.length)
  throw new ApiError(400,'INVALID_SETTLEMENT_LINES','Provide 1-50 unique supplier order IDs.');
 const ids=(v.supplierOrderIds as string[]).slice().sort();
 const r=await executeIdempotently(db,{actorId:userId,scope:'finance:settlement:'+supplierId,
  requestKey:key,requestPayload:raw,expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
   const supplier=await tx.supplier.findFirst({where:{
    id:supplierId,approval:'APPROVED',suspendedAt:null},select:{id:true}});
   if(!supplier)throw new ApiError(404,'NOT_FOUND','Approved supplier unavailable.');
   const parents=await tx.supplierOrder.findMany({where:{id:{in:ids},supplierId},
    select:{id:true,purchaseOrderId:true}});
   if(parents.length!==ids.length)throw new ApiError(404,'NOT_FOUND','Supplier order unavailable.');
   // Lock parents in deterministic order: idempotent and SERIALIZABLE even across two drafts.
   for(const parentId of [...new Set(parents.map(x=>x.purchaseOrderId))].sort())
    await lockParent(tx,parentId);
   const candidates=[];
   for(const orderId of ids){
    const item=await eligibility(tx,supplierId,orderId);
    if(item.createdAt<start||item.createdAt>end)
     throw new ApiError(409,'SETTLEMENT_PERIOD_MISMATCH','Selected supplier order is outside the stated period.');
    candidates.push(item);
   }
   const gross=candidates.reduce((n,s)=>n+s.totalPaise,0n);
   const fee=candidates.reduce((n,s)=>n+s.platformFeePaise,0n);
   const net=gross-fee;
   if(gross<=0n||net<=0n)throw new ApiError(409,'SETTLEMENT_AMOUNT_INVALID','Invalid proposed settlement.');
   const settlement=await tx.settlement.create({data:{
    supplierId,settlementKey,periodStart:start,periodEnd:end,status:'ON_HOLD',
    grossPaise:gross,commissionPaise:fee,refundPaise:0n,adjustmentPaise:0n,
    payablePaise:net,
    lines:{create:candidates.map(s=>({supplierOrderId:s.id,
     grossPaise:s.totalPaise,commissionPaise:s.platformFeePaise,
     refundPaise:0n,adjustmentPaise:0n,netPaise:s.totalPaise-s.platformFeePaise}))}
   },select:{id:true}});
   await audit(tx,'Settlement',settlement.id,userId,'SETTLEMENT_DRAFT_ON_HOLD',
    {supplierId,orderCount:ids.length,bankReconciliation:'NOT_VERIFIED'});
   return {result:settlement.id,resultRef:settlement.id,responseCode:201};
  }});
 const row=await db.settlement.findFirst({where:{id:r.resultRef,supplierId},select:settlementSelect});
 if(!row)throw new ApiError(404,'NOT_FOUND','Settlement unavailable.');
 return {settlement:settlementDTO(row),replayed:r.kind==='replayed'};
}
export async function supplierStatement(db:PrismaClient,userId:string,supplierId:string){
 uuid(supplierId);
 await requireSupplierPermission(db,userId,supplierId,'FINANCE_READ');
 const [settlements,receivables]=await Promise.all([
  db.settlement.findMany({where:{supplierId},select:settlementSelect,
   orderBy:{createdAt:'desc'},take:100}),
  db.supplierCommissionReceivable.findMany({where:{supplierId},
   select:{id:true,supplierOrderId:true,commissionPaise:true,offsetPaise:true,status:true,
    createdAt:true},orderBy:{createdAt:'desc'},take:100})
 ]);
 return {settlements:settlements.map(settlementDTO),
  codCommissionReceivables:receivables.map(r=>({id:r.id,
   supplierOrderId:r.supplierOrderId,commissionPaise:r.commissionPaise.toString(),
   offsetPaise:r.offsetPaise.toString(),status:r.status,
   createdAt:r.createdAt.toISOString()})),
  bankingReconciled:false,payoutExecutionEnabled:false};
}
export async function adminSupplierFinance(db:PrismaClient,userId:string,supplierId:string){
 uuid(supplierId);
 await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 const [orders,settlements]=await Promise.all([
  db.supplierOrder.findMany({where:{supplierId,status:'DELIVERED'},
   select:{id:true,totalPaise:true,platformFeePaise:true,codVerifiedPaise:true,
    purchaseOrder:{select:{totalPaise:true,payments:{
     select:{provider:true,status:true,amountPaise:true,capturedPaise:true,
      verifiedAt:true,providerPayRef:true}}}},
    returnRequests:{where:{status:{in:[...blockedReturns]}},select:{id:true}},
    settlementLines:{select:{settlement:{select:{status:true}}}}
   },orderBy:{createdAt:'desc'},take:100}),
  db.settlement.findMany({where:{supplierId},select:settlementSelect,
   orderBy:{createdAt:'desc'},take:100})
 ]);
 return {orders:orders.map(s=>({
  supplierOrderId:s.id,totalPaise:s.totalPaise.toString(),
  platformFeePaise:s.platformFeePaise.toString(),
  codVerifiedPaise:s.codVerifiedPaise.toString(),
  fundingType:s.purchaseOrder.payments.some(p=>p.provider==='MANUAL')?'COD_SUPPLIER_HELD':
   !!verifiedCapturedPayment(s.purchaseOrder.payments,s.purchaseOrder.totalPaise)
    ?'RAZORPAY_CAPTURE_VERIFIED':'ONLINE_UNVERIFIED',
  disputed:Boolean(s.returnRequests.length),
  allocatedToActiveSettlement:s.settlementLines.some(l=>l.settlement.status!=='CANCELLED')
 })),
 settlements:settlements.map(settlementDTO),bankingReconciled:false};
}
async function activeSupplierMember(tx:Tx,userId:string,supplierId:string){
 const member=await tx.supplierMember.findUnique({where:{
  supplierId_userId:{supplierId,userId}},select:{active:true,revokedAt:true}});
 return Boolean(member?.active&&!member.revokedAt);
}
async function journal(tx:Tx,referenceKey:string,eventType:string,lines:Array<{
 code:string;name:string;debit?:bigint;credit?:bigint;memo:string}>){
 if(lines.length<2)throw new ApiError(409,'LEDGER_UNBALANCED','At least two journal lines required.');
 const debit=lines.reduce((n,x)=>n+(x.debit??0n),0n);
 const credit=lines.reduce((n,x)=>n+(x.credit??0n),0n);
 if(debit<=0n||debit!==credit)throw new ApiError(409,'LEDGER_UNBALANCED','Journal debits must equal credits.');
 const accounts:string[]=[];
 for(const line of lines){
  const account=await tx.ledgerAccount.upsert({where:{code:line.code},
   create:{code:line.code,name:line.name,currency:'INR',active:true},update:{},
   select:{id:true,active:true,currency:true}});
  if(!account.active||account.currency!=='INR')
   throw new ApiError(409,'LEDGER_ACCOUNT_INACTIVE','Finance account is closed.');
  accounts.push(account.id);
 }
 const created=await tx.ledgerJournal.create({data:{referenceKey,eventType,
  lines:{create:lines.map((line,i)=>({lineNumber:i+1,accountId:accounts[i],
   debitPaise:line.debit??0n,creditPaise:line.credit??0n,memo:line.memo}))}
 },select:{id:true}});
 await tx.ledgerJournal.update({where:{id:created.id},data:{postedAt:new Date()}});
 return created.id;
}
/** Independent finance attestation + posted accrual memo, WITHOUT initiating payout. */
export async function approveSettlement(db:PrismaClient,userId:string,settlementId:string,raw:unknown){
 uuid(settlementId);
 const input=body(raw,['bankStatementReference']);
 const bankStatementReference=text(input.bankStatementReference,12,120,'bank_statement_reference');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  const current=await tx.settlement.findUnique({where:{id:settlementId},select:{
   id:true,supplierId:true,status:true,periodStart:true,periodEnd:true,createdAt:true,
   grossPaise:true,commissionPaise:true,payablePaise:true,
   transfers:{select:{id:true}},
   lines:{select:{supplierOrderId:true,grossPaise:true,commissionPaise:true,netPaise:true}}
  }});
  if(!current)throw new ApiError(404,'NOT_FOUND','Settlement unavailable.');
  const ids=current.lines.map(x=>x.supplierOrderId);
  const parents=await tx.supplierOrder.findMany({where:{id:{in:ids}},
   select:{purchaseOrderId:true}});
  for(const parentId of [...new Set(parents.map(x=>x.purchaseOrderId))].sort())
   await lockParent(tx,parentId);
  const maker=await tx.auditEvent.findFirst({where:{
   entityType:'Settlement',entityId:settlementId,action:'SETTLEMENT_DRAFT_ON_HOLD'
  },select:{actorUserId:true}});
  if(!maker||maker.actorUserId===userId||await activeSupplierMember(tx,userId,current.supplierId))
   throw new ApiError(403,'INDEPENDENT_SETTLEMENT_APPROVAL_REQUIRED',
    'The draft maker or supplier personnel cannot independently attest the settlement.');
  if(current.status!=='ON_HOLD'||current.transfers.length)
   throw new ApiError(409,'SETTLEMENT_ALREADY_REVIEWED','Only held drafts without transfers can be independently approved.');
  const seller=await tx.supplier.findFirst({where:{id:current.supplierId,
   approval:'APPROVED',suspendedAt:null},select:{id:true}});
  if(!seller)throw new ApiError(409,'SETTLEMENT_SUPPLIER_NOT_ELIGIBLE','Supplier is not eligible for attestation.');
  const attestationExists=await tx.auditEvent.findFirst({where:{
   entityType:'Settlement',action:'SETTLEMENT_RECONCILIATION_ATTESTED',
   afterState:{path:['bankStatementReference'],equals:bankStatementReference}
  },select:{id:true}});
  if(attestationExists)throw new ApiError(409,'BANK_REFERENCE_ALREADY_USED',
   'Bank statement reference was previously attested to a settlement.');
  let gross=0n,fee=0n,net=0n;
  for(const line of current.lines){
   // Eligibility checks exclude this draft's allocation only; check all OTHER settlements.
   const order=await tx.supplierOrder.findFirst({where:{
    id:line.supplierOrderId,supplierId:current.supplierId
   },select:{id:true,createdAt:true,status:true,totalPaise:true,platformFeePaise:true,
    invoices:{where:{status:'ISSUED'},select:{totalPaise:true}},
    items:{select:{quantity:true,shipmentLines:{select:{deliveredQty:true,
     shipment:{select:{status:true,deliveredAt:true,handoverMethod:true,
      otpVerifiedAt:true,exceptionApprovedAt:true}}}}}},
    purchaseOrder:{select:{currency:true,totalPaise:true,
     payments:{select:{provider:true,status:true,amountPaise:true,capturedPaise:true,
      verifiedAt:true,providerPayRef:true}},
     refunds:{where:{status:{in:[...blockedRefunds]}},select:{id:true}}}},
    returnRequests:{where:{status:{in:[...blockedReturns]}},select:{id:true}},
    settlementLines:{where:{settlementId:{not:settlementId},
     settlement:{status:{not:'CANCELLED'}}},select:{id:true}}
   }});
   if(!order||order.status!=='DELIVERED'||order.returnRequests.length||
    order.purchaseOrder.refunds.length||order.settlementLines.length||
    !order.items.length||order.items.some(i=>!i.shipmentLines.length||!
     i.shipmentLines.filter(l=>['DELIVERED','PARTIALLY_DELIVERED'].includes(l.shipment.status)&&l.shipment.deliveredAt&&
      (l.shipment.handoverMethod==='OTP'&&l.shipment.otpVerifiedAt||
       l.shipment.handoverMethod==='APPROVED_EXCEPTION'&&l.shipment.exceptionApprovedAt))
     .reduce((n,l)=>n.plus(l.deliveredQty),new Prisma.Decimal(0)).eq(i.quantity))||
    order.invoices.length!==1||order.invoices[0].totalPaise!==order.totalPaise||
    !verifiedCapturedPayment(order.purchaseOrder.payments,order.purchaseOrder.totalPaise))
    throw new ApiError(409,'SETTLEMENT_REVALIDATION_FAILED','Financial or fulfillment evidence changed after drafting.');
   if(    order.purchaseOrder.currency!=='INR'||order.createdAt<current.periodStart||
    order.createdAt>current.periodEnd||order.totalPaise!==line.grossPaise||
    order.platformFeePaise!==line.commissionPaise||
    order.totalPaise-order.platformFeePaise!==line.netPaise)
    throw new ApiError(409,'SETTLEMENT_REVALIDATION_FAILED','Financial snapshot does not reconcile.');
   gross+=line.grossPaise;fee+=line.commissionPaise;net+=line.netPaise;
  }
  if(!ids.length||gross!==current.grossPaise||fee!==current.commissionPaise||
   net!==current.payablePaise||net<=0n)
   throw new ApiError(409,'SETTLEMENT_TOTAL_MISMATCH','Settlement does not balance against order lines.');
  const suffix=current.supplierId.replaceAll('-','');
  const entries=[
   {code:'ONLINE_CAPTURE_CLEAR_'+suffix,name:'Online capture clearing memorandum',
    debit:gross,memo:'Settlement attested against external bank statement reference'},
   {code:'SUPPLIER_PAYABLE_'+suffix,name:'Supplier payable memorandum',
    credit:net,memo:'Approved supplier payable; not transferred'}
  ];
  if(fee>0n)entries.push({code:'PLATFORM_FEE_CLEAR_'+suffix,
   name:'Platform commission memorandum',credit:fee,
   memo:'Contractual platform fee separated from supplier payable'});
  await journal(tx,'settlement:accrual:'+settlementId,'SETTLEMENT_ACCRUAL_MEMORANDUM',entries);
  await tx.settlement.update({where:{id:settlementId},data:{
   status:'APPROVED',approvedById:userId
  }});
  // This is a human ATTESTATION, not bank integration verification.
  await audit(tx,'Settlement',settlementId,userId,'SETTLEMENT_RECONCILIATION_ATTESTED',
   {supplierId:current.supplierId,bankStatementReference,bankEvidenceType:'HUMAN_ATTESTED',
    gatewayBankVerified:false,payoutExecuted:false});
  return {id:settlementId,status:'APPROVED',payoutState:'NOT_DISBURSED' as const,
   bankEvidenceType:'HUMAN_ATTESTED' as const};
 });
}
/** Invalidate only unreleased, held proposals; no change to captured payment. */
export async function cancelHeldSettlement(db:PrismaClient,userId:string,settlementId:string,raw:unknown){
 uuid(settlementId);
 const input=body(raw,['reason']);
 const reason=text(input.reason,12,200,'reason');
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  const current=await tx.settlement.findUnique({where:{id:settlementId},
   select:{status:true,supplierId:true,transfers:{select:{id:true}}}});
  if(!current)throw new ApiError(404,'NOT_FOUND','Settlement unavailable.');
  if(current.status==='CANCELLED')return {id:settlementId,status:'CANCELLED',replayed:true};
  if(current.status!=='ON_HOLD'||current.transfers.length)
   throw new ApiError(409,'SETTLEMENT_CANNOT_CANCEL','Approved or processing settlements require formal reversal.');
  await tx.settlement.update({where:{id:settlementId},data:{status:'CANCELLED'}});
  await audit(tx,'Settlement',settlementId,userId,'SETTLEMENT_DRAFT_CANCELLED',{reason});
  return {id:settlementId,status:'CANCELLED',replayed:false};
 });
}
export async function recognizeCodCommission(db:PrismaClient,userId:string,supplierOrderId:string){
 uuid(supplierOrderId);
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,userId,'FINANCE_MANAGE');
  const child=await tx.supplierOrder.findFirst({where:{id:supplierOrderId},
   select:{id:true,purchaseOrderId:true,supplierId:true}});
  if(!child)throw new ApiError(404,'NOT_FOUND','Supplier order unavailable.');
  await lockParent(tx,child.purchaseOrderId);
  const order=await tx.supplierOrder.findUniqueOrThrow({where:{id:supplierOrderId},
   select:{id:true,supplierId:true,status:true,totalPaise:true,
    platformFeePaise:true,codVerifiedPaise:true,
    purchaseOrder:{select:{payments:{select:{provider:true,paymentMethod:true,status:true}}}},
    codCollections:{where:{status:'VERIFIED'},
     select:{collectedPaise:true,journalReference:true}}
   }});
  if(await activeSupplierMember(tx,userId,order.supplierId))
   throw new ApiError(403,'INDEPENDENT_COMMISSION_REVIEW_REQUIRED',
    'Supplier personnel cannot independently recognize their own commission.');
  const found=await tx.supplierCommissionReceivable.findUnique({where:{supplierOrderId},
   select:{id:true,supplierId:true,commissionPaise:true,offsetPaise:true,status:true,
    journalReference:true}});
  if(found){
   if(found.supplierId!==order.supplierId||found.commissionPaise!==order.platformFeePaise)
    throw new ApiError(409,'COMMISSION_SNAPSHOT_MISMATCH','Commission receipt does not match order.');
   const posted=found.journalReference?await tx.ledgerJournal.findUnique({
    where:{referenceKey:found.journalReference},select:{postedAt:true}}):null;
   if(!posted?.postedAt)throw new ApiError(409,'COMMISSION_JOURNAL_MISSING','Commission financial evidence is not posted.');
   return {id:found.id,supplierOrderId,amountPaise:found.commissionPaise.toString(),
    status:found.status,replayed:true};
  }
  if(order.status!=='DELIVERED'||order.platformFeePaise<=0n||
   order.platformFeePaise>=order.totalPaise||
   order.codVerifiedPaise!==order.totalPaise||
   order.purchaseOrder.payments.length!==1||
   order.purchaseOrder.payments[0].provider!=='MANUAL'||
   order.purchaseOrder.payments[0].paymentMethod!=='COD'||
   order.purchaseOrder.payments[0].status!=='PENDING'||
   order.codCollections.length!==1||
   order.codCollections[0].collectedPaise!==order.totalPaise||
   !order.codCollections[0].journalReference)
   throw new ApiError(409,'COMMISSION_COD_NOT_VERIFIED',
    'Independent full COD confirmation and positive contractual fee are required.');
  const posted=await tx.ledgerJournal.findUnique({where:{
   referenceKey:order.codCollections[0].journalReference},select:{postedAt:true}});
  if(!posted?.postedAt)throw new ApiError(409,'COMMISSION_COD_JOURNAL_MISSING','COD journal was not posted.');
  const suffix=order.supplierId.replaceAll('-','');
  const ref='cod:commission:'+supplierOrderId;
  await journal(tx,ref,'COD_COMMISSION_MEMORANDUM',[
   {code:'COD_COMMISSION_DUE_'+suffix,name:'Supplier COD commission due memorandum',
    debit:order.platformFeePaise,memo:'Independent COD commission receivable from supplier'},
   {code:'PLATFORM_FEE_CLEAR_'+suffix,name:'Platform commission memorandum',
    credit:order.platformFeePaise,memo:'Supplier-held COD fee not yet received by Buildto'}
  ]);
  const receivable=await tx.supplierCommissionReceivable.create({data:{
   supplierId:order.supplierId,supplierOrderId,commissionPaise:order.platformFeePaise,
   offsetPaise:0n,status:'OPEN',journalReference:ref
  },select:{id:true}});
  await audit(tx,'SupplierCommissionReceivable',receivable.id,userId,
   'COD_COMMISSION_RECOGNIZED',{supplierId:order.supplierId,
    supplierOrderId,bankCashReceived:false,offsetPaise:'0'});
  return {id:receivable.id,supplierOrderId,
   amountPaise:order.platformFeePaise.toString(),status:'OPEN',replayed:false};
 });
}
export async function journalDetail(db:PrismaClient,userId:string,journalId:string){
 uuid(journalId);await requireAdminPermission(db,userId,'FINANCE_MANAGE');
 const r=await db.ledgerJournal.findUnique({where:{id:journalId},
  select:{id:true,referenceKey:true,eventType:true,postedAt:true,
   lines:{select:{lineNumber:true,account:{select:{code:true,currency:true}},
    debitPaise:true,creditPaise:true,memo:true},orderBy:{lineNumber:'asc'}}}});
 if(!r)throw new ApiError(404,'NOT_FOUND','Journal unavailable.');
 const debit=r.lines.reduce((n,l)=>n+l.debitPaise,0n);
 const credit=r.lines.reduce((n,l)=>n+l.creditPaise,0n);
 return {id:r.id,referenceKey:r.referenceKey,eventType:r.eventType,
  postedAt:r.postedAt?.toISOString()??null,balanced:debit===credit&&debit>0n,
  debitPaise:debit.toString(),creditPaise:credit.toString(),
  lines:r.lines.map(l=>({lineNumber:l.lineNumber,accountCode:l.account.code,
   currency:l.account.currency,debitPaise:l.debitPaise.toString(),
   creditPaise:l.creditPaise.toString(),memo:l.memo}))};
}
