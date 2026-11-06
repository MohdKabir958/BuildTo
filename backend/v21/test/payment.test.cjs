'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID,createHmac}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {verifyRazorpayWebhook,recoverExpiredPaymentSessions}=require('../dist/payment-service.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const uuid=()=>randomUUID();
const sub=()=> 'user_'+uuid().replaceAll('-','');
const secret='ci_razorpay_webhook_secret_01234567890123456789';
const tokens={};
const state={calls:0};
const gateway={publicKey:'rzp_test_fake12345678',
 inspectOrderPayments:async()=>({status:state.providerInspection||'NO_ACTIVE_PAYMENT'}),
 createOrder:async({amount,receipt})=>{
  state.calls++;
  return {id:'order_'+uuid().replaceAll('-','').slice(0,20),
   amount,currency:'INR',receipt};
 }
};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,limiter:new InMemoryTestLimiter(),
 log:()=>{},paymentGateway:gateway,razorpayWebhookSecret:secret,
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
  return {subject:tokens[token],sessionId:'sess_paymentfixture123'};
 }}});
const http=request(app);
function call(method,url,token,body,key){
 let r=http[method](url);
 if(token)r=r.set('Authorization','Bearer '+token);
 if(key)r=r.set('Idempotency-Key',key);
 return body===undefined?r:r.send(body);
}
function signedEvent(event,payment,eventId='evt_'+uuid().replaceAll('-','')){
 const payload={event,payload:{payment:{entity:payment}}};
 const raw=JSON.stringify(payload);
 const signature=createHmac('sha256',secret).update(raw).digest('hex');
 return http.post('/api/v2/webhooks/razorpay').set('Content-Type','application/json')
  .set('x-razorpay-event-id',eventId).set('x-razorpay-signature',signature).send(raw);
}
function pEntity(stateName,amount='15000'){
 return {id:'pay_'+uuid().replaceAll('-','').slice(0,20),
  order_id:state.providerOrderId,amount:Number(amount),currency:'INR',
  status:stateName,method:'upi'};
}
test('fixtures: supplier listing, order, guarded stock hold and customer',async()=>{
 const customer=await db.user.create({data:{clerkUserId:sub(),displayName:'Paying customer'}});
 const outsider=await db.user.create({data:{clerkUserId:sub(),displayName:'Other customer'}});
 tokens.customer=customer.clerkUserId;tokens.outsider=outsider.clerkUserId;
 const supplier=await db.supplier.create({data:{
  slug:'pay-'+uuid(),legalName:'Pay fixture supplier',displayName:'Supplier',approval:'APPROVED'
 }});
 const category=await db.category.create({data:{slug:'pay-'+uuid(),name:'Payments',active:true}});
 const product=await db.product.create({data:{
  code:'PAY-'+uuid().slice(0,16).toUpperCase(),categoryId:category.id,name:'Cement',active:true
 }});
 const listing=await db.supplierListing.create({data:{
  supplierId:supplier.id,productId:product.id,sku:'PAY-'+uuid().slice(0,16),
  unitCode:'BAG',unitPrice:new Prisma.Decimal('75.0000'),
  status:'APPROVED',active:true,publishedAt:new Date()
 }});
 const warehouse=await db.warehouse.create({data:{
  supplierId:supplier.id,code:'PAY-'+uuid().slice(0,16),name:'Test warehouse',active:true
 }});
 const balance=await db.inventoryBalance.create({data:{
  listingId:listing.id,warehouseId:warehouse.id,
  onHandQty:new Prisma.Decimal('10.000'),reservedQty:new Prisma.Decimal('2.000')
 }});
 const order=await db.purchaseOrder.create({data:{
  customerId:customer.id,publicNumber:'BT-'+uuid().replaceAll('-').slice(0,24),
  clientRequestId:'PAY-'+uuid().replaceAll('-'),
  currency:'INR',status:'PLACED',addressSnapshot:{city:'Hyderabad'},
  subtotalPaise:15000n,totalPaise:15000n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:order.id,supplierId:supplier.id,subtotalPaise:15000n,totalPaise:15000n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:listing.id,skuSnapshot:listing.sku,
  nameSnapshot:'Cement',unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal(1),
  quantity:new Prisma.Decimal(2),unitPrice:new Prisma.Decimal(75),
  taxRateBps:0,taxablePaise:15000n,taxPaise:0n,lineTotalPaise:15000n
 }});
 const hold=await db.inventoryReservation.create({data:{
  balanceId:balance.id,orderItemId:item.id,quantity:new Prisma.Decimal(2),
  state:'HELD',expiresAt:new Date(Date.now()+1200000)
 }});
 Object.assign(state,{customer,outsider,supplier,order,child,item,hold,balance});
 assert.equal((await http.get('/api/v2/system')).body.data.capabilities.includes('payments.razorpay'),true);
});
test('payment creation rejects cross-customer writes, missing keys and client prices',async()=>{
 const url='/api/v2/orders/'+state.order.id+'/payments';
 assert.equal((await call('post',url,'outsider',{paymentMethod:'UPI'},'pay_other_123456')).status,404);
 assert.equal((await call('post',url,'customer',{paymentMethod:'UPI'})).status,428);
 assert.equal((await call('post',url,'customer',{paymentMethod:'UPI',amountPaise:'1'},'pay_override_123')).status,400);
 assert.equal((await call('post',url,'customer',{paymentMethod:'COD'},'pay_cod_123456')).status,422);
});
test('attempt creation happens once, with no provider retry on duplicate tap',async()=>{
 const url='/api/v2/orders/'+state.order.id+'/payments';
 const key='pay_'+uuid().replaceAll('-');
 const first=await call('post',url,'customer',{paymentMethod:'UPI'},key);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.amountPaise,'15000');
 assert.equal(state.calls,1);
 state.providerOrderId=first.body.data.providerOrderId;
 assert.match(state.providerOrderId,/^order_/);
 const replay=await call('post',url,'customer',{paymentMethod:'UPI'},key);
 assert.equal(replay.status,200,JSON.stringify(replay.body));
 assert.equal(replay.body.data.id,first.body.data.id);
 assert.equal(state.calls,1);
 assert.equal((await call('post',url,'customer',{paymentMethod:'CARD'},key)).status,409);
 assert.equal((await call('post',url,'customer',{paymentMethod:'UPI'},'pay_new_'+uuid().slice(0,20))).status,409);
 assert.equal((await call('post','/api/v2/orders/'+state.order.id+'/cancel','customer',{})).status,409);
 assert.equal((await call('get',url,'outsider')).status,404);
 assert.equal((await call('get',url,'customer')).body.data.length,1);
});
test('wrong signature and payment amount cannot authorize or capture order',async()=>{
 const invalid=Buffer.from('{"event":"payment.captured"}');
 assert.throws(()=>verifyRazorpayWebhook(invalid,'0'.repeat(64),'evt_test123456',secret),
  e=>e.status===401);
 assert.equal((await http.post('/api/v2/webhooks/razorpay').send({event:'payment.captured'})).status,401);
 const bad=await signedEvent('payment.captured',pEntity('captured','100'));
 assert.equal(bad.status,200,JSON.stringify(bad.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:state.order.id}})).status,'PLACED');
 assert.equal((await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:state.order.id}})).status,'PENDING');
});
test('authorized is not captured, signed capture commits stock exactly once',async()=>{
 const pay=pEntity('captured');
 const authorized=await signedEvent('payment.authorized',{...pay,status:'authorized'});
 assert.equal(authorized.status,200,JSON.stringify(authorized.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:state.order.id}})).status,'PLACED');
 const eventId='evt_'+uuid().replaceAll('-');
 const captured=await signedEvent('payment.captured',pay,eventId);
 assert.equal(captured.status,200,JSON.stringify(captured.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:state.order.id}})).status,'CONFIRMED');
 const attempt=await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:state.order.id}});
 assert.equal(attempt.status,'CAPTURED');assert.equal(attempt.capturedPaise.toString(),'15000');
 const hold=await db.inventoryReservation.findUniqueOrThrow({where:{id:state.hold.id}});
 assert.equal(hold.state,'COMMITTED');
 let bal=await db.inventoryBalance.findUniqueOrThrow({where:{id:state.balance.id}});
 assert.equal(bal.onHandQty.toString(),'8');assert.equal(bal.reservedQty.toString(),'0');
 const replay=await signedEvent('payment.captured',pay,eventId);
 assert.equal(replay.status,200);assert.equal(replay.body.duplicate,true);
 assert.equal((await signedEvent('payment.failed',{...pay,status:'failed'})).status,200);
 assert.equal((await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:state.order.id}})).status,'CAPTURED');
 assert.equal(await db.stockMovement.count({where:{referenceKey:'sale:'+hold.id}}),1);
 const orderView=await call('get','/api/v2/orders/'+state.order.id,'customer');
 assert.equal(orderView.body.data.paymentStatus,'CAPTURED');
});
test('capture after order cancellation requires manual review, no dispatch entitlement',async()=>{
 const order=await db.purchaseOrder.create({data:{
  customerId:state.customer.id,publicNumber:'BT-'+uuid().replaceAll('-').slice(0,24),
  clientRequestId:'PAY-'+uuid().replaceAll('-'),currency:'INR',status:'PLACED',
  addressSnapshot:{city:'Hyderabad'},subtotalPaise:15000n,totalPaise:15000n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:order.id,supplierId:state.supplier.id,subtotalPaise:15000n,totalPaise:15000n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:'BESPOKE',nameSnapshot:'Special freight',
  unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(1),
  unitPrice:new Prisma.Decimal(150),taxRateBps:0,taxablePaise:15000n,
  taxPaise:0n,lineTotalPaise:15000n
 }});
 const providerOrderRef='order_'+uuid().replaceAll('-').slice(0,20);
 await db.paymentAttempt.create({data:{
  purchaseOrderId:order.id,provider:'RAZORPAY',paymentMethod:'UPI',
  providerOrderRef,idempotencyKey:'manual_'+uuid().replaceAll('-'),
  amountPaise:15000n,status:'PENDING'
 }});
 const pay={id:'pay_'+uuid().replaceAll('-').slice(0,20),order_id:providerOrderRef,
  amount:15000,currency:'INR',status:'captured',method:'upi'};
 // A cancelled order (or a stale listed hold) must never be resurrected.
 await db.purchaseOrder.update({where:{id:order.id},data:{status:'CANCELLED',cancelledAt:new Date()}});
 const captured=await signedEvent('payment.captured',pay);
 assert.equal(captured.status,200,JSON.stringify(captured.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:order.id}})).status,'CANCELLED');
 assert.equal((await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:order.id}})).status,'CAPTURED');
 assert.equal(await db.auditEvent.count({where:{entityId:order.id,action:'PAYMENT_CAPTURED_REQUIRES_REVIEW'}}),1);
});

test('partial warehouse stock holds can never authorize the entire purchase',async()=>{
 const order=await db.purchaseOrder.create({data:{
  customerId:state.customer.id,publicNumber:'BT-'+uuid().replaceAll('-').slice(0,24),
  clientRequestId:'PAY-'+uuid().replaceAll('-'),currency:'INR',status:'PLACED',
  addressSnapshot:{city:'Hyderabad'},subtotalPaise:15000n,totalPaise:15000n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:order.id,supplierId:state.supplier.id,
  subtotalPaise:15000n,totalPaise:15000n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:state.item.listingId,skuSnapshot:'PARTIAL',
  nameSnapshot:'Partial warehouse stock',unitCode:'BAG',
  packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(2),
  unitPrice:new Prisma.Decimal(75),taxRateBps:0,taxablePaise:15000n,
  taxPaise:0n,lineTotalPaise:15000n
 }});
 await db.inventoryBalance.update({where:{id:state.balance.id},
  data:{reservedQty:{increment:new Prisma.Decimal(1)}}});
 await db.inventoryReservation.create({data:{
  balanceId:state.balance.id,orderItemId:item.id,quantity:new Prisma.Decimal(1),
  state:'HELD',expiresAt:new Date(Date.now()+1200000)
 }});
 const result=await call('post','/api/v2/orders/'+order.id+'/payments','customer',
  {paymentMethod:'UPI'},'partial_'+uuid().replaceAll('-'));
 assert.equal(result.status,409,JSON.stringify(result.body));
 assert.equal(result.body.error.code,'STOCK_NOT_RESERVED');
 assert.equal(await db.paymentAttempt.count({where:{purchaseOrderId:order.id}}),0);
});
test('unconfirmed gateway creation uses receipt lookup, never blindly repeats POST',async()=>{
 const order=await db.purchaseOrder.create({data:{
  customerId:state.customer.id,publicNumber:'BT-'+uuid().replaceAll('-').slice(0,24),
  clientRequestId:'PAY-'+uuid().replaceAll('-'),currency:'INR',status:'PLACED',
  addressSnapshot:{city:'Hyderabad'},subtotalPaise:15000n,totalPaise:15000n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:order.id,supplierId:state.supplier.id,
  subtotalPaise:15000n,totalPaise:15000n
 }});
 await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:'CUSTOM',nameSnapshot:'Custom quote',
  unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal(1),
  quantity:new Prisma.Decimal(1),unitPrice:new Prisma.Decimal(150),
  taxRateBps:0,taxablePaise:15000n,taxPaise:0n,lineTotalPaise:15000n
 }});
 const originalCreate=gateway.createOrder;
 const idem='recover_'+uuid().replaceAll('-');
 let attempted=0;
 gateway.createOrder=async()=>{attempted++;throw new Error('network timeout');};
 const first=await call('post','/api/v2/orders/'+order.id+'/payments','customer',
  {paymentMethod:'UPI'},idem);
 assert.equal(first.status,503,JSON.stringify(first.body));
 assert.equal(first.body.error.code,'PAYMENT_INITIALIZATION_UNKNOWN');
 const attempt=await db.paymentAttempt.findFirstOrThrow({where:{purchaseOrderId:order.id}});
 assert.equal(attempt.status,'CREATED');
 const reference='order_'+uuid().replaceAll('-').slice(0,20);
 gateway.lookupOrderByReceipt=async receipt=>({
  id:reference,amount:15000n,currency:'INR',receipt
 });
 const retry=await call('post','/api/v2/orders/'+order.id+'/payments','customer',
  {paymentMethod:'UPI'},idem);
 assert.equal(retry.status,200,JSON.stringify(retry.body));
 assert.equal(retry.body.data.providerOrderId,reference);
 assert.equal(retry.body.data.status,'PENDING');
 assert.equal(attempted,1,'gateway create POST must not be retried');
 gateway.createOrder=originalCreate;
 delete gateway.lookupOrderByReceipt;
});
test('simultaneous delivery of one signed event ID is deduplicated',async()=>{
 const pay={id:'pay_'+uuid().replaceAll('-').slice(0,20),
  order_id:state.providerOrderId,amount:15000,currency:'INR',
  status:'captured',method:'upi'};
 const eventId='evt_'+uuid().replaceAll('-');
 const [a,b]=await Promise.all([
  signedEvent('payment.captured',pay,eventId),
  signedEvent('payment.captured',pay,eventId)
 ]);
 assert.equal(a.status,200,JSON.stringify(a.body));
 assert.equal(b.status,200,JSON.stringify(b.body));
 assert.equal(Number(a.body.duplicate)+Number(b.body.duplicate),1);
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:state.order.id}})).status,'CONFIRMED');
});

async function newPayableOrder(){
 const parent=await db.purchaseOrder.create({data:{
  customerId:state.customer.id,publicNumber:'BT-'+uuid().replaceAll('-').slice(0,24),
  clientRequestId:'PAY-'+uuid().replaceAll('-'),currency:'INR',status:'PLACED',
  addressSnapshot:{city:'Hyderabad'},subtotalPaise:7500n,totalPaise:7500n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:state.supplier.id,
  subtotalPaise:7500n,totalPaise:7500n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:state.item.listingId,
  skuSnapshot:'RETRY-'+uuid().slice(0,12),nameSnapshot:'Cement',
  unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal(1),
  quantity:new Prisma.Decimal(1),unitPrice:new Prisma.Decimal(75),
  taxRateBps:0,taxablePaise:7500n,lineTotalPaise:7500n
 }});
 await db.inventoryBalance.update({where:{id:state.balance.id},data:{
  reservedQty:{increment:new Prisma.Decimal(1)}
 }});
 const hold=await db.inventoryReservation.create({data:{
  balanceId:state.balance.id,orderItemId:item.id,
  quantity:new Prisma.Decimal(1),state:'HELD',
  expiresAt:new Date(Date.now()+1200000)
 }});
 return {parent,child,item,hold};
}
test('individual failed Razorpay try is not a terminal order failure; verified cancel permits COD',async()=>{
 const x=await newPayableOrder();
 const endpoint='/api/v2/orders/'+x.parent.id+'/payments';
 const pay=await call('post',endpoint,'customer',{paymentMethod:'UPI'},
  'retry_'+uuid().replaceAll('-'));
 assert.equal(pay.status,201,JSON.stringify(pay.body));
 const attemptId=pay.body.data.id;
 const failed=await signedEvent('payment.failed',{
  id:'pay_'+uuid().replaceAll('-').slice(0,20),
  order_id:pay.body.data.providerOrderId,amount:7500,
  currency:'INR',status:'failed',method:'upi'
 });
 assert.equal(failed.status,200,JSON.stringify(failed.body));
 assert.equal((await db.paymentAttempt.findUniqueOrThrow({where:{id:attemptId}})).status,'PENDING',
  'one failed UPI PIN is not proof that the Razorpay order has closed');
 state.providerInspection='ACTIVE_PAYMENT';
 const url=endpoint+'/'+attemptId+'/cancel';
 const blocked=await call('post',url,'customer',{});
 assert.equal(blocked.status,409,JSON.stringify(blocked.body));
 state.providerInspection='NO_ACTIVE_PAYMENT';
 assert.equal((await call('post',url,'outsider',{})).status,404);
 const stopped=await call('post',url,'customer',{});
 assert.equal(stopped.status,200,JSON.stringify(stopped.body));
 assert.equal(stopped.body.data.status,'CANCELLED');
 assert.equal(stopped.body.data.orderCancelled,false);
 assert.equal((await call('post',url,'customer',{})).body.data.replayed,true);
 const cod=await call('post','/api/v2/orders/'+x.parent.id+'/cod','customer',{},
  'cod_'+uuid().replaceAll('-'));
 assert.equal(cod.status,201,JSON.stringify(cod.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:x.parent.id}})).status,'CONFIRMED');
 assert.equal((await db.inventoryReservation.findUniqueOrThrow({where:{id:x.hold.id}})).state,'COMMITTED');
 state.providerInspection=undefined;
});
test('expired payment session is reclaimed after provider verification; a late capture goes to review',async()=>{
 const x=await newPayableOrder();
 const endpoint='/api/v2/orders/'+x.parent.id+'/payments';
 const pay=await call('post',endpoint,'customer',{paymentMethod:'CARD'},
  'recover_'+uuid().replaceAll('-'));
 assert.equal(pay.status,201,JSON.stringify(pay.body));
 await db.inventoryReservation.update({where:{id:x.hold.id},
  data:{expiresAt:new Date(Date.now()-30000)}});
 state.providerInspection='NO_ACTIVE_PAYMENT';
 const recovered=await recoverExpiredPaymentSessions(db,gateway,25);
 assert(recovered.cancelled>=1,JSON.stringify(recovered));
 assert.equal((await db.inventoryReservation.findUniqueOrThrow({where:{id:x.hold.id}})).state,'EXPIRED');
 assert.equal((await db.paymentAttempt.findUniqueOrThrow({where:{id:pay.body.data.id}})).status,'CANCELLED');
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:x.parent.id}})).status,'CANCELLED');
 const late=await signedEvent('payment.captured',{
  id:'pay_'+uuid().replaceAll('-').slice(0,20),
  order_id:pay.body.data.providerOrderId,amount:7500,currency:'INR',
  status:'captured',method:'card'
 });
 assert.equal(late.status,200,JSON.stringify(late.body));
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:x.parent.id}})).status,'CANCELLED');
 assert.equal(await db.auditEvent.count({where:{
  entityId:x.parent.id,action:'PAYMENT_CAPTURED_REQUIRES_REVIEW'}}),1);
 state.providerInspection=undefined;
});
