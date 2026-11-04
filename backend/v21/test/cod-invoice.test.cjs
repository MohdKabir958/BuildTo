'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {financialYear}=require('../dist/invoice-service.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),sub=()=> 'user_'+id().replaceAll('-','');
const tokenSubjects={},store={};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokenSubjects[token])throw new ApiError(401,'INVALID_SESSION','Invalid identity');
  return {subject:tokenSubjects[token],sessionId:'sess_codfixture012'};
 }}});
const http=request(app);
function call(method,path,actor,body,key){
 let r=http[method](path);
 if(actor)r=r.set('Authorization','Bearer '+actor);
 if(key)r=r.set('Idempotency-Key',key);
 return body===undefined?r:r.send(body);
}
const key=()=> 'cod_'+id().replaceAll('-');
const customerUrl=()=>'/api/v2/orders/'+store.parent.id;
const supplierUrl=()=>'/api/v2/suppliers/'+store.supplier.id+'/orders/'+store.child.id;
test('fixture: customer, COD seller, separately staffed finance and warehouse-held stock',async()=>{
 for(const role of ['customer','outsider','fulfillment','finance','admin','conflicted','viewer']){
  const user=await db.user.create({data:{clerkUserId:sub(),displayName:'COD '+role}});
  store[role]=user;tokenSubjects[role]=user.clerkUserId;
 }
 const gstin='36QWERT'+String(Math.floor(Math.random()*9000)+1000)+'F1Z1';
 store.gstin=gstin;
 const supplier=await db.supplier.create({data:{
  slug:'cod-'+id(),legalName:'Buildto Cement Private Ltd',
  displayName:'Cement Supplier',approval:'APPROVED',verifiedAt:new Date(),
  gstRegistration:'REGULAR',gstin,
  billingAddress:{line1:'Industrial Estate 12',city:'Hyderabad',
   stateCode:'TG',postalCode:'500001'}
 }});
 store.supplier=supplier;
 await db.supplierMember.createMany({data:[
  {supplierId:supplier.id,userId:store.fulfillment.id,role:'FULFILLMENT',active:true},
  {supplierId:supplier.id,userId:store.finance.id,role:'FINANCE',active:true},
  {supplierId:supplier.id,userId:store.conflicted.id,role:'MANAGER',active:true},
  {supplierId:supplier.id,userId:store.viewer.id,role:'VIEWER',active:true}
 ]});
 await db.adminMembership.createMany({data:[
  {userId:store.admin.id,role:'FINANCE',active:true},
  {userId:store.conflicted.id,role:'FINANCE',active:true}
 ]});
 const cat=await db.category.create({data:{slug:'cod-'+id(),name:'COD Materials',active:true}});
 const prod=await db.product.create({data:{categoryId:cat.id,
  code:'COD'+id().replaceAll('-').slice(0,15).toUpperCase(),
  name:'Cement Bag',hsnCode:'2523',active:true}});
 const listing=await db.supplierListing.create({data:{
  supplierId:supplier.id,productId:prod.id,sku:'COD-'+id().replaceAll('-').slice(0,14),
  unitCode:'BAG',unitPrice:new Prisma.Decimal(50),
  status:'APPROVED',active:true,publishedAt:new Date()
 }});
 store.listing=listing;
 const warehouse=await db.warehouse.create({data:{
  supplierId:supplier.id,code:'COD-'+id().slice(0,16),
  name:'Warehouse COD',active:true
 }});
 const bal=await db.inventoryBalance.create({data:{
  listingId:listing.id,warehouseId:warehouse.id,
  onHandQty:new Prisma.Decimal('5.000'),reservedQty:new Prisma.Decimal('2.000')
 }});
 store.balance=bal;
 const parent=await db.purchaseOrder.create({data:{
  customerId:store.customer.id,clientRequestId:'cod_'+id().replaceAll('-'),
  publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  status:'PLACED',currency:'INR',
  addressSnapshot:{recipientName:'B2C Customer',line1:'Plot 12',
   city:'Hyderabad',stateCode:'TG',postalCode:'500001',phoneE164:'+919876543210'},
  subtotalPaise:10000n,discountPaise:0n,taxPaise:1800n,
  deliveryPaise:0n,totalPaise:11800n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:supplier.id,
  subtotalPaise:10000n,discountPaise:0n,taxPaise:1800n,deliveryPaise:0n,totalPaise:11800n
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:listing.id,skuSnapshot:listing.sku,
  nameSnapshot:'Cement Bag',hsnSnapshot:'2523',unitCode:'BAG',
  packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(2),
  unitPrice:new Prisma.Decimal(50),taxRateBps:1800,
  taxablePaise:10000n,discountPaise:0n,taxPaise:1800n,
  cgstPaise:900n,sgstPaise:900n,lineTotalPaise:11800n
 }});
 const hold=await db.inventoryReservation.create({data:{
  balanceId:bal.id,orderItemId:item.id,quantity:new Prisma.Decimal(2),
  state:'HELD',expiresAt:new Date(Date.now()+1200000)
 }});
 Object.assign(store,{parent,child,item,hold,warehouse});
});
test('COD is owner-authorized, exact-amount, idempotent and not an online capture',async()=>{
 assert.equal((await call('post',customerUrl()+'/cod','outsider',{},key())).status,404);
 assert.equal((await call('post',customerUrl()+'/cod','customer',{})).status,428);
 assert.equal((await call('post',customerUrl()+'/cod','customer',{amountPaise:'1'},key())).status,400);
 const k=key(),first=await call('post',customerUrl()+'/cod','customer',{},k);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.status,'COLLECTION_DUE');
 assert.equal(first.body.data.amountPaise,'11800');
 const repeat=await call('post',customerUrl()+'/cod','customer',{},k);
 assert.equal(repeat.status,200,JSON.stringify(repeat.body));assert.equal(repeat.body.data.replayed,true);
 assert.equal((await call('post',customerUrl()+'/cod','customer',{},key())).status,409);
 const attempts=await db.paymentAttempt.findMany({where:{purchaseOrderId:store.parent.id}});
 assert.equal(attempts.length,1);assert.equal(attempts[0].provider,'MANUAL');
 assert.equal(attempts[0].status,'PENDING');assert.equal(attempts[0].capturedPaise,0n);
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:store.parent.id}})).status,'CONFIRMED');
 const reservation=await db.inventoryReservation.findUniqueOrThrow({where:{id:store.hold.id}});
 assert.equal(reservation.state,'COMMITTED');
 assert.equal((await db.inventoryBalance.findUniqueOrThrow({where:{id:store.balance.id}})).onHandQty.toString(),'3');
 assert.equal((await call('get',customerUrl(),'customer')).body.data.paymentStatus,'COD_DUE');
 assert.equal((await call('post',customerUrl()+'/cancel','customer',{})).status,409);
});
test('a prior Razorpay attempt, even FAILED, blocks COD method switching',async()=>{
 const order=await db.purchaseOrder.create({data:{
  customerId:store.customer.id,clientRequestId:key(),
  publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  addressSnapshot:{city:'Hyderabad'},subtotalPaise:1000n,totalPaise:1000n
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:order.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:key(),amountPaise:1000n,status:'FAILED'
 }});
 const r=await call('post','/api/v2/orders/'+order.id+'/cod','customer',{},key());
 assert.equal(r.status,409);assert.equal(r.body.error.code,'PAYMENT_METHOD_LOCKED');
});
test('supplier cash claim requires delivered shipment with verified handover',async()=>{
 const url=supplierUrl()+'/cod';
 const body={shipmentId:id(),receiptNumber:'CASH-'+id().replaceAll('-').slice(0,24),
  note:'Customer handed cash on delivery'};
 assert.equal((await call('post',url,'customer',body,key())).status,404);
 assert.equal((await call('post',url,'viewer',body,key())).status,403);
 assert.equal((await call('post',url,'fulfillment',body,key())).status,409);
 await db.supplierOrder.update({where:{id:store.child.id},data:{
  status:'DELIVERED'
 }});
 const shipment=await db.shipment.create({data:{
  shipmentNumber:'CODSH-'+id().replaceAll('-').slice(0,25),
  supplierId:store.supplier.id,supplierOrderId:store.child.id,
  status:'DELIVERED',deliveredAt:new Date(),
  handoverMethod:'APPROVED_EXCEPTION',
  exceptionReason:'Independent supervisor approved delivery handover',
  exceptionApprovedAt:new Date(),exceptionApprovedById:store.admin.id
 }});
 store.shipment=shipment;
 const receiptBody={...body,shipmentId:shipment.id};
 const k=key(),first=await call('post',url,'fulfillment',receiptBody,k);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.status,'RECORDED');
 assert.equal(first.body.data.collectedPaise,'11800');
 store.receiptId=first.body.data.id;
 const repeat=await call('post',url,'fulfillment',receiptBody,k);
 assert.equal(repeat.status,200,JSON.stringify(repeat.body));
 assert.equal(repeat.body.replayed,true);
 assert.equal((await call('post',url,'fulfillment',receiptBody,key())).status,409);
 const child=await db.supplierOrder.findUniqueOrThrow({where:{id:store.child.id}});
 assert.equal(child.codRecordedPaise,11800n);assert.equal(child.codVerifiedPaise,0n);
 const order=await call('get',customerUrl(),'customer');
 assert.equal(order.body.data.paymentStatus,'COD_RECORDED_UNVERIFIED');
 assert.equal((await call('get',url,'finance')).body.data.length,1);
 assert.equal((await call('get',url,'outsider')).status,404);
});
test('independent admin finance posts balanced immutable journal before COD verification',async()=>{
 const endpoint='/api/v2/admin/finance/cod/'+store.receiptId+'/review';
 assert.equal((await call('post',endpoint,'fulfillment',{decision:'VERIFY',externalReference:'CASHBATCH-12345'})).status,403);
 assert.equal((await call('post',endpoint,'conflicted',{decision:'VERIFY',externalReference:'CASHBATCH-12345'})).status,403);
 assert.equal((await call('post',endpoint,'admin',{decision:'VERIFY'})).status,400);
 const verified=await call('post',endpoint,'admin',{
  decision:'VERIFY',externalReference:'CASHBATCH-12345'
 });
 assert.equal(verified.status,200,JSON.stringify(verified.body));
 assert.equal(verified.body.data.status,'VERIFIED');
 const repeat=await call('post',endpoint,'admin',{
  decision:'VERIFY',externalReference:'CASHBATCH-12345'
 });
 assert.equal(repeat.status,200,JSON.stringify(repeat.body));assert.equal(repeat.body.replayed,true);
 const receipt=await db.codCollection.findUniqueOrThrow({where:{id:store.receiptId}});
 assert.equal(receipt.verifiedByUserId,store.admin.id);
 const journal=await db.ledgerJournal.findUniqueOrThrow({where:{
  referenceKey:receipt.journalReference},include:{lines:true}
 });
 assert(journal.postedAt);assert.equal(journal.lines.length,2);
 assert.equal(journal.lines.reduce((v,l)=>v+l.debitPaise,0n),11800n);
 assert.equal(journal.lines.reduce((v,l)=>v+l.creditPaise,0n),11800n);
 const child=await db.supplierOrder.findUniqueOrThrow({where:{id:store.child.id}});
 assert.equal(child.codVerifiedPaise,11800n);
 assert.equal((await call('get',customerUrl(),'customer')).body.data.paymentStatus,'COD_VERIFIED');
 assert.equal((await db.paymentAttempt.findFirstOrThrow({
  where:{purchaseOrderId:store.parent.id}})).status,'PENDING',
  'COD does not pretend to be Razorpay capture');
});
test('supplier-finance issues exact GST snapshot invoice once; customer can only see own',async()=>{
 const path=supplierUrl()+'/invoices';
 assert.equal((await call('post',path,'fulfillment',{})).status,403);
 assert.equal((await call('post',path,'finance',{taxPaise:'0'})).status,400);
 const issued=await call('post',path,'finance',{});
 assert.equal(issued.status,201,JSON.stringify(issued.body));
 const invoice=issued.body.data;
 assert.equal(invoice.kind,'TAX_INVOICE');
 assert.equal(invoice.taxablePaise,'10000');assert.equal(invoice.taxPaise,'1800');
 assert.equal(invoice.cgstPaise,'900');assert.equal(invoice.sgstPaise,'900');
 assert.equal(invoice.totalPaise,'11800');assert.equal(invoice.lines.items.length,1);
 assert.equal(invoice.seller.gstin,store.gstin);
 assert.equal(invoice.financialYear,financialYear(new Date()));
 const repeated=await call('post',path,'finance',{});
 assert.equal(repeated.status,200,JSON.stringify(repeated.body));
 assert.equal(repeated.body.replayed,true);
 assert.equal((await db.taxInvoice.count({where:{supplierOrderId:store.child.id}})),1);
 assert.equal((await call('get',path,'finance')).body.data.length,1);
 assert.equal((await call('get',customerUrl()+'/invoices','customer')).body.data.length,1);
 assert.equal((await call('get',customerUrl()+'/invoices','outsider')).status,404);
});
test('taxable freight is not misclassified as exempt GST in issued invoices',async()=>{
 const parent=await db.purchaseOrder.create({data:{
  customerId:store.customer.id,clientRequestId:key(),publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  status:'CONFIRMED',addressSnapshot:{recipientName:'Test buyer',line1:'Site',
   city:'Hyderabad',stateCode:'TG',postalCode:'500001'},
  subtotalPaise:10000n,taxPaise:1800n,deliveryPaise:1000n,totalPaise:12800n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:store.supplier.id,status:'DISPATCHED',
  subtotalPaise:10000n,taxPaise:1800n,deliveryPaise:1000n,totalPaise:12800n
 }});
 await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:store.listing.id,skuSnapshot:store.listing.sku,
  nameSnapshot:'Cement Bag',hsnSnapshot:'2523',unitCode:'BAG',
  packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(2),
  unitPrice:new Prisma.Decimal(50),taxRateBps:1800,
  taxablePaise:10000n,taxPaise:1800n,cgstPaise:900n,sgstPaise:900n,
  lineTotalPaise:11800n
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:key(),status:'CAPTURED',amountPaise:12800n,capturedPaise:12800n,
  providerOrderRef:'order_'+id().replaceAll('-').slice(0,20),
  providerPayRef:'pay_'+id().replaceAll('-').slice(0,20),verifiedAt:new Date()
 }});
 const route='/api/v2/suppliers/'+store.supplier.id+'/orders/'+child.id+'/invoices';
 const r=await call('post',route,'finance',{});
 assert.equal(r.status,409,JSON.stringify(r.body));
 assert.equal(r.body.error.code,'FREIGHT_GST_POLICY_REQUIRED');
 assert.equal(await db.taxInvoice.count({where:{supplierOrderId:child.id}}),0);
});

test('provider CAPTURED flag without verified amount/reference never licenses a tax invoice',async()=>{
 const parent=await db.purchaseOrder.create({data:{
  customerId:store.customer.id,clientRequestId:key(),publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  status:'CONFIRMED',addressSnapshot:{recipientName:'B2C User',line1:'Building',
   city:'Hyderabad',stateCode:'TG',postalCode:'500001'},
  subtotalPaise:10000n,taxPaise:1800n,totalPaise:11800n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:store.supplier.id,status:'DISPATCHED',
  subtotalPaise:10000n,taxPaise:1800n,totalPaise:11800n
 }});
 await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,listingId:store.listing.id,skuSnapshot:store.listing.sku,
  nameSnapshot:'Cement Bag',hsnSnapshot:'2523',unitCode:'BAG',
  packSizeSnapshot:new Prisma.Decimal(1),quantity:new Prisma.Decimal(2),
  unitPrice:new Prisma.Decimal(50),taxRateBps:1800,
  taxablePaise:10000n,taxPaise:1800n,cgstPaise:900n,sgstPaise:900n,
  lineTotalPaise:11800n
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  idempotencyKey:key(),status:'CAPTURED',amountPaise:11800n,capturedPaise:0n
 }});
 const route='/api/v2/suppliers/'+store.supplier.id+'/orders/'+child.id+'/invoices';
 const r=await call('post',route,'finance',{});
 assert.equal(r.status,409,JSON.stringify(r.body));
 assert.equal(r.body.error.code,'INVOICE_PAYMENT_METHOD_REQUIRED');
 assert.equal(await db.taxInvoice.count({where:{supplierOrderId:child.id}}),0);
});
test('verified composition supplier issues zero-GST bill of supply, never a tax invoice',async()=>{
 const supplier=await db.supplier.create({data:{
  slug:'composition-'+id(),legalName:'Local Composition Building Materials',
  displayName:'Local Materials',approval:'APPROVED',verifiedAt:new Date(),
  gstRegistration:'COMPOSITION',billingAddress:{line1:'Street 6',
   city:'Hyderabad',stateCode:'TG',postalCode:'500001'}
 }});
 await db.supplierMember.create({data:{
  supplierId:supplier.id,userId:store.finance.id,role:'FINANCE',active:true
 }});
 const parent=await db.purchaseOrder.create({data:{
  customerId:store.customer.id,clientRequestId:key(),
  publicNumber:'BT-'+id().replaceAll('-').slice(0,24),
  status:'CONFIRMED',addressSnapshot:{recipientName:'B2C buyer',line1:'Construction Site',
   city:'Hyderabad',stateCode:'TG',postalCode:'500001'},
  subtotalPaise:10000n,totalPaise:10000n
 }});
 const child=await db.supplierOrder.create({data:{
  purchaseOrderId:parent.id,supplierId:supplier.id,status:'DISPATCHED',
  subtotalPaise:10000n,totalPaise:10000n
 }});
 await db.supplierOrderItem.create({data:{
  supplierOrderId:child.id,skuSnapshot:'COMPO-ONE',nameSnapshot:'Exempt material',
  unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal(1),
  quantity:new Prisma.Decimal(1),unitPrice:new Prisma.Decimal(100),
  taxRateBps:0,taxablePaise:10000n,taxPaise:0n,lineTotalPaise:10000n
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:parent.id,provider:'RAZORPAY',paymentMethod:'UPI',
  providerOrderRef:'order_'+id().replaceAll('-').slice(0,20),
  providerPayRef:'pay_'+id().replaceAll('-').slice(0,20),
  idempotencyKey:key(),status:'CAPTURED',
  verifiedAt:new Date(),amountPaise:10000n,capturedPaise:10000n
 }});
 const route='/api/v2/suppliers/'+supplier.id+'/orders/'+child.id+'/invoices';
 const issued=await call('post',route,'finance',{});
 assert.equal(issued.status,201,JSON.stringify(issued.body));
 assert.equal(issued.body.data.kind,'BILL_OF_SUPPLY');
 assert.equal(issued.body.data.taxPaise,'0');
 assert.equal(issued.body.data.totalPaise,'10000');
 assert.equal(issued.body.data.seller.gstRegistration,'COMPOSITION');
});
