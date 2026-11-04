'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {readConfig}=require('../dist/config.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const uid=()=>randomUUID(),k=()=> 'payout_'+uid().replaceAll('-');
const users={},tokens={},s={};
const provider={
 fundId:'fa_123456789012345',validationId:'fav_123456789012345',
 bankHolder:'Reliable Materials Private Limited',
 last4:'5678',ifsc:'HDFC0000123',registered:'Reliable Materials Private Limited',
 status:'pending',payoutId:'pout_123456789012345',
 amount:9200n,referenceId:'',utr:null,purpose:'payout',calls:[],
};
const evidence={
 fetchFundAccount:async id=>{
  provider.calls.push('GET fund:'+id);
  return {id,active:true,accountType:'bank_account',
   holder:provider.bankHolder,ifsc:provider.ifsc,last4:provider.last4};
 },
 fetchValidation:async id=>{
  provider.calls.push('GET validation:'+id);
  return {id,fundAccountId:provider.fundId,status:'completed',
   registeredName:provider.registered,accountStatus:'active'};
 },
 fetchPayout:async id=>{
  provider.calls.push('GET payout:'+id);
  return {id,amount:provider.amount,referenceId:provider.referenceId,
   fundAccountId:provider.fundId,currency:'INR',
   status:provider.status,purpose:provider.purpose,utr:provider.utr};
 }
};
const api=request(createV21App({db,allowedOrigins:[],proxyHops:0,log:()=>{},
 limiter:new InMemoryTestLimiter(),payoutEvidenceGateway:evidence,
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid test session');
  return {subject:tokens[token],sessionId:'session_payout_1'};
 }}}));
const send=(method,path,actor,data,idempotency)=>{
 let q=api[method](path);
 if(actor)q=q.set('Authorization','Bearer '+actor);
 if(idempotency)q=q.set('Idempotency-Key',idempotency);
 return data===undefined?q:q.send(data);
};
const admin=(x='')=>'/api/v2/admin/finance'+x;
const supplier=()=>'/api/v2/suppliers/'+s.supplier.id;
const decimals=n=>new Prisma.Decimal(n);

async function createDelivered(){
 const parent=await db.purchaseOrder.create({data:{
  customerId:users.customer.id,publicNumber:'BT-PAY-'+uid().replaceAll('-').slice(0,23),
  clientRequestId:k(),currency:'INR',status:'CONFIRMED',
  subtotalPaise:10000n,totalPaise:10000n,
  addressSnapshot:{recipientName:'Construction buyer',line1:'Street',city:'Hyderabad'}
 }});
 const child=await db.supplierOrder.create({data:{
  supplierId:s.supplier.id,purchaseOrderId:parent.id,
  status:'DELIVERED',subtotalPaise:10000n,totalPaise:10000n,
  platformFeePaise:800n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:'PAYOUT-MAT-'+uid().slice(0,12),
  nameSnapshot:'Supplier verified material',unitCode:'BAG',
  packSizeSnapshot:decimals(1),quantity:decimals(1),
  unitPrice:decimals(100),taxRateBps:0,taxablePaise:10000n,
  taxPaise:0n,lineTotalPaise:10000n
 }});
 const shipment=await db.shipment.create({data:{
  supplierOrderId:child.id,supplierId:s.supplier.id,
  shipmentNumber:'PAYSHIP-'+uid().replaceAll('-').slice(0,22),
  status:'DELIVERED',deliveredAt:new Date(),
  handoverMethod:'APPROVED_EXCEPTION',exceptionApprovedById:users.checker.id,
  exceptionApprovedAt:new Date(),exceptionReason:'Independent verified handover test'
 }});
 await db.shipmentItem.create({data:{
  shipmentId:shipment.id,supplierOrderItemId:item.id,
  quantity:decimals(1),deliveredQty:decimals(1)
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:k(),amountPaise:10000n,capturedPaise:10000n,status:'CAPTURED',
  providerOrderRef:'order_'+uid().replaceAll('-').slice(0,22),
  providerPayRef:'pay_'+uid().replaceAll('-').slice(0,22),
  verifiedAt:new Date()
 }});
 await db.taxInvoice.create({data:{
  supplierOrderId:child.id,supplierId:s.supplier.id,
  invoiceNumber:'PAYINV-'+uid().replaceAll('-').slice(0,22),
  financialYear:'2026-27',status:'ISSUED',kind:'BILL_OF_SUPPLY',
  sellerSnapshot:{verified:true},buyerSnapshot:{verified:true},
  lineSnapshot:{items:[]},taxablePaise:10000n,taxPaise:0n,totalPaise:10000n
 }});
 return {parent,child,item};
}
test('fixture: independent finance admins and verified online delivered seller',async()=>{
 for(const role of ['customer','outsider','maker','checker','registrar',
  'bankApprover','payoutMaker','externalReviewer','bankAttestor',
  'supplierFinance','supplierConflict']){
  const user=await db.user.create({data:{
   clerkUserId:'user_'+uid().replaceAll('-'),displayName:'Payout '+role}});
  users[role]=user;tokens[role]=user.clerkUserId;
 }
 s.supplier=await db.supplier.create({data:{
  slug:'payout-'+uid(),displayName:'Reliable Materials',approval:'APPROVED',
  legalName:provider.registered,verifiedAt:new Date()
 }});
 await db.adminMembership.createMany({data:[
  ...['maker','checker','registrar','bankApprover','payoutMaker',
    'externalReviewer','bankAttestor','supplierConflict'].map(role=>({
     userId:users[role].id,role:'FINANCE',active:true}))
 ]});
 await db.supplierMember.createMany({data:[
  {supplierId:s.supplier.id,userId:users.supplierFinance.id,role:'FINANCE',active:true},
  {supplierId:s.supplier.id,userId:users.supplierConflict.id,role:'OWNER',active:true}
 ]});
 s.order=await createDelivered();
 assert.equal((await send('get',supplier()+'/finance/beneficiaries','outsider')).status,404);
 assert.equal((await send('get',supplier()+'/finance/beneficiaries','supplierFinance')).status,200);
 assert.equal((await send('get',admin('/payouts'),'supplierFinance')).status,403);
});
test('settlement approved by independent finance creates posted accrual, NOT money movement',async()=>{
 const from=new Date(Date.now()-86400000).toISOString();
 const to=new Date(Date.now()+3600000).toISOString();
 const created=await send('post',admin('/settlements/drafts'),'maker',{
  supplierId:s.supplier.id,settlementKey:k(),periodStart:from,periodEnd:to,
  supplierOrderIds:[s.order.child.id]
 },k());
 assert.equal(created.status,201,JSON.stringify(created.body));
 s.settlement=created.body.data.id;
 const approved=await send('post',admin('/settlements/'+s.settlement+'/approve'),
  'checker',{bankStatementReference:'BANK-REFERENCE-'+uid().slice(0,20)});
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 assert.equal(approved.body.data.status,'APPROVED');
 assert.equal(await db.payoutTransfer.count({where:{settlementId:s.settlement}}),0);
});
