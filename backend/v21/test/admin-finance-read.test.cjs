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
async function user(label){return db.user.create({data:{
 clerkUserId:'user_'+randomUUID().replaceAll('-',''),displayName:label,
 email:label+randomUUID()+'@example.test',status:'ACTIVE'
 }});}
const app=tokens=>createV21App({db,allowedOrigins:['https://admin.buildto.example'],
 proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Not signed in.');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}});
const get=(api,path,t)=>api.get(path).set('Authorization','Bearer '+t);
test('A12: read-only finance supplier picker and COD queue are role-gated, paginated and private',async()=>{
 const operator=await user('financeOperator'),support=await user('supportOperator');
 await db.adminMembership.createMany({data:[
  {userId:operator.id,role:'FINANCE',active:true},{userId:support.id,role:'SUPPORT',active:true}
 ]});
 const api=request(app({fin:operator.clerkUserId,support:support.clerkUserId}));
 const suppliers=await get(api,'/api/v2/admin/finance/suppliers?limit=25','fin');
 assert.equal(suppliers.status,200,JSON.stringify(suppliers.body));
 assert(Array.isArray(suppliers.body.data.items));
 assert('nextCursor' in suppliers.body.data);
 assert(!JSON.stringify(suppliers.body).includes('bankAccountNumber'));
 const cod=await get(api,'/api/v2/admin/finance/cod?limit=25&status=RECORDED','fin');
 assert.equal(cod.status,200,JSON.stringify(cod.body));
 assert(Array.isArray(cod.body.data.items));
 assert(!JSON.stringify(cod.body).includes('collectorName'));
 assert(!JSON.stringify(cod.body).includes('collectedByUserId'));
 assert.equal((await get(api,'/api/v2/admin/finance/suppliers','support')).status,403);
 assert.equal((await get(api,'/api/v2/admin/finance/cod','support')).status,403);
 assert.equal((await get(api,'/api/v2/admin/finance/cod?limit=250','fin')).status,400);
 assert.equal((await get(api,'/api/v2/admin/finance/suppliers?cursor=unsafe','fin')).status,400);
 assert.equal((await api.get('/api/v2/admin/finance/cod')).status,401);
});
