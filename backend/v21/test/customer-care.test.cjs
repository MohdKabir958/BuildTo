'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {ApiError}=require('../dist/errors.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {createV21App}=require('../dist/app.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID(),sub=()=> 'user_'+id().replaceAll('-');
const key=()=> 'care_'+id().replaceAll('-');
const users={},tokens={},st={};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,limiter:new InMemoryTestLimiter(),
 log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session.');
  return {subject:tokens[token],sessionId:'sess_care_verified_1'};
 }}});
const api=request(app);
function send(method,path,actor,body,idem){
 let req=api[method](path);
 if(actor)req=req.set('Authorization','Bearer '+actor);
 if(idem)req=req.set('Idempotency-Key',idem);
 return body===undefined?req:req.send(body);
}
const orders=()=>'/api/v2/orders/'+st.order.id;
const sup=()=>'/api/v2/suppliers/'+st.supplier.id;
const returns=()=>orders()+'/returns';
const support=()=>'/api/v2/support/cases';
const reviews=()=>orders()+'/reviews';
const decimal=x=>new Prisma.Decimal(x);
test('fixture: delivered supplier lines, independent support and customer identity',async()=>{
 for(const role of ['customer','outsider','supplierStaff','finance','supportAdmin','conflictedAdmin','viewer']){
  const user=await db.user.create({data:{clerkUserId:sub(),displayName:'Care '+role}});
  users[role]=user;tokens[role]=user.clerkUserId;
 }
 st.supplier=await db.supplier.create({data:{slug:'care-'+id(),
  legalName:'Reliable Building Supply',displayName:'Building Supply',approval:'APPROVED',
  verifiedAt:new Date()}});
 await db.supplierMember.createMany({data:[
  {supplierId:st.supplier.id,userId:users.supplierStaff.id,role:'FULFILLMENT',active:true},
  {supplierId:st.supplier.id,userId:users.finance.id,role:'FINANCE',active:true},
  {supplierId:st.supplier.id,userId:users.conflictedAdmin.id,role:'MANAGER',active:true},
  {supplierId:st.supplier.id,userId:users.viewer.id,role:'VIEWER',active:true}
 ]});
 await db.adminMembership.createMany({data:[
  {userId:users.supportAdmin.id,role:'SUPPORT',active:true},
  {userId:users.conflictedAdmin.id,role:'SUPPORT',active:true}
 ]});
 st.order=await db.purchaseOrder.create({data:{
  customerId:users.customer.id,clientRequestId:key(),
  publicNumber:'BT-'+id().replaceAll('-').slice(0,24),status:'CONFIRMED',
  addressSnapshot:{recipientName:'Site Buyer',line1:'Site',city:'Hyderabad'},
  subtotalPaise:30000n,totalPaise:30000n
 }});
 st.child=await db.supplierOrder.create({data:{
  purchaseOrderId:st.order.id,supplierId:st.supplier.id,status:'DELIVERED',
  subtotalPaise:30000n,totalPaise:30000n
 }});
 st.line=await db.supplierOrderItem.create({data:{
  supplierOrderId:st.child.id,skuSnapshot:'CAR-001',nameSnapshot:'Bagged material',
  unitCode:'BAG',quantity:decimal('3.000'),packSizeSnapshot:decimal('1'),
  unitPrice:decimal('100'),taxRateBps:0,taxablePaise:30000n,
  taxPaise:0n,lineTotalPaise:30000n
 }});
 st.shipment=await db.shipment.create({data:{
  supplierOrderId:st.child.id,supplierId:st.supplier.id,
  shipmentNumber:'CARE-'+id().replaceAll('-').slice(0,24),
  status:'DELIVERED',deliveredAt:new Date(),
  handoverMethod:'APPROVED_EXCEPTION',exceptionApprovedById:users.supportAdmin.id,
  exceptionApprovedAt:new Date(),
  exceptionReason:'Verified recipient inspection and independent approved handover'
 }});
 await db.shipmentItem.create({data:{
  shipmentId:st.shipment.id,supplierOrderItemId:st.line.id,
  quantity:decimal('3'),deliveredQty:decimal('3')
 }});
 st.media=await db.mediaAsset.create({data:{
  objectKey:'returns/'+id(),mimeType:'image/jpeg',sizeBytes:512n,
  ownerUserId:users.customer.id
 }});
 st.foreignMedia=await db.mediaAsset.create({data:{
  objectKey:'returns/'+id(),mimeType:'image/jpeg',sizeBytes:512n,
  ownerUserId:users.outsider.id
 }});
 assert.equal((await db.purchaseOrder.findUniqueOrThrow({where:{id:st.order.id}})).status,'FULFILLED');
});
test('customer return is strictly owned, validates decimal quantities and media, replays same key',async()=>{
 const bad={supplierOrderId:st.child.id,reason:'Damaged packaging after delivery',
  items:[{orderItemId:st.line.id,quantity:'2.000'}]};
 assert.equal((await send('post',returns(),'outsider',bad,key())).status,404);
 assert.equal((await send('post',returns(),'customer',bad)).status,428);
 assert.equal((await send('post',returns(),'customer',{...bad,items:[
  {orderItemId:st.line.id,quantity:2}]},key())).status,400);
 assert.equal((await send('post',returns(),'customer',{
  ...bad,evidenceMediaIds:[st.foreignMedia.id]
 },key())).status,404);
 const requestBody={...bad,evidenceMediaIds:[st.media.id]};
 const k=key();
 const first=await send('post',returns(),'customer',requestBody,k);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.status,'REQUESTED');
 assert.equal(first.body.data.financialStatus,'NOT_REFUNDED');
 assert.equal(first.body.data.items[0].quantity,'2');
 st.returnId=first.body.data.id;
 const again=await send('post',returns(),'customer',requestBody,k);
 assert.equal(again.status,200,JSON.stringify(again.body));
 assert.equal(again.body.replayed,true);
 assert.equal(again.body.data.id,st.returnId);
 assert.equal((await send('post',returns(),'customer',{...requestBody,reason:'New reason, same key'},k)).status,409);
 assert.equal((await send('get',returns(),'customer')).body.data.length,1);
 assert.equal((await send('get',returns(),'outsider')).status,404);
 assert.equal((await send('get',sup()+'/orders/'+st.child.id+'/returns','viewer')).status,200);
 assert.equal((await send('get',sup()+'/orders/'+st.child.id+'/returns','outsider')).status,404);
 assert.equal((await db.refundRequest.count({where:{purchaseOrderId:st.order.id}})),0);
});
test('concurrent return attempts cannot claim more than physically delivered',async()=>{
 const body={supplierOrderId:st.child.id,reason:'Delivered materials have damaged outer wrapping',
  items:[{orderItemId:st.line.id,quantity:'1.000'}]};
 const attempts=await Promise.all([
  send('post',returns(),'customer',body,key()),
  send('post',returns(),'customer',body,key())
 ]);
 const statuses=attempts.map(a=>a.status).sort((a,b)=>a-b);
 assert.deepEqual(statuses,[201,409],JSON.stringify(attempts.map(x=>x.body)));
 st.smallReturnId=attempts.find(a=>a.status===201).body.data.id;
 const claims=await db.returnItem.findMany({where:{orderItem:{supplierOrderId:st.child.id}},
  select:{quantity:true}});
 assert.equal(claims.reduce((a,x)=>a.plus(x.quantity),decimal(0)).toString(),'3');
 const exceed=await send('post',returns(),'customer',body,key());
 assert.equal(exceed.status,409);
 assert.equal(exceed.body.error.code,'RETURN_QUANTITY_EXCEEDED');
});
test('independent review can approve; supplier can acknowledge receipt but never release money',async()=>{
 const endpoint='/api/v2/admin/returns/'+st.returnId+'/review';
 assert.equal((await send('post',endpoint,'supplierStaff',
  {decision:'APPROVE',note:'Supplier requested refund approval'})).status,403);
 assert.equal((await send('post',endpoint,'conflictedAdmin',
  {decision:'APPROVE',note:'Cannot independently approve own seller'})).status,403);
 assert.equal((await send('post',endpoint,'supportAdmin',
  {decision:'APPROVE',note:'Too short'})).status,400);
 const approval=await send('post',endpoint,'supportAdmin',{
  decision:'APPROVE',note:'Delivery photos confirm the damaged goods claim'
 });
 assert.equal(approval.status,200,JSON.stringify(approval.body));
 assert.equal(approval.body.data.status,'APPROVED');
 assert.equal(approval.body.data.financialStatus,'NOT_REFUNDED');
 assert.equal((await send('post','/api/v2/returns/'+st.returnId+'/cancel','customer',{})).status,409);
 assert.equal((await send('post',sup()+'/returns/'+st.returnId+'/receive',
  'viewer',{})).status,403);
 assert.equal((await send('post',sup()+'/returns/'+st.returnId+'/receive',
  'outsider',{})).status,404);
 const delivered=await send('post',sup()+'/returns/'+st.returnId+'/receive',
  'supplierStaff',{});
 assert.equal(delivered.status,200,JSON.stringify(delivered.body));
 assert.equal(delivered.body.data.status,'RECEIVED');
 const repeat=await send('post',sup()+'/returns/'+st.returnId+'/receive',
  'supplierStaff',{});
 assert.equal(repeat.status,200);assert.equal(repeat.body.data.replayed,true);
 assert.equal((await db.returnRequest.findUniqueOrThrow({where:{id:st.returnId}})).status,'RECEIVED');
 assert.equal((await db.refundRequest.count({where:{purchaseOrderId:st.order.id}})),0);
 assert.equal((await db.refundRequest.count({where:{purchaseOrderId:st.order.id}})),0,'No refund may be auto-released on physical receipt');
});
test('customer may cancel pending request to release its eligibility but not erase audit',async()=>{
 const r=await send('post','/api/v2/returns/'+st.smallReturnId+'/cancel','customer',{});
 assert.equal(r.status,200,JSON.stringify(r.body));
 assert.equal(r.body.data.status,'CANCELLED');
 const replay=await send('post','/api/v2/returns/'+st.smallReturnId+'/cancel','customer',{});
 assert.equal(replay.status,200);assert.equal(replay.body.data.replayed,true);
 const next=await send('post',returns(),'customer',{
  supplierOrderId:st.child.id,reason:'Another damaged unit physically delivered',
  items:[{orderItemId:st.line.id,quantity:'1.000'}]
 },key());
 assert.equal(next.status,201,JSON.stringify(next.body));
 st.lastReturnId=next.body.data.id;
 const rejected=await send('post','/api/v2/admin/returns/'+st.lastReturnId+'/review',
  'supportAdmin',{decision:'REJECT',note:'Photographs do not match this material delivery'});
 assert.equal(rejected.status,200);assert.equal(rejected.body.data.status,'REJECTED');
 assert.equal((await send('post',sup()+'/returns/'+st.lastReturnId+'/receive',
  'supplierStaff',{})).status,409);
});
test('support case requires customer-owned order and does not disclose cross-user content',async()=>{
 const body={orderId:st.order.id,subject:'Missing accessories from delivery',
  message:'Please investigate the missing accessories and document receipt.'};
 assert.equal((await send('post',support(),'outsider',body,key())).status,404);
 assert.equal((await send('post',support(),'customer',body)).status,428);
 const k=key();
 const first=await send('post',support(),'customer',body,k);
 assert.equal(first.status,201,JSON.stringify(first.body));
 st.caseId=first.body.data.id;
 const replay=await send('post',support(),'customer',body,k);
 assert.equal(replay.status,200);assert.equal(replay.body.data.id,st.caseId);
 assert.equal((await send('get',support()+'/x','customer')).status,404);
 assert.equal((await send('get',support()+'/'+st.caseId,'outsider')).status,404);
 assert.equal((await send('get',support(),'customer')).body.data.length,1);
 const admin=await send('get','/api/v2/admin/support/cases/'+st.caseId,'supportAdmin');
 assert.equal(admin.status,200,JSON.stringify(admin.body));
 assert.equal(admin.body.data.messages[0].internal,false);
 assert.equal((await send('get','/api/v2/admin/support/cases','supplierStaff')).status,403);
});
test('admin internal support notes never leak to customer, and customer cannot mark a message internal',async()=>{
 const url=support()+'/'+st.caseId;
 assert.equal((await send('post',url+'/messages','customer',
  {message:'private',internal:true})).status,400);
 assert.equal((await send('post','/api/v2/admin/support/cases/'+st.caseId+'/messages',
  'supplierStaff',{message:'Access denied',internal:true})).status,403);
 const note=await send('post','/api/v2/admin/support/cases/'+st.caseId+'/messages',
  'supportAdmin',{message:'Internal diagnostic only for care team',internal:true});
 assert.equal(note.status,200,JSON.stringify(note.body));
 assert.equal(note.body.data.internal,true);
 const customer=await send('get',url,'customer');
 assert.equal(customer.status,200,JSON.stringify(customer.body));
 assert.equal(customer.body.data.messages.length,1);
 assert(!JSON.stringify(customer.body).includes('Internal diagnostic'));
 const admin=await send('get','/api/v2/admin/support/cases/'+st.caseId,'supportAdmin');
 assert.equal(admin.body.data.messages.length,2);
});
test('support resolution is audited, customer response can reopen; closed cases are terminal',async()=>{
 const uri='/api/v2/admin/support/cases/'+st.caseId;
 assert.equal((await send('patch',uri,'supportAdmin',{status:'CLOSED',
  note:'Case closed without resolution note'})).status,409);
 assert.equal((await send('patch',uri,'supportAdmin',{status:'RESOLVED'})).status,400);
 const resolved=await send('patch',uri,'supportAdmin',{
  status:'RESOLVED',note:'Supplier confirmed shipment contents; attached delivery proof.'
 });
 assert.equal(resolved.status,200,JSON.stringify(resolved.body));
 assert.equal(resolved.body.data.status,'RESOLVED');
 const reopen=await send('post',support()+'/'+st.caseId+'/messages','customer',
  {message:'The accessories still have not been delivered.'});
 assert.equal(reopen.status,200,JSON.stringify(reopen.body));
 assert.equal((await send('get',support()+'/'+st.caseId,'customer')).body.data.status,'IN_PROGRESS');
 const resolveAgain=await send('patch',uri,'supportAdmin',{status:'RESOLVED',
  note:'Case has been reviewed again and supplier accepted the discrepancy.'});
 assert.equal(resolveAgain.status,200);
 const closed=await send('patch',uri,'supportAdmin',{status:'CLOSED',
  note:'Customer advised of the final support decision.'});
 assert.equal(closed.status,200);
 assert.equal((await send('post',support()+'/'+st.caseId+'/messages','customer',
  {message:'Late reply to closed case'})).status,409);
});
test('reviews are delivered-customer-only, private until independently published and never duplicate',async()=>{
 const body={supplierOrderId:st.child.id,rating:5,comment:'Good bulk material delivery overall.'};
 assert.equal((await send('post',reviews(),'outsider',body)).status,404);
 assert.equal((await send('post',reviews(),'customer',{...body,rating:4.5})).status,400);
 const first=await send('post',reviews(),'customer',body);
 assert.equal(first.status,201,JSON.stringify(first.body));
 st.reviewId=first.body.data.id;
 assert.equal(first.body.data.status,'PENDING');
 assert.equal((await send('post',reviews(),'customer',body)).status,409);
 assert.equal((await send('get',sup()+'/reviews')).body.data.length,0);
 assert.equal((await send('get',reviews(),'outsider')).status,404);
 assert.equal((await send('get',reviews(),'customer')).body.data.length,1);
 assert.equal((await send('get',sup()+'/reviews/manage','viewer')).body.data.length,1);
 assert.equal((await send('get','/api/v2/admin/reviews','supplierStaff')).status,403);
 assert.equal((await send('get','/api/v2/admin/reviews','supportAdmin')).body.data.length,1);
});
test('supplier-admin conflict cannot publish; independent moderation publishes and can hide',async()=>{
 const path='/api/v2/admin/reviews/'+st.reviewId+'/moderate';
 assert.equal((await send('post',path,'conflictedAdmin',{decision:'PUBLISH'})).status,403);
 const publish=await send('post',path,'supportAdmin',{decision:'PUBLISH'});
 assert.equal(publish.status,200,JSON.stringify(publish.body));
 assert.equal(publish.body.data.review.status,'PUBLISHED');
 const publicReview=await send('get',sup()+'/reviews');
 assert.equal(publicReview.status,200,JSON.stringify(publicReview.body));
 assert.equal(publicReview.body.data.length,1);
 assert.equal(publicReview.body.data[0].customerId,undefined,'Public reviews must not expose customer identity');
 assert.equal((await send('post',path,'supportAdmin',{decision:'PUBLISH'})).body.data.replayed,true);
 const hide=await send('post',path,'supportAdmin',{decision:'HIDE'});
 assert.equal(hide.status,200,JSON.stringify(hide.body));
 assert.equal((await send('get',sup()+'/reviews')).body.data.length,0);
 assert.equal((await send('get','/api/v2/admin/reviews','supportAdmin')).body.data.length,0);
});
