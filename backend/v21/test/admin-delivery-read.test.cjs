'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const request=require('supertest');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {ApiError}=require('../dist/errors.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const db=new PrismaClient();test.after(async()=>db.$disconnect());
async function user(label){return db.user.create({data:{
 clerkUserId:'user_'+randomUUID().replaceAll('-',''),email:label+'-'+randomUUID()+'@example.test',displayName:label,status:'ACTIVE'
}});}
const app=tokens=>createV21App({
 db,allowedOrigins:['https://admin.buildto.example'],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid identity.');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}
});
const get=(api,path,token)=>api.get(path).set('Authorization','Bearer '+token);
test('A08: only operations can view inactive city and PIN area (public remains active-only)',async()=>{
 const ops=await user('ops'),customer=await user('customer');
 await db.adminMembership.create({data:{userId:ops.id,role:'OPERATIONS',active:true}});
 const api=request(app({ops:ops.clerkUserId,customer:customer.clerkUserId}));
 const city=await db.city.create({data:{code:'T'+randomUUID().slice(0,7).toUpperCase(),name:'Test City',stateCode:'TG',active:false}});
 const area=await db.serviceArea.create({data:{cityId:city.id,name:'Test PIN',postalCodes:['500099'],active:false}});
 const cities=await get(api,'/api/v2/admin/delivery/cities','ops');
 assert.equal(cities.status,200,JSON.stringify(cities.body));
 assert(cities.body.data.some(x=>x.id===city.id&&x.active===false));
 const zones=await get(api,'/api/v2/admin/delivery/areas?cityId='+city.id,'ops');
 assert.equal(zones.status,200,JSON.stringify(zones.body));
 assert(zones.body.data.some(x=>x.id===area.id&&x.active===false&&x.postalCodes.includes('500099')));
 assert.equal((await get(api,'/api/v2/admin/delivery/cities','customer')).status,403);
 assert.equal((await get(api,'/api/v2/admin/delivery/areas?cityId='+city.id,'customer')).status,403);
 assert.equal((await get(api,'/api/v2/admin/delivery/areas?cityId=garbage','ops')).status,400);
 const publicCities=await request(app({ops:ops.clerkUserId,customer:customer.clerkUserId})).get('/api/v2/delivery/cities');
 assert.equal(publicCities.status,200);
 assert(!publicCities.body.data.some(x=>x.id===city.id));
});
