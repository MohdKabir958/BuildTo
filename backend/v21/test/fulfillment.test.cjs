'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {Prisma,PrismaClient}=require('../../generated/buildto-v21');
const {ApiError}=require('../dist/errors.js');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),sub=()=> 'user_'+id().replaceAll('-','');
const key=()=> 'ship_'+id().replaceAll('-');
const SECRET='test-secret-for-delivery-otp-0123456789-abcdef';
const users={},tokens={},st={};
const app=createV21App({db,limiter:new InMemoryTestLimiter(),log:()=>{},
 allowedOrigins:[],proxyHops:0,deliveryOtpSecret:SECRET,
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid identity.');
  return {subject:tokens[token],sessionId:'sess_ship_112233'};
 }}});
const api=request(app);
function send(method,path,actor,body,idem){
 let req=api[method](path);
 if(actor)req=req.set('Authorization','Bearer '+actor);
 if(idem)req=req.set('Idempotency-Key',idem);
 return body===undefined?req:req.send(body);
}
const sup=()=>'/api/v2/suppliers/'+st.supplier.id;
const order=()=>sup()+'/orders/'+st.child.id;
const ship=id=>sup()+'/shipments/'+id;
const cust=()=>'/api/v2/orders/'+st.parent.id;
const qty=s=>new Prisma.Decimal(s);
async function newParent(quantity='1'){
 const money=BigInt(qty(quantity).mul(10000).toFixed(0));
 const parent=await db.purchaseOrder.create({data:{
  customerId:users.customer.id,publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  clientRequestId:key(),status:'PLACED',currency:'INR',
  addressSnapshot:{recipientName:'Customer',line1:'Site 4',city:'Hyderabad',
   stateCode:'TG',postalCode:'500001',phoneE164:'+919876543210'},
  subtotalPaise:money,totalPaise:money
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:st.supplier.id,
  subtotalPaise:money,totalPaise:money
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:st.listing.id,skuSnapshot:st.listing.sku,
  nameSnapshot:'Cement',unitCode:'BAG',packSizeSnapshot:qty('1'),quantity:qty(quantity),
  unitPrice:qty('100'),taxRateBps:0,taxablePaise:money,taxPaise:0n,lineTotalPaise:money
 }});
 return {parent,child,item,money};
}
async function completeOnline(quantity='1'){
 const result=await newParent(quantity);
 await db.inventoryReservation.create({data:{
  orderItemId:result.item.id,balanceId:st.balance.id,quantity:qty(quantity),
  state:'COMMITTED',expiresAt:new Date(Date.now()+300000)
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:result.parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:key(),status:'CAPTURED',amountPaise:result.money,
  capturedPaise:result.money,providerOrderRef:'order_'+id().replaceAll('-').slice(0,20),
  providerPayRef:'pay_'+id().replaceAll('-').slice(0,20),verifiedAt:new Date()
 }});
 await db.purchaseOrder.update({where:{id:result.parent.id},data:{status:'CONFIRMED'}});
 return result;
}
async function advance(route,actor='fulfillment'){
 for(const stage of ['pack','dispatch','out-for-delivery']){
  const response=await send('post',route+'/'+stage,actor,{});
  assert.equal(response.status,200,JSON.stringify(response.body));
 }
}
test('fixture: approved supplier, warehouse stock, separate personnel and unpaid parent',async()=>{
 for(const role of ['customer','outsider','fulfillment','viewer','finance','admin','conflicted']){
  const user=await db.user.create({data:{clerkUserId:sub(),displayName:'Ship '+role}});
  users[role]=user;tokens[role]=user.clerkUserId;
 }
 st.supplier=await db.supplier.create({data:{
  slug:'ship-'+id(),legalName:'Shipment Materials',displayName:'Ship Supplier',
  approval:'APPROVED',verifiedAt:new Date()
 }});
 await db.supplierMember.createMany({data:[
  {supplierId:st.supplier.id,userId:users.fulfillment.id,role:'FULFILLMENT',active:true},
  {supplierId:st.supplier.id,userId:users.viewer.id,role:'VIEWER',active:true},
  {supplierId:st.supplier.id,userId:users.finance.id,role:'FINANCE',active:true},
  {supplierId:st.supplier.id,userId:users.conflicted.id,role:'MANAGER',active:true}
 ]});
 await db.adminMembership.createMany({data:[
  {userId:users.admin.id,role:'SUPPORT',active:true},
  {userId:users.conflicted.id,role:'OWNER',active:true}
 ]});
 const category=await db.category.create({data:{
  slug:'ship-'+id(),name:'Shipment Concrete',active:true
 }});
 const product=await db.product.create({data:{
  code:'SHIP'+id().replaceAll('-').slice(0,12).toUpperCase(),
  categoryId:category.id,name:'Cement',active:true
 }});
 st.listing=await db.supplierListing.create({data:{
  supplierId:st.supplier.id,productId:product.id,
  sku:'SHIP-'+id().replaceAll('-').slice(0,14),
  unitCode:'BAG',unitPrice:qty('100'),status:'APPROVED',
  active:true,publishedAt:new Date()
 }});
 st.warehouse=await db.warehouse.create({data:{
  supplierId:st.supplier.id,code:'SHIP-'+id().slice(0,16),name:'Warehouse',active:true
 }});
 st.balance=await db.inventoryBalance.create({data:{
  listingId:st.listing.id,warehouseId:st.warehouse.id,
  onHandQty:qty('10'),reservedQty:qty('4')
 }});
 const first=await newParent('4');
 Object.assign(st,first);
 st.hold=await db.inventoryReservation.create({data:{
  orderItemId:st.item.id,balanceId:st.balance.id,quantity:qty('4'),
  state:'HELD',expiresAt:new Date(Date.now()+1200000)
 }});
 const view=await send('get',sup()+'/orders','fulfillment');
 assert.equal(view.status,200,JSON.stringify(view.body));
 assert.equal(view.body.data[0].id,st.child.id);
 assert.equal((await send('get',sup()+'/orders','outsider')).status,404);
});
test('unpaid order cannot be accepted or shipped; only authenticated COD selection confirms',async()=>{
 const accept=order()+'/accept';
 const before=await send('post',accept,'fulfillment',{});
 assert.equal(before.status,409);
 assert.equal(before.body.error.code,'FULFILLMENT_PAYMENT_REQUIRED');
 assert.equal((await send('post',accept,'customer',{})).status,404);
 assert.equal((await send('post',accept,'viewer',{})).status,403);
 const invalid=await send('post',order()+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:st.item.id,quantity:'1'}]
 },key());
 assert.equal(invalid.status,409);
 const cod=await send('post',cust()+'/cod','customer',{},key());
 assert.equal(cod.status,201,JSON.stringify(cod.body));
 assert.equal((await db.inventoryReservation.findUniqueOrThrow({where:{id:st.hold.id}})).state,'COMMITTED');
 const first=await send('post',accept,'fulfillment',{});
 assert.equal(first.status,200,JSON.stringify(first.body));
 assert.equal(first.body.data.status,'CONFIRMED');
 const again=await send('post',accept,'fulfillment',{});
 assert.equal(again.status,200);assert.equal(again.body.data.replayed,true);
 assert.equal((await db.supplierOrderEvent.count({where:{supplierOrderId:st.child.id,toStatus:'CONFIRMED'}})),1);
});
test('two trucks split exactly four units; provider, warehouse and idempotency are protected',async()=>{
 const path=order()+'/shipments';
 assert.equal((await send('post',path,'viewer',{warehouseId:st.warehouse.id,
  lines:[{orderItemId:st.item.id,quantity:'2'}]},key())).status,403);
 assert.equal((await send('post',path,'fulfillment',{warehouseId:st.warehouse.id,
  lines:[{orderItemId:st.item.id,quantity:2}]},key())).status,400);
 const body={warehouseId:st.warehouse.id,
  lines:[{orderItemId:st.item.id,quantity:'2.000'}],
  carrierName:'Supplier-owned lorry',vehicleLabel:'TG-07-MATERIALS'};
 const k=key();
 const a=await send('post',path,'fulfillment',body,k);
 assert.equal(a.status,201,JSON.stringify(a.body));
 st.firstShipId=a.body.data.id;
 assert.equal(a.body.data.items[0].quantity,'2');
 const repeated=await send('post',path,'fulfillment',body,k);
 assert.equal(repeated.status,200,JSON.stringify(repeated.body));
 assert.equal(repeated.body.data.id,st.firstShipId);
 const b=await send('post',path,'fulfillment',body,key());
 assert.equal(b.status,201,JSON.stringify(b.body));
 st.secondShipId=b.body.data.id;
 const excess=await send('post',path,'fulfillment',body,key());
 assert.equal(excess.status,409,JSON.stringify(excess.body));
 assert.equal(excess.body.error.code,'SHIPMENT_ALLOCATION_EXCEEDED');
 const line=await db.supplierOrderItem.findUniqueOrThrow({where:{id:st.item.id}});
 assert.equal(line.allocatedShipmentQty.toString(),'4');
 assert.equal(await db.shipment.count({where:{supplierOrderId:st.child.id}}),2);
 assert.equal((await send('get',order()+'/shipments','customer')).status,404);
 assert.equal((await send('get',cust()+'/shipments','outsider')).status,404);
 assert.equal((await send('get',cust()+'/shipments','customer')).body.data.length,2);
});
test('customer-only OTP handover is verified once; first truck means PARTIALLY_DELIVERED',async()=>{
 const url=ship(st.firstShipId);
 assert.equal((await send('post',url+'/dispatch','fulfillment',{})).status,409);
 assert.equal((await send('post',cust()+'/shipments/'+st.firstShipId+'/otp','customer',{})).status,409);
 await advance(url);
 assert.equal((await send('get',order()+'/shipments','fulfillment')).body.data[0].deliveryOtpHash,undefined);
 assert.equal((await send('post',cust()+'/shipments/'+st.firstShipId+'/otp','outsider',{})).status,404);
 assert.equal((await send('post',cust()+'/shipments/'+st.firstShipId+'/otp','fulfillment',{})).status,404);
 const issue=await send('post',cust()+'/shipments/'+st.firstShipId+'/otp','customer',{});
 assert.equal(issue.status,200,JSON.stringify(issue.body));
 assert.match(issue.body.data.otp,/^[0-9]{6}$/);
 st.firstOtp=issue.body.data.otp;
 assert.equal((await send('post',cust()+'/shipments/'+st.firstShipId+'/otp','customer',{})).status,409);
 const wrong=await send('post',url+'/handover','fulfillment',
  {method:'OTP',otp:'x'.repeat(6)});
 assert.equal(wrong.status,400);
 const wrongOtp=st.firstOtp==='123456'?'123457':'123456';
 const invalid=await send('post',url+'/handover','fulfillment',{method:'OTP',otp:wrongOtp});
 assert.equal(invalid.status,422,JSON.stringify(invalid.body));
 assert.equal((await db.shipment.findUniqueOrThrow({where:{id:st.firstShipId}})).otpAttempts,1);
 assert.equal((await send('post',url+'/handover','outsider',{method:'OTP',otp:st.firstOtp})).status,404);
 const success=await send('post',url+'/handover','fulfillment',{method:'OTP',otp:st.firstOtp});
 assert.equal(success.status,200,JSON.stringify(success.body));
 assert.equal(success.body.data.status,'DELIVERED');
 assert.equal(success.body.data.supplierOrderStatus,'PARTIALLY_DELIVERED');
 const replay=await send('post',url+'/handover','fulfillment',{method:'OTP',otp:st.firstOtp});
 assert.equal(replay.status,200);assert.equal(replay.body.data.replayed,true);
 const shipped=await db.shipmentItem.findFirstOrThrow({where:{shipmentId:st.firstShipId}});
 assert.equal(shipped.deliveredQty.toString(),'2');
 assert.equal(shipped.rejectedQty.toString(),'0');
 assert.equal((await db.supplierOrder.findUniqueOrThrow({where:{id:st.child.id}})).status,'PARTIALLY_DELIVERED');
 assert.equal((await send('post',order()+'/cod','fulfillment',{
  shipmentId:st.firstShipId,receiptNumber:'CASH-'+id().slice(0,12),
  note:'Not all goods have been delivered'
 },key())).status,409);
});
test('second fully delivered truck completes child and parent; COD claim is still unverified',async()=>{
 const route=ship(st.secondShipId);
 await advance(route);
 const issued=await send('post',cust()+'/shipments/'+st.secondShipId+'/otp','customer',{});
 assert.equal(issued.status,200,JSON.stringify(issued.body));
 const complete=await send('post',route+'/handover','fulfillment',
  {method:'OTP',otp:issued.body.data.otp,receivedBy:'Customer'});
 assert.equal(complete.status,200,JSON.stringify(complete.body));
 assert.equal(complete.body.data.supplierOrderStatus,'DELIVERED');
 assert.equal((await db.supplierOrder.findUniqueOrThrow({where:{id:st.child.id}})).status,'DELIVERED');
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:st.parent.id}})).status,'FULFILLED');
 assert.equal((await send('get',cust(),'customer')).body.data.paymentStatus,'COD_DUE');
 const cash=await send('post',order()+'/cod','fulfillment',{
  shipmentId:st.secondShipId,receiptNumber:'CASH-'+id().replaceAll('-').slice(0,20),
  note:'Customer physically paid cash at full handover'
 },key());
 assert.equal(cash.status,201,JSON.stringify(cash.body));
 assert.equal(cash.body.data.status,'RECORDED');
 assert.equal((await send('get',cust(),'customer')).body.data.paymentStatus,'COD_RECORDED_UNVERIFIED');
});
test('no supplier self-approval of delivery exception and no unproven online fulfillment',async()=>{
 const extra=await completeOnline('1');
 st.online=extra;
 const reject=await send('post',sup()+'/orders/'+extra.child.id+'/reject',
  'fulfillment',{reason:'Cannot supply the material'});
 assert.equal(reject.status,409,JSON.stringify(reject.body));
 assert.equal(reject.body.error.code,'FINANCIAL_ADJUSTMENT_REQUIRED');
 const accept=await send('post',sup()+'/orders/'+extra.child.id+'/accept','fulfillment',{});
 assert.equal(accept.status,200,JSON.stringify(accept.body));
 const made=await send('post',sup()+'/orders/'+extra.child.id+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:extra.item.id,quantity:'1'}]
 },key());
 assert.equal(made.status,201,JSON.stringify(made.body));
 st.onlineShipId=made.body.data.id;
 await advance(ship(st.onlineShipId));
 const endpoint='/api/v2/admin/shipments/'+st.onlineShipId+'/exception-approve';
 assert.equal((await send('post',endpoint,'fulfillment',{
  reason:'Supervisor unreachable during delivery handover'
 })).status,403);
 assert.equal((await send('post',endpoint,'conflicted',{
  reason:'Supplier manager must not self-approve delivery'
 })).status,403);
 assert.equal((await send('post',ship(st.onlineShipId)+'/handover','fulfillment',{
  method:'EXCEPTION'
 })).status,409);
 const granted=await send('post',endpoint,'admin',{
  reason:'Independent support review of verified recipient handover'
 });
 assert.equal(granted.status,200,JSON.stringify(granted.body));
 assert.equal(granted.body.data.approved,true);
 const done=await send('post',ship(st.onlineShipId)+'/handover','fulfillment',{
  method:'EXCEPTION',receivedBy:'Recipient'
 });
 assert.equal(done.status,200,JSON.stringify(done.body));
 assert.equal(done.body.data.handoverMethod,'APPROVED_EXCEPTION');
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:extra.parent.id}})).status,'FULFILLED');
 const orderView=await send('get','/api/v2/orders/'+extra.parent.id,'customer');
 assert.equal(orderView.body.data.paymentStatus,'CAPTURED',
  'A captured Razorpay order must stay paid even after fulfillment.');
});
test('five incorrect OTPs persist lockout, including concurrent retries',async()=>{
 const extra=await completeOnline('1');
 await send('post',sup()+'/orders/'+extra.child.id+'/accept','fulfillment',{});
 const planned=await send('post',sup()+'/orders/'+extra.child.id+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:extra.item.id,quantity:'1'}]
 },key());
 assert.equal(planned.status,201,JSON.stringify(planned.body));
 const shipmentId=planned.body.data.id;
 await advance(ship(shipmentId));
 const issue=await send('post','/api/v2/orders/'+extra.parent.id+'/shipments/'+shipmentId+'/otp',
  'customer',{});
 assert.equal(issue.status,200);
 const wrong=issue.body.data.otp==='444444'?'444445':'444444';
 for(let i=1;i<=5;i++){
  const result=await send('post',ship(shipmentId)+'/handover','fulfillment',
   {method:'OTP',otp:wrong});
  assert.equal(result.status,i===5?429:422,JSON.stringify(result.body));
 }
 const sh=await db.shipment.findUniqueOrThrow({where:{id:shipmentId}});
 assert.equal(sh.otpAttempts,5);
 assert(sh.otpLockedUntil>new Date());
 assert.equal((await send('post',ship(shipmentId)+'/handover','fulfillment',
  {method:'OTP',otp:issue.body.data.otp})).status,429);
 assert.equal((await send('post','/api/v2/orders/'+extra.parent.id+'/shipments/'+shipmentId+'/otp',
  'customer',{})).status,429);
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:extra.parent.id}})).status,'CONFIRMED');
});
test('supplier can refuse an unpaid child without cancelling other supplier children',async()=>{
 const another=await db.supplier.create({data:{
  slug:'ship-other-'+id(),legalName:'Second Supplier',displayName:'Second',
  approval:'APPROVED'
 }});
 const part=await newParent('1');
 await db.supplierOrder.create({data:{
  purchaseOrderId:part.parent.id,supplierId:another.id,
  subtotalPaise:10000n,totalPaise:10000n
 }});
 await db.inventoryBalance.update({where:{id:st.balance.id},data:{
  reservedQty:{increment:qty('1')}
 }});
 const hold=await db.inventoryReservation.create({data:{
  orderItemId:part.item.id,balanceId:st.balance.id,quantity:qty('1'),
  state:'HELD',expiresAt:new Date(Date.now()+1200000)
 }});
 const r=await send('post',sup()+'/orders/'+part.child.id+'/reject',
  'fulfillment',{reason:'Unpaid order cannot be supplied from this warehouse'});
 assert.equal(r.status,200,JSON.stringify(r.body));
 assert.equal(r.body.data.status,'REJECTED');
 assert.equal((await db.inventoryReservation.findUniqueOrThrow({where:{id:hold.id}})).state,'RELEASED');
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:part.parent.id}})).status,
  'PARTIALLY_CANCELLED');
 assert.equal((await db.supplierOrder.findFirstOrThrow({where:{
  purchaseOrderId:part.parent.id,supplierId:another.id}})).status,'PENDING_ACCEPTANCE');
 assert.equal((await send('post',sup()+'/orders/'+part.child.id+'/reject',
  'fulfillment',{reason:'Unpaid order cannot be supplied from this warehouse'})).body.data.replayed,true);
});

test('captured fulfillment survives a previous failed UPI payment attempt',async()=>{
 const extra=await completeOnline('1');
 await db.paymentAttempt.create({data:{
  purchaseOrderId:extra.parent.id,provider:'RAZORPAY',
  paymentMethod:'UPI',status:'FAILED',amountPaise:extra.money,
  idempotencyKey:key()
 }});
 const route=sup()+'/orders/'+extra.child.id;
 const a=await send('post',route+'/accept','fulfillment',{});
 assert.equal(a.status,200,JSON.stringify(a.body));
 const b=await send('post',route+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:extra.item.id,quantity:'1'}]
 },key());
 assert.equal(b.status,201,JSON.stringify(b.body));
});
test('cancelled planned and packed lorries release allocated quantity exactly once',async()=>{
 const extra=await completeOnline('1');
 const route=sup()+'/orders/'+extra.child.id;
 assert.equal((await send('post',route+'/accept','fulfillment',{})).status,200);
 const plan=()=>send('post',route+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:extra.item.id,quantity:'1'}]
 },key());
 const planned=await plan();
 assert.equal(planned.status,201,JSON.stringify(planned.body));
 const a=ship(planned.body.data.id)+'/cancel';
 assert.equal((await send('post',a,'outsider',{reason:'Truck unavailable'})).status,404);
 const done=await send('post',a,'fulfillment',{reason:'Truck unavailable before loading'});
 assert.equal(done.status,200,JSON.stringify(done.body));
 assert.equal((await db.supplierOrderItem.findUniqueOrThrow({where:{id:extra.item.id}}))
  .allocatedShipmentQty.toString(),'0');
 assert.equal((await send('post',a,'fulfillment',{reason:'Truck unavailable before loading'})).body.data.replayed,true);
 const next=await plan();assert.equal(next.status,201,JSON.stringify(next.body));
 const second=ship(next.body.data.id);
 assert.equal((await send('post',second+'/pack','fulfillment',{})).status,200);
 assert.equal((await send('post',second+'/cancel','fulfillment',{reason:'Crane breakdown before dispatch'})).status,200);
 assert.equal((await db.supplierOrderItem.findUniqueOrThrow({where:{id:extra.item.id}}))
  .allocatedShipmentQty.toString(),'0');
 const final=await plan();assert.equal(final.status,201,JSON.stringify(final.body));
 await advance(ship(final.body.data.id));
 assert.equal((await send('post',ship(final.body.data.id)+'/cancel','fulfillment',{
  reason:'Already dispatched; this cannot be silently cancelled'
 })).status,409);
});
test('verified partially rejected material frees only rejected allocation for replacement shipment',async()=>{
 const extra=await completeOnline('3');
 const route=sup()+'/orders/'+extra.child.id;
 assert.equal((await send('post',route+'/accept','fulfillment',{})).status,200);
 const plan=quantity=>send('post',route+'/shipments','fulfillment',{
  warehouseId:st.warehouse.id,lines:[{orderItemId:extra.item.id,quantity}]
 },key());
 const original=await plan('3');
 assert.equal(original.status,201,JSON.stringify(original.body));
 const first=ship(original.body.data.id);
 await advance(first);
 const otp=await send('post','/api/v2/orders/'+extra.parent.id+'/shipments/'+original.body.data.id+'/otp',
  'customer',{});
 assert.equal(otp.status,200,JSON.stringify(otp.body));
 const partial=await send('post',first+'/handover','fulfillment',{
  method:'OTP',otp:otp.body.data.otp,
  lines:[{orderItemId:extra.item.id,deliveredQty:'2',rejectedQty:'1'}]
 });
 assert.equal(partial.status,200,JSON.stringify(partial.body));
 assert.equal(partial.body.data.status,'PARTIALLY_DELIVERED');
 assert.equal(partial.body.data.rejectedQty,'1');
 assert.equal((await db.supplierOrderItem.findUniqueOrThrow({where:{id:extra.item.id}}))
  .allocatedShipmentQty.toString(),'2');
 const wrong=await send('post',first+'/handover','fulfillment',{
  method:'OTP',otp:otp.body.data.otp,
  lines:[{orderItemId:extra.item.id,deliveredQty:'1',rejectedQty:'2'}]
 });
 assert.equal(wrong.status,409);
 const replacement=await plan('1');
 assert.equal(replacement.status,201,JSON.stringify(replacement.body));
 assert.equal((await db.supplierOrderItem.findUniqueOrThrow({where:{id:extra.item.id}}))
  .allocatedShipmentQty.toString(),'3');
 assert.equal((await plan('1')).status,409,'replacements cannot overship purchased qty');
 const second=ship(replacement.body.data.id);
 await advance(second);
 const otp2=await send('post','/api/v2/orders/'+extra.parent.id+
   '/shipments/'+replacement.body.data.id+'/otp','customer',{});
 assert.equal(otp2.status,200,JSON.stringify(otp2.body));
 const receipt=await send('post',second+'/handover','fulfillment',{
  method:'OTP',otp:otp2.body.data.otp
 });
 assert.equal(receipt.status,200,JSON.stringify(receipt.body));
 assert.equal(receipt.body.data.supplierOrderStatus,'DELIVERED');
 assert.equal((await db.supplierOrder.findUniqueOrThrow({where:{id:extra.child.id}})).status,'DELIVERED');
 const counts=await db.shipmentItem.findMany({where:{shipment:{supplierOrderId:extra.child.id}}});
 assert.equal(counts.reduce((acc,l)=>acc.plus(l.deliveredQty),qty('0')).toString(),'3');
});
