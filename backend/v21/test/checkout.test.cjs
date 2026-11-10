'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {recoverExpiredOrders}=require('../dist/order-service.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),subject=()=> 'user_'+id().replaceAll('-',''),key=()=> 'checkout_'+id().replaceAll('-','');
const tokens={},state={};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,limiter:new InMemoryTestLimiter(),
 log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Unauthorized.');
  return {subject:tokens[token],sessionId:'sess_test12345678'};
 }}});
const http=request(app);
function send(method,url,token,body,k){
 let req=http[method](url);
 if(token)req=req.set('Authorization','Bearer '+token);
 if(k)req=req.set('Idempotency-Key',k);
 return body===undefined?req:req.send(body);
}
const qty=(quantity,expectedVersion)=>({quantity,expectedVersion});
const createQuote=async(token,version,promo=null,addressId=state.address.id)=>{
 const data={addressId,expectedCartVersion:version,...(promo?{promotionCode:promo}:{})};
 return send('post','/api/v2/checkouts',token,data,key());
};
const place=async(token,quoteId,k=key())=>send('post','/api/v2/checkouts/'+quoteId+'/place',
 token,{clientRequestId:key()},k);
const cart=async(token)=> (await send('get','/api/v2/cart',token)).body.data;
const add=async(token,listingId,value)=>
 send('put','/api/v2/cart/lines/'+listingId,token,qty(value,(await cart(token)).version));

test('fixture: two suppliers, delivery zones, customer address, priced listings and warehouse stock',async()=>{
 for(const name of ['customer','otherCustomer']){
  const user=await db.user.create({data:{clerkUserId:subject(),displayName:'Checkout '+name}});
  state[name]=user;tokens[name]=user.clerkUserId;
 }
 const supplierA=await db.supplier.create({data:{
  slug:'cart-a-'+id(),legalName:'Build Materials A',displayName:'Supplier A',approval:'APPROVED',
  gstin:'36ABCDE'+String(Math.floor(1000+Math.random()*9000))+'F1Z'+String(Math.floor(Math.random()*10)),gstRegistration:'REGULAR',verifiedAt:new Date()
 }});
 const supplierB=await db.supplier.create({data:{
  slug:'cart-b-'+id(),legalName:'Build Materials B',displayName:'Supplier B',approval:'APPROVED'
 }});
 state.supplierA=supplierA;state.supplierB=supplierB;
 const category=await db.category.create({data:{slug:'cart-'+id(),name:'Cart Test Materials',active:true}});
 const city=await db.city.create({data:{code:'CT'+id().slice(0,14).toUpperCase(),name:'Hyderabad Checkout',stateCode:'TG',active:true}});
 const area=await db.serviceArea.create({data:{cityId:city.id,name:'Main delivery sector',
  postalCodes:['500001'],active:true}});
 for(const [supplier,base] of [[supplierA,1000n],[supplierB,2500n]]){
  await db.supplierServiceArea.create({data:{
   supplierId:supplier.id,areaId:area.id,active:true,minimumPaise:1000n
  }});
  await db.supplierDeliveryRate.create({data:{
   supplierId:supplier.id,areaId:area.id,active:true,
   baseFeePaise:base,handlingFeePaise:0n,effectiveFrom:new Date(Date.now()-60000)
  }});
 }
 state.address=await db.address.create({data:{
  userId:state.customer.id,cityId:city.id,label:'Construction site',
  recipientName:'Customer',phoneE164:'+919876543210',line1:'Plot 1',
  locality:'Hyderabad',postalCode:'500001'
 }});
 state.otherAddress=await db.address.create({data:{
  userId:state.otherCustomer.id,cityId:city.id,label:'Other site',
  recipientName:'Other Customer',phoneE164:'+919876543211',line1:'Plot 2',
  locality:'Hyderabad',postalCode:'500001'
 }});
 const productA=await db.product.create({data:{
  code:'CA'+id().slice(0,14).toUpperCase(),categoryId:category.id,name:'Cement Bag',active:true,hsnCode:'2523'
 }});
 const productB=await db.product.create({data:{
  code:'CB'+id().slice(0,14).toUpperCase(),categoryId:category.id,name:'Coarse Sand Bag',active:true,hsnCode:'2505'
 }});
 state.listingA=await db.supplierListing.create({data:{
  supplierId:supplierA.id,productId:productA.id,
  sku:'CA'+id().slice(0,14).toUpperCase(),unitCode:'BAG',
  status:'APPROVED',active:true,publishedAt:new Date(),
  unitPrice:new Prisma.Decimal('118.0000'),taxRateBps:1800,taxInclusive:true
 }});
 state.listingB=await db.supplierListing.create({data:{
  supplierId:supplierB.id,productId:productB.id,
  sku:'CB'+id().slice(0,14).toUpperCase(),unitCode:'BAG',
  status:'APPROVED',active:true,publishedAt:new Date(),
  unitPrice:new Prisma.Decimal('50.0000'),taxRateBps:0,taxInclusive:false
 }});
 for(const [supplier,listing] of [[supplierA,state.listingA],[supplierB,state.listingB]]){
  const warehouse=await db.warehouse.create({data:{
   supplierId:supplier.id,code:'MAIN',name:'Main warehouse',active:true
  }});
  await db.inventoryBalance.create({data:{
   listingId:listing.id,warehouseId:warehouse.id,onHandQty:new Prisma.Decimal('10.000')
  }});
 }
 assert.equal((await send('get','/api/v2/cart',null)).status,401);
});

test('cart versions prevent overwrites and reject foreign/unpublished listings and floats',async()=>{
 const first=await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('2.000',0));
 assert.equal(first.status,200,JSON.stringify(first.body));
 assert.equal(first.body.data.version,1);
 const second=await send('put','/api/v2/cart/lines/'+state.listingB.id,'customer',qty('3.000',1));
 assert.equal(second.status,200,JSON.stringify(second.body));
 assert.equal(second.body.data.version,2);
 assert.equal(second.body.data.items.length,2);
 assert.equal((await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('3.000',1))).status,409);
 assert.equal((await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty(2,2))).status,400);
 assert.equal((await cart('otherCustomer')).items.length,0);
 assert.equal((await send('post','/api/v2/cart/clear','otherCustomer',{expectedVersion:0})).status,200);
});

test('server quote calculates tax-inclusive price and two independent freight fees',async()=>{
 assert.equal((await send('post','/api/v2/checkouts','customer',{
  addressId:state.otherAddress.id,expectedCartVersion:2
 },key())).status,404);
 assert.equal((await send('post','/api/v2/checkouts','customer',{
  addressId:state.address.id,expectedCartVersion:1
 },key())).status,409);
 const q=await createQuote('customer',2);
 assert.equal(q.status,201,JSON.stringify(q.body));
 const p=q.body.data;
 state.firstQuoteId=p.id;
 assert.equal(p.subtotalPaise,'35000'); // (2 × 118 inclusive of 18%) = 200, plus 150
 assert.equal(p.taxPaise,'3600');
 assert.equal(p.deliveryPaise,'3500');
 assert.equal(p.discountPaise,'0');
 assert.equal(p.totalPaise,'42100');
 assert.equal(p.breakdown.suppliers.length,2);
 assert.equal(p.breakdown.items.length,2);
 assert.equal((await send('get','/api/v2/checkouts/'+p.id,'otherCustomer')).status,404);
 assert.equal((await send('get','/api/v2/checkouts/'+p.id,'customer')).status,200);
 assert.equal((await send('post','/api/v2/checkouts/'+p.id+'/place','customer',{
  clientRequestId:'with-no-key-0001'
 })).status,428);
});

test('a pricing or cart change invalidates old checkout quotes before any order is created',async()=>{
 await db.supplierListing.update({where:{id:state.listingA.id},data:{
  unitPrice:new Prisma.Decimal('119.0000'),version:{increment:1}
 }});
 const attempted=await place('customer',state.firstQuoteId);
 assert.equal(attempted.status,409,JSON.stringify(attempted.body));
 assert.equal(attempted.body.error.code,'CHECKOUT_CHANGED');
 assert.equal(await db.purchaseOrder.count({where:{customerId:state.customer.id}}),0);
 await db.supplierListing.update({where:{id:state.listingA.id},data:{
  unitPrice:new Prisma.Decimal('118.0000'),version:{increment:1}
 }});
 const stale=await createQuote('customer',2);
 assert.equal(stale.status,201);
 const extra=await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('3.000',2));
 assert.equal(extra.status,200);
 assert.equal((await place('customer',stale.body.data.id)).status,409);
 const restored=await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('2.000',3));
 assert.equal(restored.status,200);
});

test('multi-supplier order placement is atomic, repeat-safe and never assumes payment succeeded',async()=>{
 const quote=await createQuote('customer',4);
 assert.equal(quote.status,201,JSON.stringify(quote.body));
 const command={clientRequestId:'client_'+id().replaceAll('-','')};
 const idem=key();
 const placed=await send('post','/api/v2/checkouts/'+quote.body.data.id+'/place','customer',command,idem);
 assert.equal(placed.status,201,JSON.stringify(placed.body));
 const order=placed.body.data;
 assert.equal(order.suppliers.length,2);
 assert.equal(order.status,'PLACED');
 assert.equal(order.paymentStatus,'NOT_STARTED');
 assert.equal(order.totalPaise,'42100');
 assert(order.reservationExpiresAt);
 state.firstOrderId=order.id;
 const retry=await send('post','/api/v2/checkouts/'+quote.body.data.id+'/place','customer',command,idem);
 assert.equal(retry.status,200,JSON.stringify(retry.body));
 assert.equal(retry.body.replayed,true);
 assert.equal(retry.body.data.id,order.id);
 const duplicate=await send('post','/api/v2/checkouts/'+quote.body.data.id+'/place','customer',command,key());
 assert.equal(duplicate.status,409);
 assert.equal((await send('get','/api/v2/orders/'+order.id,'otherCustomer')).status,404);
 assert.equal((await send('get','/api/v2/orders','otherCustomer')).body.data.length,0);
 assert.equal((await send('get','/api/v2/orders','customer')).body.data.length,1);
 assert.equal((await cart('customer')).items.length,0);
 const holds=await db.inventoryReservation.findMany({where:{
  orderItem:{supplierOrder:{purchaseOrderId:order.id}}
 }});
 assert.equal(holds.length,2);
 assert(holds.every(x=>x.state==='HELD'));
 const firstBalance=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}});
 assert.equal(firstBalance.onHandQty.toString(),'10');
 assert.equal(firstBalance.reservedQty.toString(),'2');
 assert.equal(await db.paymentAttempt.count({where:{purchaseOrderId:order.id}}),0);
 const line=await db.supplierOrderItem.findFirstOrThrow({where:{listingId:state.listingA.id,
  supplierOrder:{purchaseOrderId:order.id}}});
 assert.equal(line.cgstPaise.toString(),'1800');
 assert.equal(line.sgstPaise.toString(),'1800');
 assert.equal(line.igstPaise.toString(),'0');
});

test('customer cancellation releases all supplier holds and cannot be repeated incorrectly',async()=>{
 assert.equal((await send('post','/api/v2/orders/'+state.firstOrderId+'/cancel','otherCustomer',{})).status,404);
 const c=await send('post','/api/v2/orders/'+state.firstOrderId+'/cancel','customer',{});
 assert.equal(c.status,200,JSON.stringify(c.body));
 assert.equal(c.body.data.state,'CANCELLED');
 assert.equal((await send('post','/api/v2/orders/'+state.firstOrderId+'/cancel','customer',{})).body.data.replayed,true);
 const holds=await db.inventoryReservation.findMany({where:{
  orderItem:{supplierOrder:{purchaseOrderId:state.firstOrderId}}
 }});
 assert(holds.every(h=>h.state==='RELEASED'));
 const balance=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}});
 assert.equal(balance.reservedQty.toString(),'0');
 assert.equal((await db.supplierOrder.count({where:{
  purchaseOrderId:state.firstOrderId,status:'CANCELLED'
 }})),2);
});

const promoWindow=()=>({
 startsAt:new Date(Date.now()-60000).toISOString().replace(/\.[0-9]{3}Z$/,'Z'),
 endsAt:new Date(Date.now()+4*86400000).toISOString().replace(/\.[0-9]{3}Z$/,'Z')
});
test('free-delivery coupon discounts freight, never alters taxable goods prices',async()=>{
 const current=await cart('customer');
 await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('2.000',current.version));
 await add('customer',state.listingB.id,'3.000');
 // Promotion creation is admin-only; use a server fixture here.
 const coupon=await db.promotion.create({data:{
  code:'SHIP'+id().slice(0,12).toUpperCase(),title:'Free construction freight',
  type:'FREE_DELIVERY',active:true,...promoWindow()
 }});
 const q=await createQuote('customer',(await cart('customer')).version,coupon.code);
 assert.equal(q.status,201,JSON.stringify(q.body));
 assert.equal(q.body.data.deliveryPaise,'0');
 assert.equal(q.body.data.discountPaise,'0');
 assert.equal(q.body.data.taxPaise,'3600');
 assert.equal(q.body.data.totalPaise,'38600');
 assert.equal(q.body.data.breakdown.promotionAmountPaise,'3500');
 const order=await place('customer',q.body.data.id);
 assert.equal(order.status,201,JSON.stringify(order.body));
 assert.equal(order.body.data.deliveryPaise,'0');
 assert.equal(order.body.data.discountPaise,'0');
 state.couponOrderId=order.body.data.id;
 const redemption=await db.promotionRedemption.findUniqueOrThrow({where:{orderId:state.couponOrderId}});
 assert.equal(redemption.amountPaise.toString(),'3500');
 assert.equal((await send('post','/api/v2/orders/'+state.couponOrderId+'/cancel','customer',{})).status,200);
 assert.equal(await db.promotionRedemption.count({where:{orderId:state.couponOrderId}}),0);
});

test('all-or-nothing order fails if one supplier loses stock after quote',async()=>{
 const old=(await cart('customer')).version;
 await send('put','/api/v2/cart/lines/'+state.listingA.id,'customer',qty('2.000',old));
 await add('customer',state.listingB.id,'3.000');
 const q=await createQuote('customer',(await cart('customer')).version);
 assert.equal(q.status,201);
 const before=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingB.id}});
 await db.inventoryBalance.update({where:{id:before.id},data:{
  onHandQty:new Prisma.Decimal('1.000'),version:{increment:1}
 }});
 const priorOrders=await db.purchaseOrder.count({where:{customerId:state.customer.id}});
 const denied=await place('customer',q.body.data.id);
 assert.equal(denied.status,409);
 assert.equal(denied.body.error.code,'INSUFFICIENT_AVAILABLE_STOCK');
 assert.equal(await db.purchaseOrder.count({where:{customerId:state.customer.id}}),priorOrders);
 assert.equal((await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}}))
  .reservedQty.toString(),'0');
 await db.inventoryBalance.update({where:{id:before.id},data:{
  onHandQty:new Prisma.Decimal('10.000'),version:{increment:1}
 }});
});

test('concurrent customers cannot oversell one listing even with independently valid quotes',async()=>{
 const existing=(await cart('customer'));
 await send('post','/api/v2/cart/clear','customer',{expectedVersion:existing.version});
 await add('customer',state.listingA.id,'8.000');
 await add('otherCustomer',state.listingA.id,'8.000');
 const a=await createQuote('customer',(await cart('customer')).version);
 const b=await createQuote('otherCustomer',(await cart('otherCustomer')).version,null,state.otherAddress.id);
 assert.equal(a.status,201,JSON.stringify(a.body));
 assert.equal(b.status,201,JSON.stringify(b.body));
 const [one,two]=await Promise.allSettled([
  place('customer',a.body.data.id),
  place('otherCustomer',b.body.data.id)
 ]);
 const results=[one,two].map(x=>x.status==='fulfilled'?x.value:null);
 assert.equal(results.filter(x=>x&&x.status===201).length,1,JSON.stringify(results.map(x=>x?.body?.error||x?.status)));
 assert.equal(results.filter(x=>x&&x.status!==201).length,1);
 const balance=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}});
 assert(balance.reservedQty.lte(balance.onHandQty));
 assert.equal(balance.reservedQty.toString(),'8');
 state.winningOrderId=results.find(x=>x?.status===201).body.data.id;
});

test('expired unpaid holds are recovered without a separate background service',async()=>{
 const reservations=await db.inventoryReservation.findMany({where:{
  orderItem:{supplierOrder:{purchaseOrderId:state.winningOrderId}},state:'HELD'
 }});
 assert(reservations.length>0);
 await db.inventoryReservation.updateMany({where:{id:{in:reservations.map(x=>x.id)}},
  data:{expiresAt:new Date(Date.now()-60000)}
 });
 const before=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}});
 assert.equal(before.reservedQty.toString(),'8');
 const recovered=await recoverExpiredOrders(db,10);
 assert(recovered.reclaimed>=1);
 const after=await db.inventoryBalance.findFirstOrThrow({where:{listingId:state.listingA.id}});
 assert.equal(after.reservedQty.toString(),'0');
 const order=await db.purchaseOrder.findUniqueOrThrow({where:{id:state.winningOrderId}});
 assert.equal(order.status,'CANCELLED');
 assert.equal(await db.purchaseOrder.count({where:{status:'PLACED',
  supplierOrders:{some:{items:{some:{reservations:{some:{state:'EXPIRED'}}}}}}
 }}),0);
});

test('opposite cart line order uses deterministic stock locks, no PostgreSQL deadlock',async()=>{
 const reset=async who=>{
  const value=await cart(who);
  const response=await send('post','/api/v2/cart/clear',who,{expectedVersion:value.version});
  assert.equal(response.status,200,JSON.stringify(response.body));
 };
 await reset('customer');await reset('otherCustomer');
 // Two buyers select the same stock in opposite visual/cart order.
 assert.equal((await add('customer',state.listingA.id,'2.000')).status,200);
 assert.equal((await add('customer',state.listingB.id,'2.000')).status,200);
 assert.equal((await add('otherCustomer',state.listingB.id,'2.000')).status,200);
 assert.equal((await add('otherCustomer',state.listingA.id,'2.000')).status,200);
 const a=await createQuote('customer',(await cart('customer')).version);
 const b=await createQuote('otherCustomer',(await cart('otherCustomer')).version,
  null,state.otherAddress.id);
 assert.equal(a.status,201,JSON.stringify(a.body));
 assert.equal(b.status,201,JSON.stringify(b.body));
 const attempts=await Promise.allSettled([
  place('customer',a.body.data.id),
  place('otherCustomer',b.body.data.id)
 ]);
 assert(attempts.every(result=>result.status==='fulfilled'),JSON.stringify(attempts));
 for(const result of attempts){
  assert.equal(result.value.status,201,JSON.stringify(result.value.body));
  assert.equal(result.value.body.data.suppliers.length,2);
 }
 const balances=await db.inventoryBalance.findMany({where:{
  listingId:{in:[state.listingA.id,state.listingB.id]}
 }});
 assert.equal(balances.length,2);
 for(const balance of balances){
  assert.equal(balance.reservedQty.toString(),'4');
  assert(balance.reservedQty.lte(balance.onHandQty));
 }
});
