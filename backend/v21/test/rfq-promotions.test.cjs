'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {serializable}=require('../dist/transaction.js');
const {recordOrderPromotion}=require('../dist/promotion-service.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),sub=()=> 'user_'+id().replaceAll('-','');
const tokens={};const store={};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session.');
  return {subject:tokens[token],sessionId:'sess_test12345678'};
 }}});
const api=request(app);
function send(method,url,token,body,key){
 let req=api[method](url);
 if(token)req=req.set('Authorization','Bearer '+token);
 if(key)req=req.set('Idempotency-Key',key);
 return body===undefined?req:req.send(body);
}
const hdr=()=> 'test_'+id().replaceAll('-','');
const rfqURL=()=>'/api/v2/rfqs/'+store.rfqId;
const quotePayload=(price='125.5000')=>({deliveryPaise:'1000',
 deliveryTerms:'Supplier delivers materials to requested site',
 validUntil:new Date(Date.now()+4*86400000).toISOString().replace(/\.\d{3}Z$/,'Z'),
 lines:[{rfqItemId:store.rfqItemId,listingId:store.listing.id,
  quantity:'2.000',unitCode:'BAG',unitPrice:price,taxRateBps:1800}]
});
test('fixture: normal customer, separate customer, two approved suppliers and operations admin',async()=>{
 const users={};
 for(const key of ['customer','otherCustomer','supplier','secondSupplier','viewer','admin']){
  users[key]=await db.user.create({data:{clerkUserId:sub(),displayName:'RFQ '+key}});
  tokens[key]=users[key].clerkUserId;
 }
 const [first,second]=await Promise.all([
  db.supplier.create({data:{slug:'rfq-'+id(),legalName:'Quotes First Ltd',displayName:'Quotes First',approval:'APPROVED'}}),
  db.supplier.create({data:{slug:'rfq-'+id(),legalName:'Quotes Second Ltd',displayName:'Quotes Second',approval:'APPROVED'}}),
 ]);
 await db.supplierMember.createMany({data:[
  {userId:users.supplier.id,supplierId:first.id,role:'CATALOG',active:true},
  {userId:users.secondSupplier.id,supplierId:second.id,role:'MANAGER',active:true},
  {userId:users.viewer.id,supplierId:first.id,role:'VIEWER',active:true},
 ]});
 await db.adminMembership.create({data:{userId:users.admin.id,role:'OPERATIONS',active:true}});
 const category=await db.category.create({data:{slug:'rfq-'+id(),name:'RFQ Test Materials',active:true}});
 const product=await db.product.create({data:{
  categoryId:category.id,code:'RFQ-'+id().replaceAll('-').slice(0,15).toUpperCase(),
  name:'RFQ Test Cement',active:true
 }});
 const listing=await db.supplierListing.create({data:{
  supplierId:first.id,productId:product.id,sku:'QT-'+id().replaceAll('-').slice(0,14).toUpperCase(),
  unitCode:'BAG',status:'APPROVED',active:true,publishedAt:new Date(),
  unitPrice:new Prisma.Decimal('125.5000'),taxRateBps:1800
 }});
 Object.assign(store,users,{first,second,product,listing});
 assert.equal((await send('get','/api/v2/rfqs',null)).status,401);
});
test('RFQ creation validates inputs, idempotency and user ownership',async()=>{
 const payload={
  siteSnapshot:{city:'Hyderabad',postalCode:'500001',siteNotes:'Truck access before 6pm'},
  responseDueAt:new Date(Date.now()+3*86400000).toISOString().replace(/\.\d{3}Z$/,'Z'),
  notes:'Provide branded cement',
  items:[{productId:store.product.id,description:'OPC Cement 53 Grade',
   quantity:'2.000',unitCode:'BAG',specification:{grade:'53'}}]
 };
 assert.equal((await send('post','/api/v2/rfqs','customer',payload)).status,428);
 assert.equal((await send('post','/api/v2/rfqs','customer',{
  ...payload,items:[{...payload.items[0],quantity:2}]
 },hdr())).status,400);
 const key=hdr();
 const first=await send('post','/api/v2/rfqs','customer',payload,key);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.status,'DRAFT');
 assert.equal(first.body.data.items.length,1);
 store.rfqId=first.body.data.id;store.rfqItemId=first.body.data.items[0].id;
 const replay=await send('post','/api/v2/rfqs','customer',payload,key);
 assert.equal(replay.status,200);assert.equal(replay.body.replayed,true);
 assert.equal(replay.body.data.id,store.rfqId);
 const conflict=await send('post','/api/v2/rfqs','customer',{...payload,notes:'different'},key);
 assert.equal(conflict.status,409);
 assert.equal((await send('get',rfqURL(),'otherCustomer')).status,404);
 assert.equal((await send('get',rfqURL(),'customer')).status,200);
 assert.equal((await send('get','/api/v2/rfqs','otherCustomer')).body.data.length,0);
});
test('only owner opens RFQ and invites approved suppliers; invitations are repeat-safe',async()=>{
 assert.equal((await send('post',rfqURL()+'/open','otherCustomer',{})).status,404);
 assert.equal((await send('post',rfqURL()+'/open','customer',{})).status,200);
 assert.equal((await send('post',rfqURL()+'/open','customer',{})).status,409);
 const path=rfqURL()+'/invitations/'+store.first.id;
 assert.equal((await send('post',path,'otherCustomer',{})).status,404);
 const accepted=await send('post',path,'customer',{});
 assert.equal(accepted.status,200,JSON.stringify(accepted.body));
 assert.equal(accepted.body.data.alreadyInvited,false);
 assert.equal((await send('post',path,'customer',{})).body.data.alreadyInvited,true);
 assert.equal((await send('post',rfqURL()+'/invitations/'+store.second.id,'customer',{})).status,200);
 const uninvited=await db.supplier.create({data:{
  slug:'rfq-'+id(),displayName:'Unapproved Supplier',legalName:'Unapproved Supplier',approval:'PENDING'
 }});
 assert.equal((await send('post',rfqURL()+'/invitations/'+uninvited.id,'customer',{})).status,422);
 assert.equal((await send('get','/api/v2/suppliers/'+store.first.id+'/rfqs','viewer')).status,403);
 assert.equal((await send('get','/api/v2/suppliers/'+store.first.id+'/rfqs','secondSupplier')).status,404);
 const inbox=await send('get','/api/v2/suppliers/'+store.first.id+'/rfqs','supplier');
 assert.equal(inbox.status,200);
 assert(inbox.body.data.some(r=>r.id===store.rfqId));
});
test('supplier quote is exact, complete and cannot use another supplier listing',async()=>{
 const path='/api/v2/suppliers/'+store.first.id+'/rfqs/'+store.rfqId+'/quotes';
 assert.equal((await send('post',path,'otherCustomer',quotePayload(),hdr())).status,404);
 assert.equal((await send('post',path,'viewer',quotePayload(),hdr())).status,403);
 assert.equal((await send('post',path,'secondSupplier',quotePayload(),hdr())).status,404);
 assert.equal((await send('post',path,'supplier',{
  ...quotePayload(),lines:[{...quotePayload().lines[0],quantity:'1.000'}]
 },hdr())).status,422);
 assert.equal((await send('post',path,'supplier',{
  ...quotePayload(),lines:[{...quotePayload().lines[0],unitPrice:125.5}]
 },hdr())).status,400);
 const original=quotePayload();
 assert.equal((await send('post',path,'supplier',original)).status,428);
 const firstKey=hdr();
 const first=await send('post',path,'supplier',original,firstKey);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.subtotalPaise,'25100');
 assert.equal(first.body.data.taxPaise,'4518');
 assert.equal(first.body.data.deliveryPaise,'1000');
 assert.equal(first.body.data.totalPaise,'30618');
 assert.equal(first.body.data.lines[0].lineTotalPaise,'29618');
 assert.equal(first.body.data.version,1);
 store.quoteId=first.body.data.id;
 const replay=await send('post',path,'supplier',original,firstKey);
 assert.equal(replay.status,200);
 assert.equal(replay.body.replayed,true);
 assert.equal(replay.body.data.id,store.quoteId);
 assert.equal(await db.supplierQuote.count({where:{rfqId:store.rfqId,supplierId:store.first.id}}),1);
 const reused=await send('post',path,'supplier',quotePayload('135.0000'),firstKey);
 assert.equal(reused.status,409);
 assert.equal(reused.body.error.code,'IDEMPOTENCY_KEY_REUSED');
 const revised=await send('post',path,'supplier',quotePayload('120.0000'),hdr());
 assert.equal(revised.status,201,JSON.stringify(revised.body));
 assert.equal(revised.body.data.version,2);
 assert.equal(revised.body.data.status,'SUBMITTED');
 store.revisedId=revised.body.data.id;
 const historical=await db.supplierQuote.findUniqueOrThrow({where:{id:store.quoteId}});
 assert.equal(historical.status,'REVISED');
 const own=await send('get',path,'supplier');
 assert.equal(own.status,200);assert.equal(own.body.data.length,2);
 assert.equal((await send('get',rfqURL()+'/quotes','otherCustomer')).status,404);
 const customer=await send('get',rfqURL()+'/quotes','customer');
 assert(customer.body.data.some(x=>x.id===store.revisedId));
});
test('RFQ can award exactly one current quote and prevent later submissions',async()=>{
 const path='/api/v2/suppliers/'+store.second.id+'/rfqs/'+store.rfqId+'/quotes';
 const quote=await send('post',path,'secondSupplier',{
  deliveryPaise:'1500',
  lines:[{rfqItemId:store.rfqItemId,quantity:'2.000',unitCode:'BAG',unitPrice:'130.0000',taxRateBps:0}]
 },hdr());
 assert.equal(quote.status,201,JSON.stringify(quote.body));
 assert.equal((await send('post',rfqURL()+'/quotes/'+store.revisedId+'/award','otherCustomer',{})).status,404);
 const awarded=await send('post',rfqURL()+'/quotes/'+store.revisedId+'/award','customer',{});
 assert.equal(awarded.status,200,JSON.stringify(awarded.body));
 assert.equal(awarded.body.data.status,'AWARDED');
 assert.match(awarded.body.data.message,/checkout/i);
 const stored=await db.rfq.findUniqueOrThrow({where:{id:store.rfqId}});
 assert.equal(stored.status,'AWARDED');
 assert.equal((await db.supplierQuote.findUniqueOrThrow({where:{id:store.revisedId}})).status,'ACCEPTED');
 assert.equal((await db.supplierQuote.findUniqueOrThrow({where:{id:quote.body.data.id}})).status,'REJECTED');
 assert.equal((await send('post',rfqURL()+'/quotes/'+quote.body.data.id+'/award','customer',{})).status,409);
 assert.equal((await send('post',path,'secondSupplier',{
  lines:[{rfqItemId:store.rfqItemId,quantity:'2.000',unitCode:'BAG',unitPrice:'120.0000',taxRateBps:0}]
 },hdr())).status,409);
 assert.equal(await db.supplierOrder.count({where:{sourceQuoteId:store.revisedId}}),0);
});

test('accepted listing-backed RFQ converts its negotiated price into one unpaid order',async()=>{
 const city=await db.city.create({data:{code:'RFQ'+id().slice(0,12).toUpperCase(),
  name:'Hyderabad',stateCode:'TG',active:true}});
 const address=await db.address.create({data:{
  userId:store.customer.id,cityId:city.id,label:'RFQ site',
  recipientName:'RFQ Buyer',phoneE164:'+919876543210',line1:'Site 1',
  locality:'Hyderabad',postalCode:'500001'
 }});
 store.rfqAddress=address;
 const warehouse=await db.warehouse.create({data:{
  supplierId:store.first.id,code:'RFQ'+id().slice(0,10).toUpperCase(),
  name:'RFQ stock',active:true
 }});
 await db.inventoryBalance.create({data:{
  listingId:store.listing.id,warehouseId:warehouse.id,
  onHandQty:new Prisma.Decimal('10.000')
 }});
 await db.supplier.update({where:{id:store.first.id},data:{
  gstin:'36BCDEF'+String(Math.floor(1000+Math.random()*9000))+'G1Z'+String(Math.floor(Math.random()*10)),gstRegistration:'REGULAR',verifiedAt:new Date()
 }});
 const path=rfqURL()+'/quotes/'+store.revisedId+'/order';
 const body={clientRequestId:'rfqorder_'+id(),addressId:address.id};
 assert.equal((await send('post',path,'customer',body)).status,428);
 assert.equal((await send('post',path,'otherCustomer',body,hdr())).status,404);
 const k=hdr();
 const order=await send('post',path,'customer',body,k);
 assert.equal(order.status,201,JSON.stringify(order.body));
 assert.equal(order.body.data.suppliers.length,1);
 assert.equal(order.body.data.suppliers[0].sourceQuoteId,store.revisedId);
 assert.equal(order.body.data.totalPaise,'29320');
 assert.equal(order.body.data.paymentStatus,'NOT_STARTED');
 store.rfqOrderId=order.body.data.id;
 const line=await db.supplierOrderItem.findFirstOrThrow({where:{
  supplierOrder:{purchaseOrderId:store.rfqOrderId}
 }});
 assert.equal(line.unitPrice.toString(),'120');
 assert.equal(line.quantity.toString(),'2');
 assert.equal(line.cgstPaise.toString(),'2160');
 assert.equal(line.sgstPaise.toString(),'2160');
 const holds=await db.inventoryReservation.findMany({where:{orderItemId:line.id}});
 assert.equal(holds.length,1);assert.equal(holds[0].state,'HELD');
 const replay=await send('post',path,'customer',body,k);
 assert.equal(replay.status,200);
 assert.equal(replay.body.replayed,true);
 assert.equal(replay.body.data.id,store.rfqOrderId);
 const duplicate=await send('post',path,'customer',{...body,clientRequestId:'another_'+id()},hdr());
 assert.equal(duplicate.status,409);
 assert.equal(duplicate.body.error.code,'QUOTE_ALREADY_ORDERED');
 assert.equal((await send('post','/api/v2/orders/'+store.rfqOrderId+'/cancel','customer',{})).status,200);
 assert.equal((await db.inventoryReservation.findUniqueOrThrow({where:{id:holds[0].id}})).state,'RELEASED');
});
test('accepted bespoke RFQ is provisional and never invents warehouse stock',async()=>{
 const created=await send('post','/api/v2/rfqs','customer',{
  siteSnapshot:{city:'Hyderabad',postalCode:'500001'},
  items:[{description:'Custom graded aggregate',quantity:'1.000',unitCode:'BAG'}]
 },hdr());
 assert.equal(created.status,201);
 const rfqId=created.body.data.id,rfqItemId=created.body.data.items[0].id;
 assert.equal((await send('post','/api/v2/rfqs/'+rfqId+'/open','customer',{})).status,200);
 assert.equal((await send('post','/api/v2/rfqs/'+rfqId+'/invitations/'+store.second.id,'customer',{})).status,200);
 const submitted=await send('post','/api/v2/suppliers/'+store.second.id+'/rfqs/'+rfqId+'/quotes',
  'secondSupplier',{deliveryPaise:'500',
   lines:[{rfqItemId,quantity:'1.000',unitCode:'BAG',unitPrice:'99.0000',taxRateBps:0}]},hdr());
 assert.equal(submitted.status,201,JSON.stringify(submitted.body));
 assert.equal((await send('post','/api/v2/rfqs/'+rfqId+'/quotes/'+submitted.body.data.id+'/award','customer',{})).status,200);
 const order=await send('post','/api/v2/rfqs/'+rfqId+'/quotes/'+submitted.body.data.id+'/order',
  'customer',{clientRequestId:'bespoke_'+id(),addressId:store.rfqAddress.id},hdr());
 assert.equal(order.status,201,JSON.stringify(order.body));
 assert.equal(order.body.data.totalPaise,'10400');
 assert.equal(order.body.data.reservationExpiresAt,null);
 const item=await db.supplierOrderItem.findFirstOrThrow({where:{
  supplierOrder:{purchaseOrderId:order.body.data.id}
 }});
 assert.equal(item.listingId,null);
 assert.equal(await db.inventoryReservation.count({where:{orderItemId:item.id}}),0);
 assert.equal((await send('post','/api/v2/orders/'+order.body.data.id+'/cancel','customer',{})).status,200);
});

const activeWindow=()=>({
 startsAt:new Date(Date.now()-60000).toISOString().replace(/\.\d{3}Z$/,'Z'),
 endsAt:new Date(Date.now()+5*86400000).toISOString().replace(/\.\d{3}Z$/,'Z')
});
const promoPayload=(code,type,extras)=>({code,title:'CI discount',type,...activeWindow(),...extras});
test('admin-only promotions validate types, windows and immutable amounts',async()=>{
 const base='/api/v2/admin/promotions';
 assert.equal((await send('post',base,'customer',promoPayload('RFQNOPE123','PERCENTAGE',{percentageBps:1000}))).status,403);
 assert.equal((await send('post',base,'admin',promoPayload('INVALID123','PERCENTAGE',{amountPaise:'100'}))).status,400);
 assert.equal((await send('post',base,'admin',promoPayload('INVALID234','FREE_DELIVERY',{amountPaise:'100'}))).status,400);
 const created=await send('post',base,'admin',promoPayload('BUILD'+id().slice(0,12).toUpperCase(),
  'PERCENTAGE',{percentageBps:1000,capPaise:'5000',minCartPaise:'10000',perUserLimit:1,globalLimit:1}));
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.active,false);
 store.promo=created.body.data;
 const enabled=await send('patch',base+'/'+store.promo.id,'admin',{active:true});
 assert.equal(enabled.status,200);
 assert.equal(enabled.body.data.active,true);
 assert.equal((await send('get',base,'admin')).status,200);
 assert.equal((await send('get',base,'customer')).status,403);
 assert.equal((await send('patch',base+'/'+store.promo.id,'customer',{active:false})).status,403);
});
const makeOrder=async(customerId,discountPaise,subtotalPaise=100000n,deliveryPaise=12000n)=>{
 const taxPaise=0n,totalPaise=subtotalPaise+taxPaise+deliveryPaise-discountPaise;
 return db.purchaseOrder.create({data:{
  customerId,publicNumber:'P-'+id().replaceAll('-').slice(0,32),
  clientRequestId:'promo-'+id(),addressSnapshot:{postalCode:'500001'},
  subtotalPaise,taxPaise,discountPaise,deliveryPaise,totalPaise
 }});
};
test('promotion limits are checked atomically from persisted order totals, not request subtotals',async()=>{
 const first=await makeOrder(store.customer.id,5000n);
 const accepted=await serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.customer.id,orderId:first.id
 }));
 assert.deepEqual(accepted,{amountPaise:'5000',replayed:false});
 const retry=await serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.customer.id,orderId:first.id
 }));
 assert.equal(retry.replayed,true);
 const historicalRetry=await serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.customer.id,orderId:first.id,
  now:new Date(Date.now()+12*86400000)
 }));
 assert.equal(historicalRetry.replayed,true);
 const other=await makeOrder(store.otherCustomer.id,5000n);
 await assert.rejects(serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.otherCustomer.id,orderId:other.id
 })),e=>e.code==='PROMOTION_LIMIT_REACHED');
 assert.equal(await db.promotionRedemption.count({where:{promotionId:store.promo.id}}),1);
 const wrong=await makeOrder(store.otherCustomer.id,50n);
 await assert.rejects(serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.otherCustomer.id,orderId:wrong.id
 })),e=>e.code==='PROMOTION_LIMIT_REACHED');
 const foreign=await makeOrder(store.customer.id,5000n);
 await assert.rejects(serializable(db,tx=>recordOrderPromotion(tx,{
  code:store.promo.code,customerId:store.otherCustomer.id,orderId:foreign.id
 })));
});
test('fixed and free delivery promotion calculations are precise and never client-controlled',async()=>{
 const endpoint='/api/v2/admin/promotions';
 const fixed=await send('post',endpoint,'admin',
  promoPayload('FIX'+id().slice(0,10).toUpperCase(),'FIXED_PAISE',{amountPaise:'1500',minCartPaise:'1000'}));
 assert.equal(fixed.status,201);
 await send('patch',endpoint+'/'+fixed.body.data.id,'admin',{active:true});
 const fixedOrder=await makeOrder(store.customer.id,1500n,3000n,0n);
 const applied=await serializable(db,tx=>recordOrderPromotion(tx,{
  code:fixed.body.data.code,customerId:store.customer.id,orderId:fixedOrder.id
 }));
 assert.equal(applied.amountPaise,'1500');
 const free=await send('post',endpoint,'admin',
  promoPayload('SHIP'+id().slice(0,10).toUpperCase(),'FREE_DELIVERY',{minCartPaise:'1000'}));
 assert.equal(free.status,201);
 await send('patch',endpoint+'/'+free.body.data.id,'admin',{active:true});
 // Shipping discounts reduce freight, not taxable item prices.
 const city=await db.city.create({data:{
  code:'HYD'+id().slice(0,12).toUpperCase(),name:'Hyderabad Test',stateCode:'TG',active:true
 }});
 const address=await db.address.create({data:{
  userId:store.customer.id,cityId:city.id,label:'Test site',
  recipientName:'Receiver',phoneE164:'+919876543210',line1:'Road 1',
  locality:'Hyderabad',postalCode:'500001'
 }});
 const linkedQuote=async(discountPaise)=>{
  const quote=await db.checkoutQuote.create({data:{
   customerId:store.customer.id,addressId:address.id,
   cartVersion:0,cartFingerprint:'0'.repeat(64),
   addressSnapshot:{postalCode:'500001'},
   quoteSnapshot:{promotionCode:free.body.data.code,promotionType:'FREE_DELIVERY',
    deliveryBeforePromotionPaise:'2500',promotionAmountPaise:'2500'},
   subtotalPaise:100000n,discountPaise:0n,taxPaise:0n,deliveryPaise:0n,totalPaise:100000n,
   expiresAt:new Date(Date.now()+600000)
  }});
  const order=await makeOrder(store.customer.id,discountPaise,100000n,0n);
  await db.purchaseOrder.update({where:{id:order.id},data:{checkoutQuoteId:quote.id}});
  return order;
 };
 const shipOrder=await linkedQuote(0n);
 const shipped=await serializable(db,tx=>recordOrderPromotion(tx,{
  code:free.body.data.code,customerId:store.customer.id,orderId:shipOrder.id
 }));
 assert.equal(shipped.amountPaise,'2500');
 const invalidOrder=await linkedQuote(200n);
 await assert.rejects(serializable(db,tx=>recordOrderPromotion(tx,{
  code:free.body.data.code,customerId:store.customer.id,orderId:invalidOrder.id
 })),e=>e.code==='PROMOTION_TOTAL_MISMATCH');
  assert.equal((await send('get','/api/v2/promotions/preview','customer')).status,404);
});
test('a cancelled or unapproved RFQ cannot be reopened or quoted',async()=>{
 const payload={
  siteSnapshot:{city:'Hyderabad',postalCode:'500001'},
  items:[{description:'Custom building aggregate',quantity:'3.000',unitCode:'BAG'}]
 };
 const created=await send('post','/api/v2/rfqs','customer',payload,hdr());
 assert.equal(created.status,201);
 const rfq='/api/v2/rfqs/'+created.body.data.id;
 assert.equal((await send('post',rfq+'/cancel','customer',{})).status,200);
 assert.equal((await send('post',rfq+'/open','customer',{})).status,409);
 assert.equal((await send('post',rfq+'/invitations/'+store.first.id,'customer',{})).status,409);
});

test('two simultaneous redemptions cannot exceed the global cap',async()=>{
 const endpoint='/api/v2/admin/promotions';
 const created=await send('post',endpoint,'admin',
  promoPayload('LIMIT'+id().slice(0,12).toUpperCase(),'FIXED_PAISE',{
   amountPaise:'1500',globalLimit:1
  }));
 assert.equal(created.status,201);
 const activated=await send('patch',endpoint+'/'+created.body.data.id,'admin',{active:true});
 assert.equal(activated.status,200);
 const orders=await Promise.all([
  makeOrder(store.customer.id,1500n),
  makeOrder(store.otherCustomer.id,1500n)
 ]);
 const results=await Promise.allSettled(orders.map((order,i)=>serializable(db,tx=>recordOrderPromotion(tx,{
  code:created.body.data.code,
  customerId:i===0?store.customer.id:store.otherCustomer.id,
  orderId:order.id
 }))));
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(results.filter(x=>x.status==='rejected').length,1);
 assert.equal(await db.promotionRedemption.count({where:{promotionId:created.body.data.id}}),1);
});

test('cancelling an open RFQ closes all submitted supplier offers atomically',async()=>{
 const created=await send('post','/api/v2/rfqs','customer',{
  siteSnapshot:{city:'Hyderabad',postalCode:'500001'},
  items:[{description:'Need more cement',quantity:'2.000',unitCode:'BAG'}]
 },hdr());
 assert.equal(created.status,201,JSON.stringify(created.body));
 const rfqId=created.body.data.id,base='/api/v2/rfqs/'+rfqId;
 assert.equal((await send('post',base+'/open','customer',{})).status,200);
 const quote=await db.supplierQuote.create({data:{
  rfqId,supplierId:store.first.id,quoteNumber:'QT-'+id().replaceAll('-').slice(0,20),
  version:1,status:'SUBMITTED',subtotalPaise:1000n,taxPaise:0n,
  deliveryPaise:0n,totalPaise:1000n
 }});
 assert.equal((await send('post',base+'/cancel','customer',{})).status,200);
 assert.equal((await db.supplierQuote.findUniqueOrThrow({where:{id:quote.id}})).status,'REJECTED');
 assert.equal((await db.rfq.findUniqueOrThrow({where:{id:rfqId}})).status,'CANCELLED');
});
