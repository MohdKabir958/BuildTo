'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {Prisma,PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),sub=()=> 'user_'+id().replaceAll('-');
const key=()=> 'fin_'+id().replaceAll('-');
const users={},tokens={},st={};
const api=request(createV21App({db,allowedOrigins:[],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
  return {subject:tokens[token],sessionId:'sess_finance_test_1'};
 }}}));
function send(method,path,actor,data,k){
 let req=api[method](path);
 if(actor)req=req.set('Authorization','Bearer '+actor);
 if(k)req=req.set('Idempotency-Key',k);
 return data===undefined?req:req.send(data);
}
const admin=(x='')=>'/api/v2/admin/finance'+x;
const supplier=()=>'/api/v2/suppliers/'+st.supplier.id;
const start=()=>new Date(Date.now()-86400000).toISOString();
const end=()=>new Date(Date.now()+1200000).toISOString();
const makeDraft=(orderId,settlementKey,periodStart=start(),periodEnd=end())=>({
 supplierId:st.supplier.id,settlementKey,periodStart,periodEnd,
 supplierOrderIds:[orderId]
});
async function makeOrder(method='RAZORPAY',amount=10000n,fee=800n){
 const parent=await db.purchaseOrder.create({data:{
  customerId:users.customer.id,clientRequestId:key(),
  publicNumber:'BT-'+id().replaceAll('-').slice(0,25),
  subtotalPaise:amount,totalPaise:amount,currency:'INR',
  addressSnapshot:{recipientName:'Site buyer',city:'Hyderabad',line1:'Site road'},
  status:'CONFIRMED'
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:st.supplier.id,
  status:'DELIVERED',subtotalPaise:amount,totalPaise:amount,
  platformFeePaise:fee
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:'FIN-MAT-'+id().slice(0,10),
  nameSnapshot:'Building materials',unitCode:'BAG',
  packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(1),
  unitPrice:new Prisma.Decimal(Number(amount)/100),taxRateBps:0,
  taxablePaise:amount,taxPaise:0n,lineTotalPaise:amount
 }});
 const shipment=await db.shipment.create({data:{
  shipmentNumber:'FINSH-'+id().replaceAll('-').slice(0,24),
  supplierOrderId:child.id,supplierId:st.supplier.id,status:'DELIVERED',
  deliveredAt:new Date(),handoverMethod:'APPROVED_EXCEPTION',
  exceptionApprovedById:users.approver.id,exceptionApprovedAt:new Date(),
  exceptionReason:'Independent approved verification of full physical delivery'
 }});
 await db.shipmentItem.create({data:{
  shipmentId:shipment.id,supplierOrderItemId:item.id,
  quantity:new Prisma.Decimal(1),deliveredQty:new Prisma.Decimal(1)
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:parent.id,provider:method==='MANUAL'?'MANUAL':'RAZORPAY',paymentMethod:method==='MANUAL'?'COD':'UPI',
  status:method==='MANUAL'?'PENDING':method==='AUTHORIZED'?'AUTHORIZED':'CAPTURED',
  idempotencyKey:key(),amountPaise:amount,capturedPaise:method==='RAZORPAY'?amount:0n,
  ...(method==='RAZORPAY'?{providerOrderRef:'order_'+id().replaceAll('-').slice(0,23),
   providerPayRef:'pay_'+id().replaceAll('-').slice(0,23),verifiedAt:new Date()}:{})
 }});
 if(method!=='MANUAL'){
  await db.taxInvoice.create({data:{
   supplierOrderId:child.id,supplierId:st.supplier.id,
   invoiceNumber:'FT-'+id().replaceAll('-').slice(0,23),
   financialYear:'2026-27',status:'ISSUED',kind:'BILL_OF_SUPPLY',
   sellerSnapshot:{verified:true},buyerSnapshot:{customer:true},
   lineSnapshot:{items:[]},taxablePaise:amount,taxPaise:0n,totalPaise:amount
  }});
 }
 return {parent,child,item,shipment,amount,fee};
}
test('fixture: independent finance reviewers and seller-only finance membership',async()=>{
 for(const role of ['customer','outsider','maker','approver','conflicted','supplierFinance','fulfillment','viewer']){
  const u=await db.user.create({data:{clerkUserId:sub(),displayName:'Finance '+role}});
  users[role]=u;tokens[role]=u.clerkUserId;
 }
 st.supplier=await db.supplier.create({data:{
  slug:'finance-'+id(),displayName:'Online & COD Materials',
  legalName:'Finance Supplier P Ltd',approval:'APPROVED',verifiedAt:new Date()
 }});
 await db.adminMembership.createMany({data:[
  {userId:users.maker.id,role:'FINANCE',active:true},
  {userId:users.approver.id,role:'FINANCE',active:true},
  {userId:users.conflicted.id,role:'FINANCE',active:true}
 ]});
 await db.supplierMember.createMany({data:[
  {supplierId:st.supplier.id,userId:users.supplierFinance.id,role:'FINANCE',active:true},
  {supplierId:st.supplier.id,userId:users.fulfillment.id,role:'FULFILLMENT',active:true},
  {supplierId:st.supplier.id,userId:users.conflicted.id,role:'OWNER',active:true},
  {supplierId:st.supplier.id,userId:users.viewer.id,role:'VIEWER',active:true}
 ]});
 st.online=await makeOrder('RAZORPAY',10000n,800n);
 assert.equal((await send('get',supplier()+'/finance/statement','outsider')).status,404);
 assert.equal((await send('get',supplier()+'/finance/statement','viewer')).status,403);
 assert.equal((await send('get',supplier()+'/finance/statement','supplierFinance')).status,200);
 assert.equal((await send('get',admin('/suppliers/'+st.supplier.id),'supplierFinance')).status,403);
 assert.equal((await send('get',admin('/suppliers/'+st.supplier.id),'maker')).status,200);
});
test('unverified or COD supplier cash is NEVER counted as platform-held settlement funds',async()=>{
 st.cod=await makeOrder('MANUAL',20000n,1700n);
 const b=makeDraft(st.cod.child.id,key());
 assert.equal((await send('post',admin('/settlements/drafts'),'maker',b,key())).status,409);
 const unpaid=await makeOrder('AUTHORIZED',12000n,700n);
 const r=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(unpaid.child.id,key()),key());
 assert.equal(r.status,409,JSON.stringify(r.body));
 assert.equal(r.body.error.code,'SETTLEMENT_CAPTURE_REQUIRED');
 assert.equal(await db.settlement.count({where:{supplierId:st.supplier.id}}),0);
});
test('draft must have verified physical handover and exactly one issued invoice',async()=>{
 st.missingInvoice=await makeOrder('RAZORPAY',13000n,500n);
 await db.taxInvoice.deleteMany({where:{supplierOrderId:st.missingInvoice.child.id}});
 const missing=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(st.missingInvoice.child.id,key()),key());
 assert.equal(missing.status,409);
 assert.equal(missing.body.error.code,'SETTLEMENT_INVOICE_REQUIRED');
 await db.taxInvoice.create({data:{
  supplierOrderId:st.missingInvoice.child.id,supplierId:st.supplier.id,
  invoiceNumber:'FIN-'+id().slice(0,24),financialYear:'2026-27',
  taxablePaise:13000n,totalPaise:13000n,taxPaise:0n,
  kind:'BILL_OF_SUPPLY',status:'ISSUED',sellerSnapshot:{},buyerSnapshot:{},lineSnapshot:{}
 }});
 await db.shipment.update({where:{id:st.missingInvoice.shipment.id},
  data:{status:'DISPATCHED',deliveredAt:null,handoverMethod:null,
   exceptionApprovedAt:null,exceptionApprovedById:null,exceptionReason:null}});
 const insufficient=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(st.missingInvoice.child.id,key()),key());
 assert.equal(insufficient.status,409,JSON.stringify(insufficient.body));
 assert.equal(insufficient.body.error.code,'SETTLEMENT_HANDOVER_REQUIRED');
});
test('held draft contains exact supplier payable and never marks money disbursed',async()=>{
 const b=makeDraft(st.online.child.id,key());
 assert.equal((await send('post',admin('/settlements/drafts'),'customer',b,key())).status,403);
 assert.equal((await send('post',admin('/settlements/drafts'),'maker',b)).status,428);
 assert.equal((await send('post',admin('/settlements/drafts'),'maker',
  {...b,supplierOrderIds:[st.cod.child.id]},key())).status,409);
 const k=key(),created=await send('post',admin('/settlements/drafts'),'maker',b,k);
 assert.equal(created.status,201,JSON.stringify(created.body));
 st.settlementId=created.body.data.id;
 assert.equal(created.body.data.status,'ON_HOLD');
 assert.equal(created.body.data.grossPaise,'10000');
 assert.equal(created.body.data.commissionPaise,'800');
 assert.equal(created.body.data.payablePaise,'9200');
 assert.equal(created.body.data.payoutState,'NOT_DISBURSED');
 assert.equal(created.body.data.lines.length,1);
 const r=await send('post',admin('/settlements/drafts'),'maker',b,k);
 assert.equal(r.status,200,JSON.stringify(r.body));
 assert.equal(r.body.replayed,true);
 assert.equal(r.body.data.id,st.settlementId);
 assert.equal((await send('post',admin('/settlements/drafts'),'maker',
  {...b,settlementKey:key()},k)).status,409);
 assert.equal((await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(st.online.child.id,key()),key())).status,409);
 assert.equal(await db.payoutTransfer.count({where:{settlementId:st.settlementId}}),0);
});
test('independent attestation posts exactly one balanced accrual memo; not a bank payout',async()=>{
 const url=admin('/settlements/'+st.settlementId+'/approve');
 const input={bankStatementReference:'BANK-STATEMENT-'+id().replaceAll('-').slice(0,20)};
 assert.equal((await send('post',url,'maker',input)).status,403);
 assert.equal((await send('post',url,'conflicted',input)).status,403);
 assert.equal((await send('post',url,'supplierFinance',input)).status,403);
 assert.equal((await send('post',url,'approver',{bankStatementReference:'short'})).status,400);
 const approved=await send('post',url,'approver',input);
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 assert.equal(approved.body.data.status,'APPROVED');
 assert.equal(approved.body.data.payoutState,'NOT_DISBURSED');
 assert.equal(approved.body.data.bankEvidenceType,'HUMAN_ATTESTED');
 const after=await db.settlement.findUniqueOrThrow({where:{id:st.settlementId}});
 assert.equal(after.approvedById,users.approver.id);
 assert.equal(after.paidAt,null);
 assert.equal(await db.payoutTransfer.count({where:{settlementId:st.settlementId}}),0);
 const posted=await db.ledgerJournal.findUniqueOrThrow({where:{
  referenceKey:'settlement:accrual:'+st.settlementId},include:{lines:true}});
 assert(posted.postedAt);
 assert.equal(posted.lines.length,3);
 assert.equal(posted.lines.reduce((x,l)=>x+l.debitPaise,0n),10000n);
 assert.equal(posted.lines.reduce((x,l)=>x+l.creditPaise,0n),10000n);
 assert.equal((await send('get',admin('/journals/'+posted.id),'outsider')).status,403);
 const detail=await send('get',admin('/journals/'+posted.id),'maker');
 assert.equal(detail.status,200,JSON.stringify(detail.body));
 assert.equal(detail.body.data.balanced,true);
 assert.equal(detail.body.data.creditPaise,'10000');
 assert.equal((await send('post',url,'approver',input)).status,409);
 assert.equal((await send('post',admin('/settlements/'+st.settlementId+'/cancel'),
  'maker',{reason:'Attempt to cancel after finance approval'})).status,409);
});
test('held proposal may be cancelled, freeing allocation without deleting audit/history',async()=>{
 const fresh=await makeOrder('RAZORPAY',11000n,900n);
 const b=makeDraft(fresh.child.id,key());
 const made=await send('post',admin('/settlements/drafts'),'maker',b,key());
 assert.equal(made.status,201,JSON.stringify(made.body));
 const endpoint=admin('/settlements/'+made.body.data.id+'/cancel');
 assert.equal((await send('post',endpoint,'supplierFinance',
  {reason:'Supplier cannot cancel admin proposal'})).status,403);
 const stopped=await send('post',endpoint,'maker',
  {reason:'Cancelled after manual finance review of statements'});
 assert.equal(stopped.status,200,JSON.stringify(stopped.body));
 assert.equal(stopped.body.data.status,'CANCELLED');
 const retry=await send('post',endpoint,'maker',
  {reason:'Cancelled after manual finance review of statements'});
 assert.equal(retry.status,200);assert.equal(retry.body.data.replayed,true);
 const newDraft=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(fresh.child.id,key()),key());
 assert.equal(newDraft.status,201,JSON.stringify(newDraft.body));
});
test('unresolved customer return and reserved provider refund each prevent online settlement',async()=>{
 const ret=await makeOrder('RAZORPAY',17000n,1000n);
 await db.returnRequest.create({data:{
  supplierOrderId:ret.child.id,customerId:users.customer.id,
  reason:'Return request pending independent assessment',status:'REQUESTED',
  items:{create:{supplierOrderItemId:ret.item.id,quantity:new Prisma.Decimal(1)}}
 }});
 const first=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(ret.child.id,key()),key());
 assert.equal(first.status,409,JSON.stringify(first.body));
 assert.equal(first.body.error.code,'SETTLEMENT_DISPUTED');
 const refunded=await makeOrder('RAZORPAY',15000n,800n);
 const payment=await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:refunded.parent.id}});
 const received=await db.returnRequest.create({data:{supplierOrderId:refunded.child.id,customerId:users.customer.id,reason:'Returned goods remain held during finance review',status:'RECEIVED',items:{create:{supplierOrderItemId:refunded.item.id,quantity:new Prisma.Decimal(1)}}}});
 await db.refundRequest.create({data:{
  returnRequestId:received.id,
  purchaseOrderId:refunded.parent.id,paymentAttemptId:payment.id,
  requestKey:key(),amountPaise:2000n,status:'REQUESTED',
  reason:'Outstanding request requiring manual review'
 }});
 const second=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(refunded.child.id,key()),key());
 assert.equal(second.status,409,JSON.stringify(second.body));
 assert.equal(second.body.error.code,'SETTLEMENT_DISPUTED');
});
test('COD commission requires finance-verified full receipt and posted cash memo',async()=>{
 const endpoint=admin('/cod-commissions/'+st.cod.child.id+'/recognize');
 assert.equal((await send('post',endpoint,'maker',{})).status,409);
 assert.equal((await send('post',endpoint,'supplierFinance',{})).status,403);
 const receipt=await db.codCollection.create({data:{
  supplierId:st.supplier.id,supplierOrderId:st.cod.child.id,
  shipmentId:st.cod.shipment.id,
  receiptNumber:'FINCASH-'+id().replaceAll('-').slice(0,25),
  idempotencyKey:key(),collectedPaise:st.cod.amount,
  collectedByUserId:users.fulfillment.id,status:'RECORDED'
 }});
 const review=await send('post',admin('/cod/'+receipt.id+'/review'),'approver',{
  decision:'VERIFY',externalReference:'COD-BANK-MEMO-'+id().slice(0,20)
 });
 assert.equal(review.status,200,JSON.stringify(review.body));
 assert.equal(review.body.data.status,'VERIFIED');
 assert.equal((await send('post',endpoint,'conflicted',{})).status,403);
 const recognized=await send('post',endpoint,'maker',{});
 assert.equal(recognized.status,200,JSON.stringify(recognized.body));
 assert.equal(recognized.body.data.amountPaise,'1700');
 assert.equal(recognized.body.data.status,'OPEN');
 const repeated=await send('post',endpoint,'maker',{});
 assert.equal(repeated.status,200);assert.equal(repeated.body.data.replayed,true);
 const rec=await db.supplierCommissionReceivable.findUniqueOrThrow({
  where:{supplierOrderId:st.cod.child.id}});
 assert.equal(rec.offsetPaise,0n);
 assert.equal(rec.commissionPaise,1700n);
 const j=await db.ledgerJournal.findUniqueOrThrow({where:{referenceKey:rec.journalReference},
  include:{lines:true}});
 assert(j.postedAt);
 assert.equal(j.lines.reduce((n,l)=>n+l.debitPaise,0n),1700n);
 assert.equal(j.lines.reduce((n,l)=>n+l.creditPaise,0n),1700n);
 assert.equal((await send('get',supplier()+'/finance/statement','supplierFinance'))
  .body.data.codCommissionReceivables[0].amountPaise,undefined);
 const statement=await send('get',supplier()+'/finance/statement','supplierFinance');
 assert.equal(statement.status,200,JSON.stringify(statement.body));
 assert(statement.body.data.settlements.length>=2);
 assert.equal(statement.body.data.codCommissionReceivables[0].commissionPaise,'1700');
 assert.equal(statement.body.data.payoutExecutionEnabled,false);
 assert.equal((await db.payoutTransfer.count()),0);
});


test('settlement eligibility accepts captured money after a failed UPI try',async()=>{
 const order=await makeOrder('RAZORPAY',19000n,1100n);
 await db.paymentAttempt.create({data:{
  purchaseOrderId:order.parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:key(),status:'FAILED',amountPaise:19000n
 }});
 const created=await send('post',admin('/settlements/drafts'),'maker',
  makeDraft(order.child.id,key()),key());
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.supplierId,st.supplier.id);
 assert.equal(created.body.data.status,'ON_HOLD');
});
