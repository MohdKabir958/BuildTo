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
 assert.equal(created.body.data.status,'APPROVED');
 assert.equal(created.body.data.active,true);
 assert.ok(created.body.data.publishedAt);
 assert.equal(created.body.data.unitPrice,'315.25');
 assert.equal(created.body.data.mrpPaise,'39900');
 store.listingId=created.body.data.id;
 const replay=await send('post',url,'seller',base,{'Idempotency-Key':idempotency});
 assert.equal(replay.status,200);assert.equal(replay.body.replayed,true);
 assert.equal(replay.body.data.id,created.body.data.id);
 const changed=await send('post',url,'seller',{...base,unitPrice:'290.0000'},{'Idempotency-Key':idempotency});
 assert.equal(changed.status,409);
 const privateOther=await send('patch','/api/v2/suppliers/'+store.otherSupplier.id+'/listings/'+store.listingId,'seller',{
   expectedVersion:0,unitPrice:'1.0000'
 });
 assert.equal(privateOther.status,404);
 const outsiderEdit=await send('patch','/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId,'outsider',{
   expectedVersion:0,unitPrice:'1.0000'
 });
 assert.equal(outsiderEdit.status,404);
 const listingPublic=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(listingPublic.status,200);assert.equal(listingPublic.body.data.length,1);
});
test('supplier names a warehouse product and customers can see it without an admin product',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings';
 const created=await send('post',url,'seller',{
  productName:'Warehouse Cement 53',unitCode:'BAG',unitPrice:'250.0000',
  taxRateBps:1800,taxInclusive:true,
 },{'Idempotency-Key':key()});
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.status,'APPROVED');
 assert.equal(created.body.data.active,true);
 assert.equal(created.body.data.productName,'Warehouse Cement 53');
 const visible=await http.get('/api/v2/catalog/products?search=Warehouse%20Cement');
 assert.equal(visible.status,200);
 assert(visible.body.data.items.some(item=>item.name==='Warehouse Cement 53'));
});
test('supplier photo is saved with the product and can be opened',async()=>{
 const jpeg=Buffer.from([0xff,0xd8,0xff,0xd9]);
 const uploaded=await http.post('/api/v2/suppliers/'+store.supplier.id+'/product-photos')
  .set(H('seller')).set('Content-Type','image/jpeg').send(jpeg);
 assert.equal(uploaded.status,201,JSON.stringify(uploaded.body));
 const imageUrl=uploaded.body.data.imageUrl;
 const created=await send('post','/api/v2/suppliers/'+store.supplier.id+'/listings','seller',{
  productName:'Photo Cement',unitCode:'BAG',unitPrice:'10.0000',
  taxRateBps:1800,taxInclusive:true,imageUrl,
 },{'Idempotency-Key':key()});
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.imageUrl,imageUrl);
 const file=await http.get(imageUrl);
 assert.equal(file.status,200);
 assert.equal(file.headers['content-type'],'image/jpeg');
 const found=await http.get('/api/v2/catalog/products?search=Photo%20Cement');
 assert(found.body.data.items.some(item=>item.name==='Photo Cement'&&item.imageUrl===imageUrl));
 const gif=Buffer.concat([Buffer.from('GIF89a','ascii'),Buffer.from([0,0])]);
 const gifUpload=await http.post('/api/v2/suppliers/'+store.supplier.id+'/product-photos')
  .set(H('seller')).set('Content-Type','image/gif').send(gif);
 assert.equal(gifUpload.status,201,JSON.stringify(gifUpload.body));
 const heic=Buffer.alloc(16);
 heic.writeUInt32BE(16,0);heic.write('ftyp',4);heic.write('heic',8);
 const heicUpload=await http.post('/api/v2/suppliers/'+store.supplier.id+'/product-photos')
  .set(H('seller')).set('Content-Type','image/heic').send(heic);
 assert.equal(heicUpload.status,201,JSON.stringify(heicUpload.body));
 const junk=await http.post('/api/v2/suppliers/'+store.supplier.id+'/product-photos')
  .set(H('seller')).set('Content-Type','image/gif').send(Buffer.from('not-a-photo'));
 assert.equal(junk.status,415);
 const huge=Buffer.alloc(8*1024*1024+1,0);
 huge[0]=0xff;huge[1]=0xd8;huge[2]=0xff;
 const tooBig=await http.post('/api/v2/suppliers/'+store.supplier.id+'/product-photos')
  .set(H('seller')).set('Content-Type','image/jpeg').send(huge);
 assert.equal(tooBig.status,413);
});
test('verified supplier listings stay public through tier changes',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 let price=await send('put',url+'/price-tiers','seller',{
  expectedVersion:0,
  tiers:[{minQty:'5.000',pricePerUnit:'300.0000'},{minQty:'10.000',pricePerUnit:'290.0000'}]
 });
 assert.equal(price.status,200,JSON.stringify(price.body));
 assert.equal(price.body.data.version,1);
 assert.equal(price.body.data.status,'APPROVED');
 assert.equal(price.body.data.priceTiers.length,2);
 const submit=await send('post',url+'/submit','seller',{expectedVersion:1});
 assert.equal(submit.status,409);
 const pending=await send('get','/api/v2/admin/catalog/listings/pending','admin');
 assert.equal(pending.status,200);
 assert.equal(pending.body.data.some(x=>x.id===store.listingId),false);
 const publicItems=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(publicItems.status,200);
 const item=publicItems.body.data.find(x=>x.id===store.listingId);
 assert(item);assert.equal(item.priceTiers.length,2);
 assert.equal(item.priceTiers[0].pricePerUnit,'300');
 assert.equal(item.mrpPaise,'39900');
 assert.equal(item.unitPrice,'315.25');
 const audited=await db.auditEvent.count({where:{entityType:'SupplierListing',entityId:store.listingId}});
 assert(audited>=2);
});
test('optimistic version conflict keeps an edited price public',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 const stale=await send('patch',url,'seller',{expectedVersion:0,unitPrice:'310.0000'});
 assert.equal(stale.status,409);assert.equal(stale.body.error.code,'LISTING_VERSION_CONFLICT');
 const change=await send('patch',url,'seller',{expectedVersion:1,unitPrice:'305.0000'});
 assert.equal(change.status,200,JSON.stringify(change.body));
 assert.equal(change.body.data.status,'APPROVED');assert.equal(change.body.data.active,true);
 assert.equal(change.body.data.version,2);
 const visible=await http.get('/api/v2/catalog/listings?productId='+store.productId);
 assert.equal(visible.body.data.length,1);
 assert.equal(visible.body.data[0].unitPrice,'305');
 const invalid=await send('post',url+'/submit','seller',{expectedVersion:2});
 assert.equal(invalid.status,409);
});
test('a selling price below existing quantity prices is rejected until those prices are lowered',async()=>{
 const url='/api/v2/suppliers/'+store.supplier.id+'/listings/'+store.listingId;
 const current=await db.supplierListing.findUniqueOrThrow({where:{id:store.listingId}});
 const blocked=await send('patch',url,'seller',{
   expectedVersion:current.version,unitPrice:'280.0000'
 });
 assert.equal(blocked.status,422);
 assert.equal(blocked.body.error.code,'INVALID_PRICE_TIERS');
 const revised=await send('put',url+'/price-tiers','seller',{
   expectedVersion:current.version,
   tiers:[{minQty:'5.000',pricePerUnit:'270.0000'},{minQty:'10.000',pricePerUnit:'260.0000'}]
 });
 assert.equal(revised.status,200,JSON.stringify(revised.body));
 assert.equal(revised.body.data.status,'APPROVED');
 assert.equal(revised.body.data.version,current.version+1);
 const oldEdit=await send('patch',url,'seller',{
   expectedVersion:current.version,unitPrice:'280.0000'
 });
 assert.equal(oldEdit.status,409);
 const changed=await send('patch',url,'seller',{
   expectedVersion:revised.body.data.version,unitPrice:'280.0000'
 });
 assert.equal(changed.status,200,JSON.stringify(changed.body));
 assert.equal(changed.body.data.status,'APPROVED');
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
