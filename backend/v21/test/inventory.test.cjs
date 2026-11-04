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
const {holdOrderItemStock,releaseOrderItemStock,commitOrderItemStock}=require('../dist/inventory-reservations.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const uid=()=>randomUUID(),sub=()=> 'user_'+uid().replaceAll('-','');
const tokens={};const store={};
const app=createV21App({db,allowedOrigins:[],proxyHops:0,limiter:new InMemoryTestLimiter(),
 log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session.');
  return {subject:tokens[token],sessionId:'sess_test123456789'};
 }}});
const http=request(app);
function send(method,url,token,body,key){
 let req=http[method](url);
 if(token)req=req.set('Authorization','Bearer '+token);
 if(key)req=req.set('Idempotency-Key',key);
 return body===undefined?req:req.send(body);
}
const key=()=> 'stock_'+uid().replaceAll('-','');
const url=()=>'/api/v2/suppliers/'+store.supplier.id+'/inventory';
const balance=async(listingId,warehouseId)=>db.inventoryBalance.findUniqueOrThrow({
 where:{listingId_warehouseId:{listingId,warehouseId}}
});
const purchase=async(qty)=>{
 const parent=await db.purchaseOrder.create({data:{
   publicNumber:'CI-'+uid().replaceAll('-').slice(0,28),
   customerId:store.buyer.id,clientRequestId:'ci_'+uid(),currency:'INR',
   addressSnapshot:{line1:'CI Test Address',postalCode:'500001'},
   subtotalPaise:100000n,taxPaise:0n,totalPaise:100000n,
 }});
 const so=await db.supplierOrder.create({data:{
   purchaseOrderId:parent.id,supplierId:store.supplier.id,
   subtotalPaise:100000n,totalPaise:100000n,
 }});
 const item=await db.supplierOrderItem.create({data:{
  supplierOrderId:so.id,listingId:store.listing.id,skuSnapshot:store.listing.sku,
  nameSnapshot:'Test Cement',unitCode:'BAG',packSizeSnapshot:new Prisma.Decimal('1.000'),
  quantity:new Prisma.Decimal(qty),unitPrice:new Prisma.Decimal('100.0000'),taxRateBps:0,
  taxablePaise:100000n,taxPaise:0n,lineTotalPaise:100000n
 }});
 return item;
};
test('setup supplier, draft-free approved listing, warehouse owner and viewer fixtures',async()=>{
 const users={};
 for(const name of ['owner','viewer','outsider','buyer']){
  users[name]=await db.user.create({data:{clerkUserId:sub(),displayName:'Stock '+name}});
  tokens[name]=users[name].clerkUserId;
 }
 const supplier=await db.supplier.create({data:{
  slug:'stock-'+uid(),displayName:'Stock Supplier',legalName:'Stock Supplier Ltd',approval:'APPROVED'
 }});
 const other=await db.supplier.create({data:{
  slug:'stock-'+uid(),displayName:'Other Supplier',legalName:'Other Supplier Ltd',approval:'APPROVED'
 }});
 await db.supplierMember.createMany({data:[
  {supplierId:supplier.id,userId:users.owner.id,role:'INVENTORY',active:true},
  {supplierId:supplier.id,userId:users.viewer.id,role:'VIEWER',active:true},
  {supplierId:other.id,userId:users.outsider.id,role:'OWNER',active:true},
 ]});
 const category=await db.category.create({data:{
  slug:'stock-'+uid(),name:'Stock Test Materials',active:true,
 }});
 const product=await db.product.create({data:{
  code:'ST-'+uid().replaceAll('-').slice(0,20).toUpperCase(),name:'Stock Test Cement',
  categoryId:category.id,active:true,
 }});
 const listing=await db.supplierListing.create({data:{
  supplierId:supplier.id,productId:product.id,sku:'ST-'+uid().replaceAll('-').slice(0,20).toUpperCase(),
  unitCode:'BAG',status:'APPROVED',active:true,publishedAt:new Date(),
  unitPrice:new Prisma.Decimal('100.0000'),taxRateBps:0
 }});
 Object.assign(store,{...users,supplier,other,category,product,listing});
 const missing=await send('get',url()+'/warehouses',null);
 assert.equal(missing.status,401);
 const foreign=await send('get',url()+'/warehouses','outsider');
 assert.equal(foreign.status,404);
 const limited=await send('post',url()+'/warehouses','viewer',{code:'MAIN',name:'No permission'});
 assert.equal(limited.status,403);
 const first=await send('post',url()+'/warehouses','owner',{
  code:'MAIN',name:'Main Warehouse',
  address:{line1:'Plot 1',locality:'Hyderabad',city:'Hyderabad',stateCode:'TG',postalCode:'500001'}
 });
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.active,false);
 store.firstId=first.body.data.id;
 const second=await send('post',url()+'/warehouses','owner',{code:'SECOND',name:'Second Warehouse'});
 assert.equal(second.status,201,JSON.stringify(second.body));
 store.secondId=second.body.data.id;
 const unauthorized=await send('patch',url()+'/warehouses/'+store.firstId,'outsider',{active:true});
 assert.equal(unauthorized.status,404);
 for(const warehouseId of [store.firstId,store.secondId]){
  const enabled=await send('patch',url()+'/warehouses/'+warehouseId,'owner',{active:true});
  assert.equal(enabled.status,200);assert.equal(enabled.body.data.active,true);
 }
 assert.equal((await send('get',url()+'/warehouses','viewer')).body.data.length,2);
});
test('stock receipt uses exact Decimal quantity, optimistic version and idempotency',async()=>{
 const receipt={
   listingId:store.listing.id,warehouseId:store.firstId,
   kind:'RECEIPT',delta:'10.500',reason:'Initial stock count',expectedVersion:0
 };
 assert.equal((await send('post',url()+'/adjustments','owner',receipt)).status,428);
 assert.equal((await send('post',url()+'/adjustments','viewer',receipt,key())).status,403);
 assert.equal((await send('post',url()+'/adjustments','outsider',receipt,key())).status,404);
 assert.equal((await send('post',url()+'/adjustments','owner',{...receipt,delta:10.5},key())).status,400);
 assert.equal((await send('post',url()+'/adjustments','owner',{...receipt,kind:'SALE'},key())).status,400);
 assert.equal((await send('post',url()+'/adjustments','owner',{...receipt,warehouseId:store.secondId,admin:true},key())).status,400);
 const idem=key();
 const first=await send('post',url()+'/adjustments','owner',receipt,idem);
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.currentBalance.onHandQty,'10.5');
 assert.equal(first.body.data.currentBalance.availableQty,'10.5');
 assert.equal(first.body.data.currentBalance.version,1);
 store.receiptId=first.body.data.movementId;
 const again=await send('post',url()+'/adjustments','owner',receipt,idem);
 assert.equal(again.status,200);
 assert.equal(again.body.data.replayed,true);
 assert.equal(again.body.data.movementId,store.receiptId);
 assert.equal((await db.stockMovement.count({where:{balance:{listingId:store.listing.id,
   warehouseId:store.firstId}}})),1);
 const changed=await send('post',url()+'/adjustments','owner',{...receipt,delta:'11.000'},idem);
 assert.equal(changed.status,409);
 assert.equal(changed.body.error.code,'IDEMPOTENCY_KEY_REUSED');
 const stale=await send('post',url()+'/adjustments','owner',{...receipt,delta:'1.000'},key());
 assert.equal(stale.status,409);
 assert.equal(stale.body.error.code,'STOCK_VERSION_CONFLICT');
});
test('transfer is atomic, balances conserved, history paired and retries safe',async()=>{
 const payload={listingId:store.listing.id,fromWarehouseId:store.firstId,
  toWarehouseId:store.secondId,quantity:'4.500',reason:'Supplier delivery staging',
  expectedFromVersion:1,expectedToVersion:0};
 const first=await send('post',url()+'/transfers','owner',payload,key());
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.quantity,'4.5');
 const [a,c]=await Promise.all([balance(store.listing.id,store.firstId),balance(store.listing.id,store.secondId)]);
 assert.equal(a.onHandQty.toString(),'6');
 assert.equal(c.onHandQty.toString(),'4.5');
 assert.equal(a.onHandQty.plus(c.onHandQty).toString(),'10.5');
 const againKey=key();
 const transferTwo={...payload,quantity:'0.500',expectedFromVersion:2,expectedToVersion:1};
 const transfer=await send('post',url()+'/transfers','owner',transferTwo,againKey);
 assert.equal(transfer.status,201);
 const replay=await send('post',url()+'/transfers','owner',transferTwo,againKey);
 assert.equal(replay.status,200);
 assert.equal(replay.body.data.replayed,true);
 assert.equal(replay.body.data.transferOutId,transfer.body.data.transferOutId);
 const updated=await balance(store.listing.id,store.firstId);
 const target=await balance(store.listing.id,store.secondId);
 assert.equal(updated.onHandQty.toString(),'5.5');
 assert.equal(target.onHandQty.toString(),'5');
 const movements=await send('get',url()+'/warehouses/'+store.firstId+'/movements','owner');
 assert.equal(movements.status,200);
 assert(movements.body.data.some(row=>row.kind==='TRANSFER_OUT'&&row.delta==='-4.5'));
 const foreign=await send('post','/api/v2/suppliers/'+store.other.id+'/inventory/transfers',
   'owner',transferTwo,key());
 assert.equal(foreign.status,404);
});
test('negative adjustment cannot consume reserved stock; active stock blocks warehouse deactivation',async()=>{
 const current=await balance(store.listing.id,store.firstId);
 const over=await send('post',url()+'/adjustments','owner',{
  listingId:store.listing.id,warehouseId:store.firstId,kind:'DAMAGE',
  delta:'-6.000',reason:'Breakage count',expectedVersion:current.version
 },key());
 assert.equal(over.status,409);
 const valid=await send('post',url()+'/adjustments','owner',{
  listingId:store.listing.id,warehouseId:store.firstId,kind:'DAMAGE',
  delta:'-0.500',reason:'Breakage count',expectedVersion:current.version
 },key());
 assert.equal(valid.status,201,JSON.stringify(valid.body));
 assert.equal(valid.body.data.currentBalance.onHandQty,'5');
 assert.equal((await send('patch',url()+'/warehouses/'+store.firstId,'owner',{active:false})).status,409);
 const viewer=await send('get',url()+'/balances?listingId='+store.listing.id,'viewer');
 assert.equal(viewer.status,200);
 assert.equal(viewer.body.data.length,2);
 assert(viewer.body.data.every(x=>typeof x.onHandQty==='string'));
});
test('transactional order-item holds respect supplier ownership, stock and purchased qty',async()=>{
 const line=await purchase('5.000');
 store.itemId=line.id;
 const first=await serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.supplier.id,orderItemId:line.id,warehouseId:store.firstId,
  quantity:'3.000',expiresAt:new Date(Date.now()+10*60_000)
 }));
 assert.equal(first.replayed,false);
 store.holdId=first.reservationId;
 const repeat=await serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.supplier.id,orderItemId:line.id,warehouseId:store.firstId,
  quantity:'3.000',expiresAt:new Date(Date.now()+10*60_000)
 }));
 assert.equal(repeat.replayed,true);
 assert.equal(repeat.reservationId,first.reservationId);
 const denied=await assert.rejects(serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.other.id,orderItemId:line.id,warehouseId:store.secondId,
  quantity:'1.000',expiresAt:new Date(Date.now()+10*60_000)
 })),e=>e.status===404);
 const extra=await serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.supplier.id,orderItemId:line.id,warehouseId:store.secondId,
  quantity:'2.000',expiresAt:new Date(Date.now()+10*60_000)
 }));
 store.secondHold=extra.reservationId;
 await assert.rejects(serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.supplier.id,orderItemId:line.id,warehouseId:store.secondId,
  quantity:'3.000',expiresAt:new Date(Date.now()+10*60_000)
 })),e=>e.status===409);
 const src=await balance(store.listing.id,store.firstId);
 assert.equal(src.onHandQty.toString(),'5');
 assert.equal(src.reservedQty.toString(),'3');
 assert.equal(src.onHandQty.minus(src.reservedQty).toString(),'2');
 assert.equal((await send('post',url()+'/reservations','owner',{
   orderItemId:line.id,quantity:'3.000'
 })).status,404);
});
test('reserved stock cannot be damaged/transferred; release and sale commit exactly once',async()=>{
 const current=await balance(store.listing.id,store.firstId);
 const bad=await send('post',url()+'/adjustments','owner',{
  listingId:store.listing.id,warehouseId:store.firstId,
  kind:'DAMAGE',delta:'-2.500',reason:'Damaged material',expectedVersion:current.version
 },key());
 assert.equal(bad.status,409);
 const released=await serializable(db,tx=>releaseOrderItemStock(tx,store.holdId));
 assert.equal(released.state,'RELEASED');
 assert.equal((await serializable(db,tx=>releaseOrderItemStock(tx,store.holdId))).replayed,true);
 await assert.rejects(serializable(db,tx=>commitOrderItemStock(tx,store.holdId)),
  e=>e.status===409);
 const committed=await serializable(db,tx=>commitOrderItemStock(tx,store.secondHold));
 assert.equal(committed.state,'COMMITTED');
 assert.equal((await serializable(db,tx=>commitOrderItemStock(tx,store.secondHold))).replayed,true);
 const sale=await db.stockMovement.findUnique({where:{referenceKey:'sale:'+store.secondHold}});
 assert(sale);assert.equal(sale.kind,'SALE');assert.equal(sale.delta.toString(),'-2');
 const dst=await balance(store.listing.id,store.secondId);
 assert.equal(dst.reservedQty.toString(),'0');
 assert.equal(dst.onHandQty.toString(),'3');
 assert.equal(await db.stockMovement.count({where:{referenceKey:'sale:'+store.secondHold}}),1);
});
test('two simultaneous checkout transactions never oversell the same balance',async()=>{
 const [lineOne,lineTwo]=await Promise.all([purchase('4.000'),purchase('4.000')]);
 const cmd=id=>serializable(db,tx=>holdOrderItemStock(tx,{
  supplierId:store.supplier.id,orderItemId:id,warehouseId:store.firstId,
  quantity:'4.000',expiresAt:new Date(Date.now()+20*60_000)
 }));
 const results=await Promise.allSettled([cmd(lineOne.id),cmd(lineTwo.id)]);
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1,JSON.stringify(results.map(x=>x.status)));
 assert.equal(results.filter(x=>x.status==='rejected').length,1);
 const current=await balance(store.listing.id,store.firstId);
 assert(current.reservedQty.lte(current.onHandQty));
 assert.equal(current.reservedQty.toString(),'4');
 assert.equal(current.onHandQty.toString(),'5');
 const winner=results.find(x=>x.status==='fulfilled');
 await serializable(db,tx=>releaseOrderItemStock(tx,winner.value.reservationId,'EXPIRED'));
 const clear=await balance(store.listing.id,store.firstId);
 assert.equal(clear.reservedQty.toString(),'0');
});
test('stock movement and audit are append-only database records',async()=>{
 await assert.rejects(db.stockMovement.delete({where:{id:store.receiptId}}));
 assert.equal(await db.stockMovement.count({where:{id:store.receiptId}}),1);
 assert((await db.auditEvent.count({where:{action:{startsWith:'STOCK_'}}}))>=2);
});
