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


test('provider-valid bank destination requires two independent administrators',async()=>{
 const register=admin('/suppliers/'+s.supplier.id+'/beneficiaries');
 const body={fundAccountId:provider.fundId,validationId:provider.validationId};
 assert.equal((await send('post',register,'supplierConflict',body)).status,403);
 assert.equal((await send('post',register,'outsider',body)).status,403);
 provider.registered='Completely Different Legal Entity';
 const mismatch=await send('post',register,'registrar',body);
 assert.equal(mismatch.status,409,JSON.stringify(mismatch.body));
 assert.equal(mismatch.body.error.code,'PAYOUT_BENEFICIARY_NAME_MISMATCH');
 provider.registered=provider.bankHolder;
 const created=await send('post',register,'registrar',body);
 assert.equal(created.status,201,JSON.stringify(created.body));
 s.accountId=created.body.data.id;
 assert.equal(created.body.data.active,false);
 assert.equal(created.body.data.bankValidationApproved,false);
 assert.equal(created.body.data.maskedBankAccount,'****5678');
 assert(!JSON.stringify(created.body).includes('123456785678'));
 const duplicated=await send('post',register,'registrar',body);
 assert.equal(duplicated.status,200);
 assert.equal(duplicated.body.replayed,true);
 const check=admin('/beneficiaries/'+s.accountId+'/approve');
 assert.equal((await send('post',check,'registrar',{})).status,403);
 assert.equal((await send('post',check,'supplierConflict',{})).status,403);
 provider.ifsc='HDFC0000999';
 const changed=await send('post',check,'bankApprover',{});
 assert.equal(changed.status,409,JSON.stringify(changed.body));
 provider.ifsc='HDFC0000123';
 const approved=await send('post',check,'bankApprover',{});
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 assert.equal(approved.body.data.beneficiary.active,true);
 assert.equal(approved.body.data.beneficiary.bankValidationApproved,true);
 const view=await send('get',supplier()+'/finance/beneficiaries','supplierFinance');
 assert.equal(view.status,200);
 assert.equal(view.body.data.length,1);
 assert.equal(view.body.data[0].maskedBankAccount,'****5678');
 assert.equal(view.body.data[0].active,true);
 const again=await send('post',check,'bankApprover',{});
 assert.equal(again.status,200);
 assert.equal(again.body.data.replayed,true);
 const stored=await db.supplierPayoutAccount.findUniqueOrThrow({where:{id:s.accountId}});
 assert.equal(stored.bankAccountLast4,'5678');
 assert.equal(stored.providerTokenRef,provider.fundId);
 assert.equal(stored.approvedById,users.bankApprover.id);
});
test('one payout per independently approved settlement; no automatic bank transfer',async()=>{
 const endpoint=admin('/settlements/'+s.settlement+'/payout-intent');
 const body={payoutAccountId:s.accountId};
 assert.equal((await send('post',endpoint,'payoutMaker',body)).status,428);
 assert.equal((await send('post',endpoint,'checker',body,k())).status,409);
 assert.equal((await send('post',endpoint,'bankApprover',body,k())).status,409);
 assert.equal((await send('post',endpoint,'supplierConflict',body,k())).status,403);
 const idem=k();
 const made=await send('post',endpoint,'payoutMaker',body,idem);
 assert.equal(made.status,201,JSON.stringify(made.body));
 s.payout=made.body.data;
 assert.equal(s.payout.status,'PENDING');
 assert.equal(s.payout.amountPaise,'9200');
 assert.match(s.payout.externalReferenceId,/^BT[A-F0-9]{32}$/);
 assert.equal(s.payout.providerPayoutId,null);
 assert.equal(s.payout.payoutExecutionByBuildtoApi,false);
 assert.equal((await db.settlement.findUniqueOrThrow({where:{id:s.settlement}})).paidAt,null);
 const replay=await send('post',endpoint,'payoutMaker',body,idem);
 assert.equal(replay.status,200,JSON.stringify(replay.body));
 assert.equal(replay.body.data.id,s.payout.id);
 assert.equal((await send('post',endpoint,'payoutMaker',body,k())).status,409);
 assert.equal(await db.payoutTransfer.count({where:{settlementId:s.settlement}}),1);
 provider.referenceId=s.payout.externalReferenceId;
 assert(!provider.calls.some(x=>x.includes('POST')));
});
test('RazorpayX payout read-only GET enforces exact reference, destination, amount and UTR',async()=>{
 const url=admin('/payouts/'+s.payout.id+'/reconcile');
 const body={providerPayoutId:provider.payoutId};
 assert.equal((await send('post',url,'payoutMaker',body)).status,403);
 assert.equal((await send('post',url,'supplierConflict',body)).status,403);
 provider.amount=9201n;
 const mismatch=await send('post',url,'externalReviewer',body);
 assert.equal(mismatch.status,409,JSON.stringify(mismatch.body));
 assert.equal(mismatch.body.error.code,'PAYOUT_PROVIDER_MISMATCH');
 provider.amount=9200n;
 provider.referenceId='BT'+'F'.repeat(32);
 assert.equal((await send('post',url,'externalReviewer',body)).status,409);
 provider.referenceId=s.payout.externalReferenceId;
 provider.status='processed';
 provider.utr=null;
 assert.equal((await send('post',url,'externalReviewer',body)).status,409);
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'payout:processed:'+s.payout.id}}),0);
 provider.status='processing';
 const pending=await send('post',url,'externalReviewer',body);
 assert.equal(pending.status,200,JSON.stringify(pending.body));
 assert.equal(pending.body.data.payout.status,'PROCESSING');
 assert.equal(pending.body.data.payout.providerPayoutId,provider.payoutId);
 assert.equal((await db.settlement.findUniqueOrThrow({where:{id:s.settlement}})).status,'PROCESSING');
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'payout:processed:'+s.payout.id}}),0);
 provider.status='processed';
 provider.utr='UTR12345678900123';
 const completed=await send('post',url,'externalReviewer',body);
 assert.equal(completed.status,200,JSON.stringify(completed.body));
 assert.equal(completed.body.data.payout.status,'SUCCEEDED');
 assert.equal(completed.body.data.payout.settlementStatus,'PAID');
 const journal=await db.ledgerJournal.findUniqueOrThrow({where:{
  referenceKey:'payout:processed:'+s.payout.id},include:{lines:true}});
 assert(journal.postedAt);
 assert.equal(journal.lines.length,2);
 assert.equal(journal.lines.reduce((x,l)=>x+l.debitPaise,0n),9200n);
 assert.equal(journal.lines.reduce((x,l)=>x+l.creditPaise,0n),9200n);
 const settlement=await db.settlement.findUniqueOrThrow({where:{id:s.settlement}});
 assert.equal(settlement.status,'PAID');
 assert(settlement.paidAt);
 const again=await send('post',url,'externalReviewer',body);
 assert.equal(again.status,200,JSON.stringify(again.body));
 assert.equal(again.body.data.replayed,true);
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'payout:processed:'+s.payout.id}}),1);
});
test('bank statement independently attested against exact provider UTR, never called bank verified',async()=>{
 const path=admin('/payouts/'+s.payout.id+'/bank-attest');
 const body={bankStatementReference:'BANK-OUT-2026-'+uid().slice(0,20),
  providerUtr:provider.utr};
 assert.equal((await send('post',path,'payoutMaker',body)).status,403);
 assert.equal((await send('post',path,'externalReviewer',body)).status,403);
 assert.equal((await send('post',path,'bankAttestor',
  {...body,providerUtr:'WRONGUTR987654321'})).status,409);
 const done=await send('post',path,'bankAttestor',body);
 assert.equal(done.status,200,JSON.stringify(done.body));
 assert.equal(done.body.data.bankStatementAttested,true);
 assert.equal(done.body.data.bankStatementAPIReconciled,false);
 assert.equal(done.body.data.bankEvidenceType,'HUMAN_ATTESTATION');
 const again=await send('post',path,'bankAttestor',body);
 assert.equal(again.status,200);assert.equal(again.body.data.replayed,true);
 assert.equal((await send('post',path,'bankAttestor',
  {...body,bankStatementReference:'BANK-CHANGED-REFERENCE-2026'})).status,409);
 const report=await send('get',admin('/payouts-reconciliation'),'checker');
 assert.equal(report.status,200,JSON.stringify(report.body));
 assert.equal(report.body.data.bankStatementAPIReconciled,false);
 assert.equal(report.body.data.payoutExecutionEnabledByApi,false);
 assert.equal(report.body.data.payouts.find(x=>x.id===s.payout.id).bankStatementAttested,true);
 const vendor=await send('get',supplier()+'/finance/payouts','supplierFinance');
 assert.equal(vendor.status,200);
 assert.equal(vendor.body.data[0].status,'SUCCEEDED');
 assert.equal(vendor.body.data[0].maskedBankAccount,'****5678');
});


test('PostgreSQL rejects forged payout success, duplicate payout and bank destination mutation',async()=>{
 await assert.rejects(db.supplierPayoutAccount.update({where:{id:s.accountId},
  data:{bankAccountLast4:'9999'}}));
 await assert.rejects(db.payoutTransfer.update({where:{id:s.payout.id},
  data:{amountPaise:100n}}));
 await assert.rejects(db.payoutTransfer.create({data:{
  settlementId:s.settlement,payoutAccountId:s.accountId,
  requestKey:k(),status:'PENDING',amountPaise:9200n
 }}));
 await assert.rejects(db.settlement.update({where:{id:s.settlement},
  data:{status:'PROCESSING',paidAt:null}}));
 assert.equal(await db.payoutTransfer.count({where:{settlementId:s.settlement}}),1);
 assert.equal((await db.settlement.findUniqueOrThrow({where:{id:s.settlement}})).status,'PAID');
 provider.status='reversed';
 const after=await send('post',admin('/payouts/'+s.payout.id+'/reconcile'),
  'externalReviewer',{providerPayoutId:provider.payoutId});
 assert.equal(after.status,409,JSON.stringify(after.body));
 assert.equal(after.body.error.code,'PAYOUT_ALREADY_FINALIZED');
 provider.status='processed';
});
test('RazorpayX reversed payout stays FAILED and cannot quietly generate a second transfer',async()=>{
 const order=await createDelivered();
 const drafted=await send('post',admin('/settlements/drafts'),'maker',{
  supplierId:s.supplier.id,settlementKey:k(),
  periodStart:new Date(Date.now()-86400000).toISOString(),
  periodEnd:new Date(Date.now()+3600000).toISOString(),
  supplierOrderIds:[order.child.id]
 },k());
 assert.equal(drafted.status,201,JSON.stringify(drafted.body));
 const approved=await send('post',admin('/settlements/'+drafted.body.data.id+'/approve'),
  'checker',{bankStatementReference:'BANK-SECOND-'+uid().slice(0,21)});
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 const intent=await send('post',admin('/settlements/'+drafted.body.data.id+'/payout-intent'),
  'payoutMaker',{payoutAccountId:s.accountId},k());
 assert.equal(intent.status,201,JSON.stringify(intent.body));
 const old={...provider};
 provider.payoutId='pout_'+uid().replaceAll('-').slice(0,18);
 provider.referenceId=intent.body.data.externalReferenceId;
 provider.status='reversed';provider.utr=null;
 const failed=await send('post',admin('/payouts/'+intent.body.data.id+'/reconcile'),
  'externalReviewer',{providerPayoutId:provider.payoutId});
 assert.equal(failed.status,200,JSON.stringify(failed.body));
 assert.equal(failed.body.data.payout.status,'FAILED');
 assert.equal((await db.settlement.findUniqueOrThrow({
  where:{id:drafted.body.data.id}})).status,'FAILED');
 assert.equal(await db.ledgerJournal.count({where:{
  referenceKey:'payout:processed:'+intent.body.data.id}}),0);
 assert.equal((await send('post',admin('/payouts/'+intent.body.data.id+'/reconcile'),
  'externalReviewer',{providerPayoutId:provider.payoutId})).status,409);
 assert.equal((await send('post',admin('/settlements/'+drafted.body.data.id+'/payout-intent'),
  'payoutMaker',{payoutAccountId:s.accountId},k())).status,409);
 assert.equal((await send('post',admin('/payouts/'+intent.body.data.id+'/bank-attest'),
  'bankAttestor',{bankStatementReference:'BANK-FAILED-PAYOUT-2026',
   providerUtr:'UTR12345678901111'})).status,409);
 Object.assign(provider,old);
});
test('RazorpayX adapter only fetches provider GET and never exposes full account number',async()=>{
 const {RazorpayXPayoutEvidence}=require('../dist/payout-gateway.js');
 const gateway=new RazorpayXPayoutEvidence('rzp_test_fakefinance','fake-secret');
 const oldFetch=global.fetch,calls=[];
 global.fetch=async(url,init)=>{
  calls.push({url,method:init.method});
  if(url.endsWith('/fund_accounts/'+provider.fundId))
   return {ok:true,json:async()=>({
    id:provider.fundId,active:true,account_type:'bank_account',
    bank_account:{name:provider.bankHolder,ifsc:provider.ifsc,account_number:'123456785678'}
   })};
  if(url.endsWith('/fund_accounts/validations/'+provider.validationId))
   return {ok:true,json:async()=>({
    id:provider.validationId,status:'completed',
    fund_account:{id:provider.fundId},
    results:{account_status:'active',registered_name:provider.registered}
   })};
  return {ok:true,json:async()=>({
   id:provider.payoutId,entity:'payout',fund_account_id:provider.fundId,
   amount:9200,currency:'INR',purpose:'payout',
   reference_id:s.payout.externalReferenceId,status:'processed',utr:'UTR12345678900123'
  })};
 };
 try{
  const account=await gateway.fetchFundAccount(provider.fundId);
  assert.equal(account.last4,'5678');
  assert(!JSON.stringify(account).includes('123456785678'));
  const validation=await gateway.fetchValidation(provider.validationId);
  assert.equal(validation.fundAccountId,provider.fundId);
  const payout=await gateway.fetchPayout(provider.payoutId);
  assert.equal(payout.amount,9200n);
  assert.equal(payout.status,'processed');
  assert.equal(calls.length,3);
  assert(calls.every(c=>c.method==='GET'));
 }finally{global.fetch=oldFetch;}
});
test('staging refuses live RazorpayX evidence keys; no half-configured finance gateway',()=>{
 const base={BUILDTO_V21_ENV:'local',
  DATABASE_URL:'postgresql://postgres:postgres@127.0.0.1:5432/buildto_v21_test'};
 assert.throws(()=>readConfig({...base,
  RAZORPAYX_READ_ONLY_KEY_ID:'rzp_test_validonly'}),/RAZORPAYX_READ_ONLY_CONFIG_INVALID/);
 assert.throws(()=>readConfig({...base,BUILDTO_V21_ENV:'staging',
  DATABASE_URL:'postgresql://placeholder:placeholder@ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech/neondb',
  BUILDTO_V21_CORS_ORIGINS:'https://staging.buildto.test',
  RAZORPAYX_READ_ONLY_KEY_ID:'rzp_live_danger',RAZORPAYX_READ_ONLY_KEY_SECRET:'fake'}),/RAZORPAYX_STAGING_LIVE_KEY_DENIED/);
});
