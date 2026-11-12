'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const request=require('supertest');
const sharp=require('sharp');
const {PrismaClient,Prisma}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app');
const {InMemoryTestLimiter}=require('../dist/rateLimit');
const {ApiError}=require('../dist/errors');
const {assertAuthorizedParty}=require('../dist/identity');
const {calculateFreight}=require('../dist/freight');
const db=new PrismaClient(),tokens={},files=new Map(),state={};
const store={put:async(k,b)=>{files.set(k,b)},get:async k=>files.get(k),remove:async k=>{files.delete(k)}};
const api=request(createV21App({db,mediaStore:store,deviceEncryptionKey:Buffer.alloc(32,7).toString("base64"),allowedOrigins:['https://supplier.example'],proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Sign in');return {subject:tokens[token],sessionId:'sess_business1234'};}}}));
const call=(method,path,actor,body)=>{let r=api[method](path).set('Authorization','Bearer '+actor);return body===undefined?r:r.send(body)};
test.after(()=>db.$disconnect());
test('authentication origin policy: native opt-in is explicit; foreign and malformed origins never pass',()=>{
 const options={authorizedParties:['https://supplier.example']};
 assert.doesNotThrow(()=>assertAuthorizedParty('https://supplier.example',options));
 for(const party of [undefined,null,123,'','https://attacker.example'])assert.throws(()=>assertAuthorizedParty(party,options),e=>e.status===401);
 assert.doesNotThrow(()=>assertAuthorizedParty(undefined,{...options,allowNativeWithoutAzp:true}));
 assert.throws(()=>assertAuthorizedParty('https://attacker.example',{...options,allowNativeWithoutAzp:true}),e=>e.status===401);
});
test('fixture: independent identities, active catalog and city',async()=>{
 for(const name of ['owner','other','admin']){
  const u=await db.user.create({data:{clerkUserId:'user_'+randomUUID().replaceAll('-',''),displayName:name,email:randomUUID()+'@test.example'}});
  state[name]=u;tokens[name]=u.clerkUserId;
 }
 await db.adminMembership.create({data:{userId:state.admin.id,role:'OWNER',active:true}});
 state.city=await db.city.create({data:{code:'BC'+randomUUID().slice(0,8).toUpperCase(),name:'Completion City',stateCode:'TS',active:true}});
 state.category=await db.category.create({data:{slug:'bc-'+randomUUID(),name:'Materials',active:true}});
 state.product=await db.product.create({data:{code:'BC'+randomUUID().slice(0,12),categoryId:state.category.id,name:'Cement',active:true}});
});
test('private uploads validate actual bytes; only owner or independent linked reviewer can read',async()=>{
 assert.equal((await api.post('/api/v2/media').send({})).status,401);
 const body={purpose:'EVIDENCE',mimeType:'image/png',base64:Buffer.from('<script>bad</script>').toString('base64')};
 assert.equal((await call('post','/api/v2/media','owner',body)).status,400);
 const png=await sharp({create:{width:2,height:2,channels:3,background:'white'}}).png().toBuffer();
 const uploaded=await call('post','/api/v2/media','owner',{...body,base64:png.toString('base64')});
 assert.equal(uploaded.status,201,JSON.stringify(uploaded.body));state.mediaId=uploaded.body.data.id;
 assert.equal((await call('get','/api/v2/media/'+state.mediaId,'other')).status,404);
 assert.equal((await call('get','/api/v2/media/'+state.mediaId,'admin')).status,404);
 const own=await call('get','/api/v2/media/'+state.mediaId,'owner');assert.equal(own.status,200);assert.match(own.headers['content-disposition'],/^attachment/);
 assert(!JSON.stringify(uploaded.body).includes('objectKey'));
 const pdf=await call('post','/api/v2/media','owner',{purpose:'EVIDENCE',mimeType:'application/pdf',base64:Buffer.from('not a pdf').toString('base64')});assert.equal(pdf.status,400);
});
test('catalog image publication requires catalog authority and cannot publish private KYC assets',async()=>{
 const path='/api/v2/admin/catalog/products/'+state.product.id+'/images/';
 assert.equal((await call('put',path+state.mediaId,'admin',{position:0})).status,404);
 assert.equal((await call('post','/api/v2/media','owner',{purpose:'CATALOG_IMAGE',mimeType:'image/png',base64:'eA=='})).status,403);
 const png=await sharp({create:{width:2,height:2,channels:3,background:'red'}}).png().toBuffer();
 const uploaded=await call('post','/api/v2/media','admin',{purpose:'CATALOG_IMAGE',mimeType:'image/png',base64:png.toString('base64')});
 assert.equal(uploaded.status,201,JSON.stringify(uploaded.body));const id=uploaded.body.data.id;
 assert.equal((await api.get('/api/v2/catalog/images/'+id)).status,404);
 assert.equal((await call('put',path+id,'admin',{position:0})).status,200);
 assert.equal((await api.get('/api/v2/catalog/images/'+id)).status,200);
 const products=await api.get('/api/v2/catalog/products?search=Cement');
 assert(products.body.data.items.some(p=>p.id===state.product.id&&p.images.some(x=>x.id===id)));
 await call('delete',path+id,'admin');assert.equal((await api.get('/api/v2/catalog/images/'+id)).status,404);
});
test('project/site CRUD enforces ownership and archives referenced records instead of deleting history',async()=>{
 const project=await call('post','/api/v2/me/projects','owner',{name:'House build'});assert.equal(project.status,201);const projectId=project.body.data.id;
 assert.equal((await call('patch','/api/v2/me/projects/'+projectId,'other',{name:'stolen'})).status,404);
 const address=await db.address.create({data:{userId:state.owner.id,cityId:state.city.id,label:'Site',recipientName:'Buyer',phoneE164:'+919876543210',line1:'Road 12',locality:'Town',postalCode:'500001'}});
 assert.equal((await call('post','/api/v2/me/sites','other',{name:'Foreign site',projectId,addressId:address.id})).status,404);
 const site=await call('post','/api/v2/me/sites','owner',{name:'Main site',projectId,addressId:address.id});assert.equal(site.status,201,JSON.stringify(site.body));
 assert.equal((await call('get','/api/v2/me/projects/'+projectId,'other')).status,404);
 assert.equal((await call('get','/api/v2/me/projects/'+projectId,'owner')).body.data.sites.length,1);
 await call('delete','/api/v2/me/projects/'+projectId,'owner');
 assert.equal((await call('post','/api/v2/me/sites','owner',{name:'Archived site',projectId,addressId:address.id})).status,404);
 const disabled=await call('delete','/api/v2/me/sites/'+site.body.data.id,'owner');assert.equal(disabled.body.data.active,false);
 assert(await db.constructionSite.findUnique({where:{id:site.body.data.id}}));
});
test('RFQ freight prices verified cargo conversions and multiple trips; persisted snapshot agrees with quote',async()=>{
 state.supplier=await db.supplier.create({data:{slug:'bc-'+randomUUID(),displayName:'Materials',legalName:'Materials Ltd',approval:'APPROVED'}});
 await db.supplierMember.create({data:{supplierId:state.supplier.id,userId:state.owner.id,role:'OWNER',active:true}});
 const area=await db.serviceArea.create({data:{cityId:state.city.id,name:'City',postalCodes:['500001'],active:true}});
 await db.supplierServiceArea.create({data:{supplierId:state.supplier.id,areaId:area.id,active:true}});
 await db.productUnitConversion.create({data:{productId:state.product.id,fromUnit:'BAG',toUnit:'KG',multiplier:new Prisma.Decimal(50)}});
 const configured=await call('put',`/api/v2/suppliers/${state.supplier.id}/delivery/areas/${area.id}/freight-rate`,'owner',{baseFeePaise:'1000',handlingFeePaise:'100',perKmPaise:'100',perTonneKmPaise:'10',weightCapacityKg:'500',vehicleClass:'Small truck'});
 assert.equal(configured.status,200,JSON.stringify(configured.body));
 const rfq=await db.rfq.create({data:{publicNumber:'RFQ-'+randomUUID().slice(0,20),customerId:state.other.id,status:'OPEN',siteSnapshot:{city:state.city.name,postalCode:'500001'},items:{create:{productId:state.product.id,description:'Cement',quantity:new Prisma.Decimal(20),unitCode:'BAG'}}},include:{items:true}});
 await db.rfqInvitation.create({data:{rfqId:rfq.id,supplierId:state.supplier.id}});
 const body={lines:[{rfqItemId:rfq.items[0].id,quantity:'20',unitCode:'BAG',unitPrice:'100',taxRateBps:0}],freight:{rateId:configured.body.data.id,roadDistanceKm:'10',distanceEvidence:'Supplier verified road route from depot to site'}};
 const quote=await api.post(`/api/v2/suppliers/${state.supplier.id}/rfqs/${rfq.id}/quotes`).set('Authorization','Bearer owner').set('Idempotency-Key',randomUUID()).send(body);
 assert.equal(quote.status,201,JSON.stringify(quote.body));
 const snapshot=quote.body.data.freightSnapshot;assert.equal(snapshot.trips,2);assert.equal(snapshot.weightKg,'1000');assert.equal(snapshot.amountPaise,'4300');assert.equal(quote.body.data.deliveryPaise,'4300');
 const unknown=await db.product.create({data:{code:'UNKNOWN-'+randomUUID(),categoryId:state.category.id,name:'Unknown mass',active:true}});
 await db.rfqItem.update({where:{id:rfq.items[0].id},data:{productId:unknown.id}});
 const invalid=await api.post(`/api/v2/suppliers/${state.supplier.id}/rfqs/${rfq.id}/quotes`).set('Authorization','Bearer owner').set('Idempotency-Key',randomUUID()).send(body);
 assert.equal(invalid.status,422);assert.equal(invalid.body.error.code,'FREIGHT_DIMENSIONS_REQUIRED');
});
test('freight rounding uses exact decimals and rejects missing capacities and excessive trips',()=>{
 const rate={baseFeePaise:0n,handlingFeePaise:0n,perKmPaise:1n,perTonneKmPaise:0n,perCubicMetreKmPaise:0n,weightCapacityKg:null,volumeCapacityM3:null};
 assert.equal(calculateFreight(rate,new Prisma.Decimal('1.5'),null,null).amountPaise,'2');
 assert.throws(()=>calculateFreight(rate,new Prisma.Decimal(1),new Prisma.Decimal(100),null),e=>e.code==='FREIGHT_CAPACITY_REQUIRED');
 assert.throws(()=>calculateFreight({...rate,weightCapacityKg:new Prisma.Decimal(1)},new Prisma.Decimal(1),new Prisma.Decimal(101),null),e=>e.code==='FREIGHT_TRIP_LIMIT');
});

test('content publication is explicit/versioned and device tokens stay encrypted and scoped',async()=>{
 const slug='policy-'+randomUUID().slice(0,8),path='/api/v2/admin/content/'+slug;
 const body={title:'Terms',body:'Supplier terms text',published:false,expectedVersion:0,reason:'Independent policy review'};
 assert.equal((await call('put',path,'owner',body)).status,403);
 assert.equal((await call('put',path,'admin',body)).status,200);
 assert.equal((await api.get('/api/v2/content/'+slug)).status,404);
 assert.equal((await call('put',path,'admin',{...body,published:true})).status,409);
 assert.equal((await call('put',path,'admin',{...body,published:true,expectedVersion:1})).status,200);
 assert.equal((await api.get('/api/v2/content/'+slug)).body.data.format,'plain-text');
 const device={token:'fcm_token_'+randomUUID().replaceAll('-','')+'0123456789abcdefgh',app:'supplier',platform:'android'};
 const registered=await call('post','/api/v2/me/devices','owner',device);assert.equal(registered.status,201,JSON.stringify(registered.body));
 assert(!JSON.stringify(registered.body).includes(device.token));
 const stored=await db.deviceRegistration.findUniqueOrThrow({where:{id:registered.body.data.id}});
 assert(!stored.fcmTokenEnc.includes(device.token));assert(stored.fcmTokenEnc.startsWith('v1.'));
 assert.equal((await call('post','/api/v2/me/devices','other',device)).status,409);
 assert.equal((await call('delete','/api/v2/me/devices/'+stored.id,'other')).status,404);
 assert.equal((await call('delete','/api/v2/me/devices/'+stored.id,'owner')).status,200);
 assert.equal((await call('post','/api/v2/me/devices','other',device)).status,201,'Disabled device can be registered by the next signed-in owner');
});
