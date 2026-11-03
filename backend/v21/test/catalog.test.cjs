'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const request=require('supertest');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const id=()=>randomUUID();
const subject=()=> 'user_'+id().replaceAll('-','');
const slug=()=> 'ci-'+id();
const key=()=> 'catalog_'+id().replaceAll('-','');
const tokens={};
const application=createV21App({
 db,allowedOrigins:['https://staging.buildto.example'],proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
   if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid token.');
   return {subject:tokens[token],sessionId:'sess_testcode123456'};
 }}
});
const http=request(application);
const H=token=>({'Authorization':'Bearer '+token});
const send=(method,url,token,data,headers={})=>{
 let req=http[method](url);
 if(token)req=req.set('Authorization','Bearer '+token);
 for(const [k,v] of Object.entries(headers))req=req.set(k,v);
 return data===undefined?req:req.send(data);
};
const store={};
test('setup signed-user-equivalent fixture and create admin-owned category/brand/product',async()=>{
 const admin=await db.user.create({data:{clerkUserId:subject(),displayName:'Catalog Admin'}});
 const seller=await db.user.create({data:{clerkUserId:subject(),displayName:'Seller Manager'}});
 const outsider=await db.user.create({data:{clerkUserId:subject(),displayName:'Other Seller'}});
 const auditor=await db.user.create({data:{clerkUserId:subject(),displayName:'Auditor'}});
 await db.adminMembership.createMany({data:[
  {userId:admin.id,role:'CATALOG',active:true},{userId:auditor.id,role:'AUDITOR',active:true}
 ]});
 const supplier=await db.supplier.create({data:{
  slug:slug(),legalName:'Catalog Supplier Ltd',displayName:'Catalog Supplier',approval:'APPROVED'
 }});
 const otherSupplier=await db.supplier.create({data:{
  slug:slug(),legalName:'Other Supplier Ltd',displayName:'Other Supplier',approval:'APPROVED'
 }});
 await db.supplierMember.createMany({data:[
  {userId:seller.id,supplierId:supplier.id,active:true,role:'CATALOG'},
  {userId:outsider.id,supplierId:otherSupplier.id,active:true,role:'CATALOG'}
 ]});
 for(const [t,u] of Object.entries({admin,seller,outsider,auditor}))tokens[t]=u.clerkUserId;
 Object.assign(store,{admin,seller,outsider,auditor,supplier,otherSupplier});
 const category=await send('post','/api/v2/admin/catalog/categories','admin',{slug:slug(),name:'New Testing Materials'});
 assert.equal(category.status,201);assert.equal(category.body.data.active,false);
 store.categoryId=category.body.data.id;
 const brand=await send('post','/api/v2/admin/catalog/brands','admin',{slug:slug(),name:'Test Brand'});
 assert.equal(brand.status,201);store.brandId=brand.body.data.id;
 let product=await send('post','/api/v2/admin/catalog/products','admin',{
  code:'CT-'+id().slice(0,8).toUpperCase(),name:'Cement Test 53 Grade',
  categoryId:store.categoryId,brandId:store.brandId,
  specification:{grade:'53',fireResistant:false},
 });
 assert.equal(product.status,422);
 const activated=await send('patch','/api/v2/admin/catalog/categories/'+store.categoryId,'admin',{active:true});
 assert.equal(activated.status,200);
 product=await send('post','/api/v2/admin/catalog/products','admin',{
  code:'CT-'+id().slice(0,8).toUpperCase(),name:'Cement Test 53 Grade',
  categoryId:store.categoryId,brandId:store.brandId,hsnCode:'2523',
  specification:{grade:'53',fireResistant:false},
 });
 assert.equal(product.status,201);assert.equal(product.body.data.active,false);
 store.productId=product.body.data.id;
 const before=await http.get('/api/v2/catalog/products?categoryId='+store.categoryId);
 assert.equal(before.status,200);assert.equal(before.body.data.items.length,0);
 const publication=await send('patch','/api/v2/admin/catalog/products/'+store.productId,'admin',{active:true});
 assert.equal(publication.status,200);assert.equal(publication.body.data.active,true);
 const after=await http.get('/api/v2/catalog/products?categoryId='+store.categoryId);
 assert.equal(after.status,200);
 assert(after.body.data.items.some(p=>p.id===store.productId));
 assert.equal((await http.get('/api/v2/catalog/categories')).status,200);
 assert.equal((await http.get('/api/v2/catalog/brands')).status,200);
 assert.equal((await http.get('/api/v2/catalog/units')).status,200);
 const forbidden=await send('post','/api/v2/admin/catalog/brands','auditor',{slug:slug(),name:'Unapproved'});
 assert.equal(forbidden.status,403);
});
test('pricing rejects floats, missing keys, unsupported fields, cross supplier and role bypasses',async()=>{
 const supplierId=store.supplier.id;
 const base={
  productId:store.productId,sku:'CT-'+id().slice(0,8).toUpperCase(),
  unitCode:'BAG',packSize:'1.000',minOrderQty:'1.000',stepQty:'1.000',
  maxOrderQty:'500.000',unitPrice:'315.2500',mrpPaise:'39900',
  taxRateBps:1800,taxInclusive:true
 };
 const url='/api/v2/suppliers/'+supplierId+'/listings';
 assert.equal((await send('post',url,'seller',base)).status,428);
 assert.equal((await send('post',url,'seller',{...base,unitPrice:315.25},{'Idempotency-Key':key()})).status,400);
 assert.equal((await send('post',url,'seller',{...base,admin:true},{'Idempotency-Key':key()})).status,400);
 assert.equal((await send('post',url,'outsider',base,{'Idempotency-Key':key()})).status,404);
 const idempotency=key();
 const created=await send('post',url,'seller',base,{'Idempotency-Key':idempotency});
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.status,'DRAFT');
 assert.equal(created.body.data.unitPrice,'315.25');
 assert.equal(created.body.data.mrpPaise,'39900');
 store.listingId=created.body.data.id;
 const replay=await send('post',url,'seller',base,{'Idempotency-Key':idempotency});
 assert.equal(replay.status,200);assert.equal(replay.body.replayed,true);
 assert.equal(replay.body.data.id,created.body.data.id);
 const changed=await send('post',url,'seller',{...base,unitPrice:'290.0000'},{'Idempotency-Key':idempotency});
 assert.equal(changed.status,409);
 const privateOther=await send('get','/api/v2/suppliers/'+store.otherSupplier.id+'/listings/'+store.listingId,'seller');
 assert.equal(privateOther.status,404);
 const listingPublic=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(listingPublic.status,200);assert.equal(listingPublic.body.data.length,0);
});
test('supplier can replace tiers, submit; admin approves; exact prices only visible when published',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 let price=await send('put',url+'/price-tiers','seller',{
  expectedVersion:0,
  tiers:[{minQty:'5.000',pricePerUnit:'300.0000'},{minQty:'10.000',pricePerUnit:'290.0000'}]
 });
 assert.equal(price.status,200,JSON.stringify(price.body));
 assert.equal(price.body.data.version,1);
 assert.equal(price.body.data.priceTiers.length,2);
 const submit=await send('post',url+'/submit','seller',{expectedVersion:1});
 assert.equal(submit.status,200);assert.equal(submit.body.data.status,'PENDING');
 const pre=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(pre.body.data.length,0);
 const pending=await send('get','/api/v2/admin/catalog/listings/pending','admin');
 assert.equal(pending.status,200);
 assert(pending.body.data.some(x=>x.id===store.listingId));
 const approve=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{decision:'APPROVE',expectedVersion:2});
 assert.equal(approve.status,200,JSON.stringify(approve.body));
 assert.equal(approve.body.data.version,3);
 assert.equal(approve.body.data.status,'APPROVED');
 const publicItems=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(publicItems.status,200);
 const item=publicItems.body.data.find(x=>x.id===store.listingId);
 assert(item);assert.equal(item.priceTiers.length,2);
 assert.equal(item.priceTiers[0].pricePerUnit,'300');
 assert.equal(item.mrpPaise,'39900');
 assert.equal(item.unitPrice,'315.25');
 const audited=await db.auditEvent.count({where:{entityType:'SupplierListing',entityId:store.listingId}});
 assert(audited>=3);
});
test('optimistic version conflict and repricing unpublish approved listing',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 const stale=await send('patch',url,'seller',{expectedVersion:2,unitPrice:'310.0000'});
 assert.equal(stale.status,409);assert.equal(stale.body.error.code,'LISTING_VERSION_CONFLICT');
 const change=await send('patch',url,'seller',{expectedVersion:3,unitPrice:'305.0000'});
 assert.equal(change.status,200,JSON.stringify(change.body));
 assert.equal(change.body.data.status,'PENDING');assert.equal(change.body.data.active,false);
 assert.equal(change.body.data.version,4);
 const invisible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(invisible.body.data.length,0);
 const invalid=await send('post',url+'/submit','seller',{expectedVersion:4});
 assert.equal(invalid.status,409);
 const approve=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{
  decision:'APPROVE',expectedVersion:4
 });
 assert.equal(approve.status,200);
 const visible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(visible.body.data.length,1);
 assert.equal(visible.body.data[0].unitPrice,'305');
});
test('a lower base price cannot be approved with stale higher tiers; re-tier while pending',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 const current=await db.supplierListing.findUniqueOrThrow({where:{id:store.listingId}});
 const changed=await send('patch',url,'seller',{
   expectedVersion:current.version,unitPrice:'280.0000'
 });
 assert.equal(changed.status,200);
 assert.equal(changed.body.data.status,'PENDING');
 const rejected=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{
   expectedVersion:changed.body.data.version,decision:'APPROVE'
 });
 assert.equal(rejected.status,422);
 assert.equal(rejected.body.error.code,'INVALID_PRICE_TIERS');
 const revised=await send('put',url+'/price-tiers','seller',{
   expectedVersion:changed.body.data.version,
   tiers:[{minQty:'5.000',pricePerUnit:'270.0000'},{minQty:'10.000',pricePerUnit:'260.0000'}]
 });
 assert.equal(revised.status,200,JSON.stringify(revised.body));
 assert.equal(revised.body.data.status,'PENDING');
 assert.equal(revised.body.data.version,changed.body.data.version+1);
 const oldEdit=await send('patch',url,'seller',{
   expectedVersion:changed.body.data.version,unitPrice:'280.0000'
 });
 assert.equal(oldEdit.status,409);
 const approved=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{
   expectedVersion:revised.body.data.version,decision:'APPROVE'
 });
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 const visible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 const listing=visible.body.data.find(x=>x.id===store.listingId);
 assert(listing);
 assert.equal(listing.unitPrice,'280');
 assert.deepEqual(listing.priceTiers.map(x=>x.pricePerUnit),['270','260']);
});

test('suspending supplier or listing makes it disappear from public catalog',async()=>{
 const row=await db.supplierListing.findUniqueOrThrow({where:{id:store.listingId}});
 const reject=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{
  decision:'REJECT',expectedVersion:row.version
 });
 assert.equal(reject.status,409);
 await db.supplier.update({where:{id:store.supplier.id},data:{approval:'SUSPENDED',suspendedAt:new Date()}});
 let visible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(visible.body.data.length,0);
 const blocked=await send('patch','/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId,'seller',{
  expectedVersion:row.version,unitPrice:'299.0000'
 });
 assert.equal(blocked.status,404);
 await db.supplier.update({where:{id:store.supplier.id},data:{approval:'APPROVED',suspendedAt:null}});
 const suspend=await send('post','/api/v2/admin/catalog/listings/'+store.listingId+'/review','admin',{
  decision:'SUSPEND',expectedVersion:row.version
 });
 assert.equal(suspend.status,200);
 visible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(visible.body.data.length,0);
});
test('product conversion accepts exact non-floating multiplier and rejects identical units',async()=>{
 const url='/api/v2/admin/catalog/products/'+store.productId+'/conversions';
 const bad=await send('post',url,'admin',{fromUnit:'BAG',toUnit:'BAG',multiplier:'50.000000000'});
 assert.equal(bad.status,400);
 const good=await send('post',url,'admin',{fromUnit:'BAG',toUnit:'KG',multiplier:'50.000000000'});
 assert.equal(good.status,201,JSON.stringify(good.body));
 assert.equal(good.body.data.multiplier,'50');
});
test('category cannot deactivate while active products remain',async()=>{
 const url='/api/v2/admin/catalog/categories/'+store.categoryId;
 const disabled=await send('patch',url,'admin',{active:false});
 assert.equal(disabled.status,409);
 const change=await send('patch','/api/v2/admin/catalog/products/'+store.productId,'admin',{active:false});
 assert.equal(change.status,200);
 const done=await send('patch',url,'admin',{active:false});
 assert.equal(done.status,200);
});
