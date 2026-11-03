'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const subject=()=> 'user_'+randomUUID().replaceAll('-','');
const tokens={};
const app=createV21App({
 db,allowedOrigins:[],proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session.');
  return {subject:tokens[token],sessionId:'sess_test12345678'};
 }}
});
const http=request(app);
const send=(method,url,token,payload)=>{
 let req=http[method](url);
 if(token)req=req.set('Authorization','Bearer '+token);
 return payload===undefined?req:req.send(payload);
};
const store={};
test('bootstrap isolated admin, customers, supplier identities',async()=>{
 const admin=await db.user.create({data:{clerkUserId:subject(),displayName:'Delivery Admin'}});
 const customer=await db.user.create({data:{clerkUserId:subject(),displayName:'Delivery Customer'}});
 const outsider=await db.user.create({data:{clerkUserId:subject(),displayName:'Second Customer'}});
 const supplierOwner=await db.user.create({data:{clerkUserId:subject(),displayName:'Supplier Fulfillment'}});
 const supplierStranger=await db.user.create({data:{clerkUserId:subject(),displayName:'Foreign Supplier'}});
 await db.adminMembership.create({data:{userId:admin.id,role:'OPERATIONS',active:true}});
 const supplier=await db.supplier.create({data:{
  slug:'geo-'+randomUUID(),legalName:'Area Test Supplier',displayName:'Area Test Supplier',approval:'APPROVED'
 }});
 const otherSupplier=await db.supplier.create({data:{
  slug:'geo-'+randomUUID(),legalName:'Other Area Supplier',displayName:'Other Area Supplier',approval:'APPROVED'
 }});
 await db.supplierMember.createMany({data:[
  {userId:supplierOwner.id,supplierId:supplier.id,role:'FULFILLMENT',active:true},
  {userId:supplierStranger.id,supplierId:otherSupplier.id,role:'FULFILLMENT',active:true}
 ]});
 for(const [key,user] of Object.entries({admin,customer,outsider,supplierOwner,supplierStranger}))
  tokens[key]=user.clerkUserId;
 Object.assign(store,{admin,customer,outsider,supplierOwner,supplierStranger,supplier,otherSupplier});
});
test('admin defines city and explicit PIN zone; authorization and activation enforced',async()=>{
 const forbidden=await send('post','/api/v2/admin/delivery/cities','customer',
  {code:'HYD'+randomUUID().slice(0,5).toUpperCase(),name:'Hyderabad',stateCode:'TG'});
 assert.equal(forbidden.status,403);
 const created=await send('post','/api/v2/admin/delivery/cities','admin',
  {code:'HYD'+randomUUID().slice(0,5).toUpperCase(),name:'Test Hyderabad',stateCode:'TG'});
 assert.equal(created.status,201,JSON.stringify(created.body));
 assert.equal(created.body.data.active,false);
 store.cityId=created.body.data.id;
 const payload={cityId:store.cityId,name:'North Hyderabad',postalCodes:['500001','500002']};
 assert.equal((await send('post','/api/v2/admin/delivery/areas','admin',payload)).status,422);
 const activated=await send('patch','/api/v2/admin/delivery/cities/'+store.cityId,'admin',{active:true});
 assert.equal(activated.status,200);
 const area=await send('post','/api/v2/admin/delivery/areas','admin',payload);
 assert.equal(area.status,201,JSON.stringify(area.body));
 assert.equal(area.body.data.active,false);
 store.areaId=area.body.data.id;
 assert.equal((await http.get('/api/v2/delivery/areas?cityId='+store.cityId)).body.data.length,0);
 const enabled=await send('patch','/api/v2/admin/delivery/areas/'+store.areaId,'admin',{active:true});
 assert.equal(enabled.status,200);
 const visible=await http.get('/api/v2/delivery/areas?cityId='+store.cityId);
 assert.equal(visible.status,200);assert.equal(visible.body.data[0].postalCodes[0],'500001');
 assert.equal((await http.get('/api/v2/delivery/cities')).status,200);
});
test('supplier configures only own area and fixed exact paise freight',async()=>{
 const area=store.areaId,supplier=store.supplier.id;
 const route='/api/v2/suppliers/'+supplier+'/delivery/areas/'+area;
 const forbidden=await send('put',route,'supplierStranger',{active:true,minimumPaise:'5000'});
 assert.equal(forbidden.status,404);
 const adminForbidden=await send('put',route,'admin',{active:true,minimumPaise:'5000'});
 assert.equal(adminForbidden.status,404);
 const selected=await send('put',route,'supplierOwner',{active:true,minimumPaise:'5000'});
 assert.equal(selected.status,200,JSON.stringify(selected.body));
 assert.equal(selected.body.data.minimumPaise,'5000');
 const invalid=await send('put',route+'/flat-rate','supplierOwner',{
  baseFeePaise:99.1,handlingFeePaise:'1000'
 });
 assert.equal(invalid.status,400);
 const price=await send('put',route+'/flat-rate','supplierOwner',{
  baseFeePaise:'9900',handlingFeePaise:'1000',freeAbovePaise:'100000'
 });
 assert.equal(price.status,200,JSON.stringify(price.body));
 assert.equal(price.body.data.baseFeePaise,'9900');
 const coverage=await send('get','/api/v2/suppliers/'+supplier+'/delivery','supplierOwner');
 assert.equal(coverage.status,200);
 assert.equal(coverage.body.data.find(x=>x.areaId===area).rates[0].handlingFeePaise,'1000');
});
const addressPayload=(label,postalCode='500001',latitude='17.3850000',longitude='78.4867000')=>({
 cityId:store.cityId,label,recipientName:'Test Receiver',phoneE164:'+919876543210',
 line1:'Road 1, Test Buildings',locality:'Hyderabad',postalCode,
 latitude,longitude
});
test('customer address ownership, PIN, coordinate pairing, default uniqueness and soft delete',async()=>{
 const invalid=await send('post','/api/v2/me/addresses','customer',{
  ...addressPayload('Wrong'),postalCode:'50001'
 });
 assert.equal(invalid.status,400);
 const missingLng=await send('post','/api/v2/me/addresses','customer',{
  ...addressPayload('Incomplete'),longitude:undefined
 });
 assert.equal(missingLng.status,400);
 const first=await send('post','/api/v2/me/addresses','customer',addressPayload('Site One'));
 assert.equal(first.status,201,JSON.stringify(first.body));
 assert.equal(first.body.data.isDefault,true);
 store.addressId=first.body.data.id;
 const second=await send('post','/api/v2/me/addresses','customer',
  {...addressPayload('Site Two','500002'),isDefault:true});
 assert.equal(second.status,201,JSON.stringify(second.body));
 assert.equal(second.body.data.isDefault,true);store.secondId=second.body.data.id;
 const addresses=await send('get','/api/v2/me/addresses','customer');
 assert.equal(addresses.status,200);
 assert.equal(addresses.body.data.filter(a=>a.isDefault).length,1);
 assert.equal(addresses.body.data.length,2);
 assert.equal((await send('patch','/api/v2/me/addresses/'+store.addressId,'outsider',{label:'Stolen'})).status,404);
 assert.equal((await send('delete','/api/v2/me/addresses/'+store.secondId,'outsider')).status,404);
 const removed=await send('delete','/api/v2/me/addresses/'+store.secondId,'customer');
 assert.equal(removed.status,200);
 assert.equal((await send('get','/api/v2/me/addresses','customer')).body.data.length,1);
});
test('PIN-only zone returns clear fee preview, and never trusts customer subtotal',async()=>{
 const supplierId=store.supplier.id;
 const eligibility=await send('get','/api/v2/delivery/suppliers/'+supplierId+'/eligibility?addressId='+store.addressId,'customer');
 assert.equal(eligibility.status,200,JSON.stringify(eligibility.body));
 assert.equal(eligibility.body.data.serviceable,true);
 assert.equal(eligibility.body.data.previewOnly,true);
 assert.equal(eligibility.body.data.standardDeliveryFeePaise,'10900');
 assert.equal(eligibility.body.data.minimumOrderPaise,'5000');
 assert.equal(eligibility.body.data.freeAbovePaise,'100000');
 assert.equal((await send('get','/api/v2/delivery/suppliers/'+supplierId+'/eligibility?addressId='+store.addressId,'outsider')).status,404);
 assert.equal((await send('get','/api/v2/delivery/suppliers/'+supplierId+'/eligibility?addressId='+store.addressId,'supplierOwner')).status,404);
});
test('PostGIS radius enforces coordinates as well as matching PIN; no false positive outside circle',async()=>{
 const cityId=store.cityId, supplierId=store.otherSupplier.id;
 const created=await send('post','/api/v2/admin/delivery/areas','admin',{
  cityId,name:'Within 4km test zone',postalCodes:['500001'],
  centerLat:'17.3850000',centerLng:'78.4867000',radiusKm:'4.00'
 });
 assert.equal(created.status,201,JSON.stringify(created.body));
 const areaId=created.body.data.id;
 assert.equal((await send('patch','/api/v2/admin/delivery/areas/'+areaId,'admin',{active:true})).status,200);
 const route='/api/v2/suppliers/'+supplierId+'/delivery/areas/'+areaId;
 assert.equal((await send('put',route,'supplierStranger',{active:true,minimumPaise:'0'})).status,200);
 assert.equal((await send('put',route+'/flat-rate','supplierStranger',{
   baseFeePaise:'20000',handlingFeePaise:'0'
 })).status,200);
 const inside=await send('get','/api/v2/delivery/suppliers/'+supplierId+'/eligibility?addressId='+store.addressId,'customer');
 assert.equal(inside.status,200,JSON.stringify(inside.body));
 assert.equal(inside.body.data.serviceable,true);
 const far=await send('post','/api/v2/me/addresses','customer',
   addressPayload('Far delivery site','500001','19.0760000','72.8777000'));
 assert.equal(far.status,201,JSON.stringify(far.body));
 const outside=await send('get','/api/v2/delivery/suppliers/'+supplierId+'/eligibility?addressId='+far.body.data.id,'customer');
 assert.equal(outside.status,200);
 assert.equal(outside.body.data.serviceable,false);
});
test('suspended supplier is never serviceable and disabled area stops delivery eligibility',async()=>{
 const sid=store.supplier.id;
 await db.supplier.update({where:{id:sid},data:{approval:'SUSPENDED',suspendedAt:new Date()}});
 const during=await send('get','/api/v2/delivery/suppliers/'+sid+'/eligibility?addressId='+store.addressId,'customer');
 assert.equal(during.status,200);assert.equal(during.body.data.serviceable,false);
 await db.supplier.update({where:{id:sid},data:{approval:'APPROVED',suspendedAt:null}});
 const off=await send('patch','/api/v2/admin/delivery/areas/'+store.areaId,'admin',{active:false});
 assert.equal(off.status,200);
 const blocked=await send('get','/api/v2/delivery/suppliers/'+sid+'/eligibility?addressId='+store.addressId,'customer');
 assert.equal(blocked.body.data.serviceable,false);
 const edit=await send('patch','/api/v2/admin/delivery/areas/'+store.areaId,'admin',{
  postalCodes:['500001','500003']
 });
 assert.equal(edit.status,200);
 assert.equal((await send('patch','/api/v2/admin/delivery/areas/'+store.areaId,'admin',{active:true})).status,200);
 const improper=await send('patch','/api/v2/admin/delivery/areas/'+store.areaId,'admin',{
  postalCodes:['500004']
 });
 assert.equal(improper.status,409);
});
