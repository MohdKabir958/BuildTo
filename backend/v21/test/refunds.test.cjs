'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),key=()=> 'refund_'+id().replaceAll('-'),uid=()=> 'user_'+id().replaceAll('-');
const u={},tokens={},state={};
const paymentProvider={id:'rfnd_1234567890abcdefgh',amount:11800n,currency:'INR',
 paymentId:'',status:'pending'};
let lookupCalled=0;
const gateway={publicKey:'rzp_test_mockRefunds',createOrder:async()=>{throw Error('PROVIDER_POST_FORBIDDEN')},
 lookupRefund:async providerId=>{
  lookupCalled++;
  return {...paymentProvider,id:providerId};
 }};
const api=request(createV21App({db,allowedOrigins:[],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},paymentGateway:gateway,
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
  return {subject:tokens[token],sessionId:'sess_v21_refund_test_1'};
 }}}));
const send=(method,path,actor,body,idem)=>{
 let req=api[method](path);
 if(actor)req=req.set('Authorization','Bearer '+actor);
 if(idem)req=req.set('Idempotency-Key',idem);
 return body===undefined?req:req.send(body);
};
const finance=(x='')=>'/api/v2/admin/finance'+x;
const credit=(r)=>'/api/v2/suppliers/'+state.supplier.id+'/returns/'+r.id+'/credit-note';
const Dec=n=>new Prisma.Decimal(n);
async function orderWithReturn({received=true,returnedQty=2,method='RAZORPAY'}={}){
 const purchaseOrder=await db.purchaseOrder.create({data:{
  publicNumber:'BT-RF-'+id().replaceAll('-').slice(0,25),
  customerId:u.customer.id,clientRequestId:key(),
  currency:'INR',status:'CONFIRMED',subtotalPaise:10000n,
  taxPaise:1800n,totalPaise:11800n,
  addressSnapshot:{recipientName:'Return buyer',line1:'Real address',city:'Hyderabad',
   stateCode:'TS',postalCode:'500001'}
 }});
 const child=await db.supplierOrder.create({data:{
  supplierId:state.supplier.id,purchaseOrderId:purchaseOrder.id,
  status:'DELIVERED',subtotalPaise:10000n,taxPaise:1800n,
  platformFeePaise:500n,totalPaise:11800n
 }});
 const sku='RF-CEMENT-'+id().replaceAll('-').slice(0,20);
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:sku,nameSnapshot:'Return test cement',
  unitCode:'BAG',packSizeSnapshot:Dec(1),quantity:Dec(2),
  unitPrice:Dec('50'),taxRateBps:1800,hsnSnapshot:'2523',
  taxablePaise:10000n,discountPaise:0n,taxPaise:1800n,
  igstPaise:1800n,lineTotalPaise:11800n
 }});
 const shipment=await db.shipment.create({data:{
  supplierId:state.supplier.id,supplierOrderId:child.id,
  shipmentNumber:'RFSH-'+id().replaceAll('-').slice(0,22),
  status:'DELIVERED',deliveredAt:new Date(),
  handoverMethod:'APPROVED_EXCEPTION',exceptionApprovedById:u.checker.id,
  exceptionApprovedAt:new Date(),exceptionReason:'Independent physical handover verification test'
 }});
 await db.shipmentItem.create({data:{
  shipmentId:shipment.id,supplierOrderItemId:item.id,
  quantity:Dec(2),deliveredQty:Dec(2)
 }});
 const payment=await db.paymentAttempt.create({data:{
  purchaseOrderId:purchaseOrder.id,provider:method==='MANUAL'?'MANUAL':'RAZORPAY',
  paymentMethod:method==='MANUAL'?'COD':'UPI',idempotencyKey:key(),
  amountPaise:11800n,capturedPaise:method==='MANUAL'?0n:11800n,
  status:method==='MANUAL'?'PENDING':'CAPTURED',
  ...(method!=='MANUAL'?{
   providerOrderRef:'order_'+id().replaceAll('-').slice(0,23),
   providerPayRef:'pay_'+id().replaceAll('-').slice(0,23),
   verifiedAt:new Date()}:{})
 }});
 const invoice=await db.taxInvoice.create({data:{
  supplierId:state.supplier.id,supplierOrderId:child.id,
  invoiceNumber:'RFT-'+id().replaceAll('-').slice(0,22),
  financialYear:'2026-27',status:'ISSUED',kind:'TAX_INVOICE',
  sellerSnapshot:{legalName:'Tax Materials Pvt Ltd',gstin:'36AAAAA0000A1Z5'},
  buyerSnapshot:{recipientName:'Return buyer',stateCode:'TS'},
  lineSnapshot:{items:[{sku,name:'Return test cement',hsn:'2523',
   unitCode:'BAG',quantity:'2',unitPrice:'50',taxRateBps:1800,
   taxablePaise:'10000',discountPaise:'0',taxPaise:'1800',
   cgstPaise:'0',sgstPaise:'0',utgstPaise:'0',igstPaise:'1800',cessPaise:'0',
   lineTotalPaise:'11800'}]},
  taxablePaise:10000n,taxPaise:1800n,totalPaise:11800n,igstPaise:1800n
 }});
 const ret=await db.returnRequest.create({data:{
  supplierOrderId:child.id,customerId:u.customer.id,
  reason:'Full material return after delivery verification',
  status:received?'RECEIVED':'REQUESTED',
  items:{create:{supplierOrderItemId:item.id,quantity:Dec(returnedQty)}}
 }});
 if(received)await db.auditEvent.create({data:{
  entityType:'ReturnRequest',entityId:ret.id,action:'SUPPLIER_RETURN_PHYSICALLY_RECEIVED',
  actorUserId:u.receiver.id,actorSupplierId:state.supplier.id,
  actorRole:'SUPPLIER_FULFILLMENT'
 }});
 return {purchaseOrder,child,item,shipment,payment,invoice,ret};
}
test('fixture: approved GST supplier, verified payment, independent roles and physical return',async()=>{
 for(const role of ['customer','outsider','issuer','receiver','maker','checker','conflicted','viewer']){
  const user=await db.user.create({data:{clerkUserId:uid(),displayName:'Refund '+role}});
  u[role]=user;tokens[role]=user.clerkUserId;
 }
 state.supplier=await db.supplier.create({data:{
  slug:'refund-test-'+id(),legalName:'Tax Materials Pvt Ltd',
  displayName:'Tax Materials',approval:'APPROVED',verifiedAt:new Date(),
  gstRegistration:'REGULAR',gstin:'36AAAAA0000A1Z5'
 }});
 await db.supplierMember.createMany({data:[
  {supplierId:state.supplier.id,userId:u.issuer.id,role:'FINANCE',active:true},
  {supplierId:state.supplier.id,userId:u.receiver.id,role:'FULFILLMENT',active:true},
  {supplierId:state.supplier.id,userId:u.conflicted.id,role:'OWNER',active:true},
  {supplierId:state.supplier.id,userId:u.viewer.id,role:'VIEWER',active:true}
 ]});
 await db.adminMembership.createMany({data:[
  {userId:u.maker.id,role:'FINANCE',active:true},
  {userId:u.checker.id,role:'FINANCE',active:true},
  {userId:u.conflicted.id,role:'FINANCE',active:true}
 ]});
 state.online=await orderWithReturn({});
 paymentProvider.paymentId=state.online.payment.providerPayRef;
 assert.equal((await send('get','/api/v2/orders/'+state.online.purchaseOrder.id+'/refunds','outsider')).status,404);
 assert.equal((await send('get',finance('/refunds'),'outsider')).status,403);
 assert.equal((await send('get',finance('/refunds'),'maker')).status,200);
});
test('GST credit note is supplier-finance-only, independent, exact and idempotent',async()=>{
 const endpoint=credit(state.online.ret);
 assert.equal((await send('post',endpoint,'outsider',{})).status,404);
 assert.equal((await send('post',endpoint,'viewer',{})).status,403);
 assert.equal((await send('post',endpoint,'receiver',{})).status,403);
 assert.equal((await send('post',endpoint,'issuer',{totalPaise:'1'})).status,400);
 const issued=await send('post',endpoint,'issuer',{});
 assert.equal(issued.status,201,JSON.stringify(issued.body));
 state.credit=issued.body.data;
 assert.equal(state.credit.kind,'CREDIT_NOTE');
 assert.equal(state.credit.sourceInvoiceId,state.online.invoice.id);
 assert.equal(state.credit.totalPaise,'11800');
 assert.equal(state.credit.taxablePaise,'10000');
 assert.equal(state.credit.igstPaise,'1800');
 assert.equal(state.credit.returnRequestId,state.online.ret.id);
 const repeated=await send('post',endpoint,'issuer',{});
 assert.equal(repeated.status,200,JSON.stringify(repeated.body));
 assert.equal(repeated.body.replayed,true);
 assert.equal(repeated.body.data.id,state.credit.id);
 assert.equal(await db.taxInvoice.count({where:{kind:'CREDIT_NOTE',
  returnRequestId:state.online.ret.id}}),1);
 const linked=await db.taxInvoice.findUniqueOrThrow({where:{id:state.credit.id}});
 assert.equal(linked.status,'ISSUED');
 assert.equal(linked.sourceInvoiceId,state.online.invoice.id);
});
test('refund reserves exactly one captured payment budget; maker-checker separation',async()=>{
 const endpoint=finance('/refunds/requests/'+state.online.ret.id);
 assert.equal((await send('post',endpoint,'maker',{})).status,428);
 assert.equal((await send('post',endpoint,'outsider',{},key())).status,403);
 assert.equal((await send('post',endpoint,'conflicted',{},key())).status,403);
 assert.equal((await send('post',endpoint,'maker',{amountPaise:'1'},key())).status,400);
 const k=key();
 const created=await send('post',endpoint,'maker',{},k);
 assert.equal(created.status,201,JSON.stringify(created.body));
 state.refund=created.body.data;
 assert.equal(state.refund.amountPaise,'11800');
 assert.equal(state.refund.status,'REQUESTED');
 assert.equal(state.refund.providerRefundId,null);
 assert.equal(state.refund.customerBankCredit,'NOT_VERIFIED');
 const repeated=await send('post',endpoint,'maker',{},k);
 assert.equal(repeated.status,200,JSON.stringify(repeated.body));
 assert.equal(repeated.body.replayed,true);
 assert.equal(repeated.body.data.id,state.refund.id);
 assert.equal((await send('post',endpoint,'maker',{},key())).status,409);
 assert.equal(await db.refundRequest.count({where:{returnRequestId:state.online.ret.id}}),1);
 const approve=finance('/refunds/'+state.refund.id+'/approve');
 assert.equal((await send('post',approve,'maker',{})).status,403);
 assert.equal((await send('post',approve,'conflicted',{})).status,403);
 const valid=await send('post',approve,'checker',{});
 assert.equal(valid.status,200,JSON.stringify(valid.body));
 assert.equal(valid.body.data.status,'APPROVED');
 assert.equal(valid.body.data.providerRefundId,null);
 assert.equal((await send('post',approve,'checker',{})).status,409);
});
test('provider REFUND lookup is read-only, rejects mismatched payment or amount',async()=>{
 const endpoint=finance('/refunds/'+state.refund.id+'/reconcile');
 assert.equal((await send('post',endpoint,'maker',{providerRefundId:'bad'})).status,400);
 paymentProvider.paymentId='pay_WRONGPAYMENT123';
 const mismatch=await send('post',endpoint,'checker',{providerRefundId:paymentProvider.id});
 assert.equal(mismatch.status,409,JSON.stringify(mismatch.body));
 assert.equal(mismatch.body.error.code,'REFUND_PROVIDER_EVIDENCE_MISMATCH');
 paymentProvider.paymentId=state.online.payment.providerPayRef;
 paymentProvider.amount=11801n;
 assert.equal((await send('post',endpoint,'checker',{providerRefundId:paymentProvider.id})).status,409);
 paymentProvider.amount=11800n;
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'refund:processed:'+state.refund.id}}),0);
 assert(lookupCalled>=2);
});
test('Razorpay pending is never SUCCEEDED; processed posts one balanced immutable memo',async()=>{
 const endpoint=finance('/refunds/'+state.refund.id+'/reconcile');
 paymentProvider.status='pending';
 const pending=await send('post',endpoint,'checker',{providerRefundId:paymentProvider.id});
 assert.equal(pending.status,200,JSON.stringify(pending.body));
 assert.equal(pending.body.data.refund.status,'PROCESSING');
 assert.equal(pending.body.data.refund.customerBankCredit,'NOT_VERIFIED');
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'refund:processed:'+state.refund.id}}),0);
 paymentProvider.status='processed';
 const finished=await send('post',endpoint,'checker',{providerRefundId:paymentProvider.id});
 assert.equal(finished.status,200,JSON.stringify(finished.body));
 assert.equal(finished.body.data.refund.status,'SUCCEEDED');
 assert.equal(finished.body.data.refund.customerBankCredit,'NOT_VERIFIED');
 const j=await db.ledgerJournal.findUniqueOrThrow({where:{
  referenceKey:'refund:processed:'+state.refund.id},include:{lines:true}});
 assert(j.postedAt);
 assert.equal(j.lines.length,2);
 assert.equal(j.lines.reduce((n,l)=>n+l.debitPaise,0n),11800n);
 assert.equal(j.lines.reduce((n,l)=>n+l.creditPaise,0n),11800n);
 const repeated=await send('post',endpoint,'checker',{providerRefundId:paymentProvider.id});
 assert.equal(repeated.status,200);assert.equal(repeated.body.data.replayed,true);
 assert.equal(await db.ledgerJournal.count({where:{referenceKey:'refund:processed:'+state.refund.id}}),1);
 const customer=await send('get','/api/v2/orders/'+state.online.purchaseOrder.id+'/refunds','customer');
 assert.equal(customer.status,200);
 assert.equal(customer.body.data[0].status,'SUCCEEDED');
 assert.equal(customer.body.data[0].customerBankCredit,'NOT_VERIFIED');
});


test('partial returns cannot fabricate line tax credits or manual refund amounts',async()=>{
 const partial=await orderWithReturn({returnedQty:1});
 const attempt=await send('post',credit(partial.ret),'issuer',{});
 assert.equal(attempt.status,409,JSON.stringify(attempt.body));
 assert.equal(attempt.body.error.code,'CREDIT_NOTE_PARTIAL_UNSUPPORTED');
 assert.equal(await db.taxInvoice.count({where:{returnRequestId:partial.ret.id}}),0);
 assert.equal((await send('post',finance('/refunds/requests/'+partial.ret.id),
  'maker',{},key())).status,409);
});
test('supplier-collected COD never becomes an online Razorpay refund',async()=>{
 const cod=await orderWithReturn({method:'MANUAL'});
 const note=await send('post',credit(cod.ret),'issuer',{});
 assert.equal(note.status,201,JSON.stringify(note.body));
 const rejected=await send('post',finance('/refunds/requests/'+cod.ret.id),
  'maker',{},key());
 assert.equal(rejected.status,409,JSON.stringify(rejected.body));
 assert.equal(rejected.body.error.code,'REFUND_VERIFIED_CAPTURE_REQUIRED');
 assert.equal(await db.refundRequest.count({where:{returnRequestId:cod.ret.id}}),0);
});
test('an active settlement blocks credit notes and refunds until independently unwound',async()=>{
 const held=await orderWithReturn({});
 const settle=await db.settlement.create({data:{
  supplierId:state.supplier.id,settlementKey:key(),status:'ON_HOLD',
  periodStart:new Date(Date.now()-86400000),periodEnd:new Date(Date.now()+86400000),
  grossPaise:held.child.totalPaise,commissionPaise:held.child.platformFeePaise,
  payablePaise:held.child.totalPaise-held.child.platformFeePaise,
  lines:{create:{supplierOrderId:held.child.id,
   grossPaise:held.child.totalPaise,commissionPaise:held.child.platformFeePaise,
   netPaise:held.child.totalPaise-held.child.platformFeePaise}}
 }});
 const refused=await send('post',credit(held.ret),'issuer',{});
 assert.equal(refused.status,409,JSON.stringify(refused.body));
 assert.equal(refused.body.error.code,'CREDIT_NOTE_FINANCIAL_HOLD');
 await db.settlement.update({where:{id:settle.id},data:{status:'CANCELLED'}});
 const creditAfter=await send('post',credit(held.ret),'issuer',{});
 assert.equal(creditAfter.status,201,JSON.stringify(creditAfter.body));
});
test('provider-failed status stays MANUAL_REVIEW with reserved budget, not SUCCEEDED',async()=>{
 const failure=await orderWithReturn({});
 assert.equal((await send('post',credit(failure.ret),'issuer',{})).status,201);
 const created=await send('post',finance('/refunds/requests/'+failure.ret.id),'maker',{},key());
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal((await send('post',finance('/refunds/'+created.body.data.id+'/approve'),
  'checker',{})).status,200);
 const old={...paymentProvider};
 paymentProvider.id='rfnd_'+id().replaceAll('-').slice(0,21);
 paymentProvider.paymentId=failure.payment.providerPayRef;
 paymentProvider.status='failed';
 const failed=await send('post',finance('/refunds/'+created.body.data.id+'/reconcile'),
  'checker',{providerRefundId:paymentProvider.id});
 assert.equal(failed.status,200,JSON.stringify(failed.body));
 assert.equal(failed.body.data.refund.status,'MANUAL_REVIEW');
 assert.equal(failed.body.data.refund.customerBankCredit,'NOT_VERIFIED');
 assert.equal(await db.ledgerJournal.count({where:{
  referenceKey:'refund:processed:'+created.body.data.id}}),0);
 assert.equal((await send('post',finance('/refunds/requests/'+failure.ret.id),
  'maker',{},key())).status,409);
 assert.equal((await send('post',finance('/refunds/'+created.body.data.id+'/approve'),
  'checker',{})).status,409);
 Object.assign(paymentProvider,old);
});
test('database rejects mutation of posted refund, issued GST credit and its original invoice',async()=>{
 await assert.rejects(db.refundRequest.update({where:{id:state.refund.id},
  data:{amountPaise:42n}}),e=>e.code==='P2004'||e.code==='P2010'||/immutable/i.test(e.message));
 await assert.rejects(db.taxInvoice.update({where:{id:state.credit.id},
  data:{totalPaise:13000n}}),e=>e.code==='P2004'||e.code==='P2010'||/immutable/i.test(e.message));
 await assert.rejects(db.taxInvoice.update({where:{id:state.online.invoice.id},
  data:{status:'CREDITED'}}),e=>e.code==='P2004'||e.code==='P2010'||/immutable/i.test(e.message));
 const j=await db.ledgerJournal.findUniqueOrThrow({where:{
  referenceKey:'refund:processed:'+state.refund.id},include:{lines:true}});
 await assert.rejects(db.ledgerLine.update({where:{
  journalId_lineNumber:{journalId:j.id,lineNumber:1}
 },data:{debitPaise:10n}}));
 assert.equal(await db.refundRequest.count({where:{id:state.refund.id,status:'SUCCEEDED'}}),1);
});


test('refund evidence selects captured payment despite a failed earlier attempt',async()=>{
 const order=await orderWithReturn({});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:order.purchaseOrder.id,provider:'RAZORPAY',
  paymentMethod:'UPI',idempotencyKey:key(),status:'FAILED',amountPaise:11800n
 }});
 const note=await send('post',credit(order.ret),'issuer',{});
 assert.equal(note.status,201,JSON.stringify(note.body));
 const requested=await send('post',finance('/refunds/requests/'+order.ret.id),
  'maker',{},key());
 assert.equal(requested.status,201,JSON.stringify(requested.body));
 const saved=await db.refundRequest.findUniqueOrThrow({where:{id:requested.body.data.id}});
 assert.equal(saved.paymentAttemptId,order.payment.id,
  'refund must link the actual captured attempt, never the failed attempt');
});
