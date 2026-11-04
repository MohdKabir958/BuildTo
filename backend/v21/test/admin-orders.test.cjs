'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const request=require('supertest');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const db=new PrismaClient();test.after(async()=>db.$disconnect());
async function user(name){return db.user.create({data:{
 clerkUserId:'user_'+randomUUID().replaceAll('-',''),displayName:name,
 email:name+randomUUID()+'@example.test',status:'ACTIVE'
 }});}
const app=tokens=>createV21App({db,allowedOrigins:['https://admin.buildto.example'],
 proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Not authenticated');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}});
const get=(api,path,t)=>api.get(path).set('Authorization','Bearer '+t);
test('A10: admin can inspect supplier split and funding without customer PII; catalog and unauthenticated blocked',async()=>{
 const customer=await user('orderCustomer'),ops=await user('orderOps'),catalog=await user('orderCatalog');
 await db.adminMembership.createMany({data:[
  {userId:ops.id,role:'OPERATIONS',active:true},{userId:catalog.id,role:'CATALOG',active:true}
 ]});
 const supplier=await db.supplier.create({data:{
  slug:'order-inspection-'+randomUUID(),legalName:'Safe Materials',displayName:'Safe Materials',approval:'APPROVED'
 }});
 const order=await db.purchaseOrder.create({data:{
  publicNumber:'ORD-'+randomUUID().slice(0,10),customerId:customer.id,clientRequestId:randomUUID(),
  addressSnapshot:{privateName:'Do not disclose buyer',privatePhone:'+919999999999'},
  subtotalPaise:5000n,discountPaise:0n,taxPaise:900n,deliveryPaise:100n,totalPaise:6000n
 }});
 await db.supplierOrder.create({data:{
  purchaseOrderId:order.id,supplierId:supplier.id,
  subtotalPaise:5000n,taxPaise:900n,deliveryPaise:100n,totalPaise:6000n,platformFeePaise:0n
 }});
 await db.paymentAttempt.create({data:{
  purchaseOrderId:order.id,provider:'RAZORPAY',paymentMethod:'UPI',
  providerOrderRef:'secret_'+randomUUID(),idempotencyKey:'fixture-'+randomUUID(),
  status:'PENDING',amountPaise:6000n
 }});
 const api=request(app({ops:ops.clerkUserId,catalog:catalog.clerkUserId,customer:customer.clerkUserId}));
 const list=await get(api,'/api/v2/admin/orders?number='+order.publicNumber,'ops');
 assert.equal(list.status,200,JSON.stringify(list.body));
 assert.equal(list.body.data.items.length,1);
 assert.equal(list.body.data.items[0].publicNumber,order.publicNumber);
 const detail=await get(api,'/api/v2/admin/orders/'+order.id,'ops');
 assert.equal(detail.status,200,JSON.stringify(detail.body));
 assert.equal(detail.body.data.totalPaise,'6000');
 assert.equal(detail.body.data.supplierOrders[0].supplierName,'Safe Materials');
 assert.equal(detail.body.data.payments[0].status,'PENDING');
 assert.equal(detail.body.data.payments[0].capturedPaise,'0');
 assert.equal(detail.body.data.executionAllowed,false);
 const encoded=JSON.stringify(detail.body);
 assert(!encoded.includes('Do not disclose buyer'));
 assert(!encoded.includes('+919999999999'));
 assert(!encoded.includes('secret_'));
 assert.equal((await get(api,'/api/v2/admin/orders','catalog')).status,403);
 assert.equal((await get(api,'/api/v2/admin/orders','customer')).status,403);
 assert.equal((await api.get('/api/v2/admin/orders')).status,401);
 assert.equal((await get(api,'/api/v2/admin/orders?limit=999','ops')).status,400);
 assert.equal((await get(api,'/api/v2/admin/orders/invalid','ops')).status,404);
});
