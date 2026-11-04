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
 proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Sign in required.');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}});
const get=(api,path,t)=>api.get(path).set('Authorization','Bearer '+t);
test('A13: finance beneficiary list is bounded, masked and rejects other roles',async()=>{
 const finance=await user('financeA13'),support=await user('supportA13');
 await db.adminMembership.createMany({data:[
  {userId:finance.id,role:'FINANCE',active:true},
  {userId:support.id,role:'SUPPORT',active:true}
 ]});
 const api=request(app({fin:finance.clerkUserId,support:support.clerkUserId}));
 const found=await get(api,'/api/v2/admin/finance/beneficiaries?limit=25','fin');
 assert.equal(found.status,200,JSON.stringify(found.body));
 assert(Array.isArray(found.body.data.items));
 assert('nextCursor' in found.body.data);
 const raw=JSON.stringify(found.body);
 assert(!raw.includes('bankAccountNumber'));
 assert(!raw.includes('providerTokenRef'));
 assert(!raw.includes('validationRef'));
 assert.equal((await get(api,'/api/v2/admin/finance/beneficiaries','support')).status,403);
 assert.equal((await api.get('/api/v2/admin/finance/beneficiaries')).status,401);
 assert.equal((await get(api,'/api/v2/admin/finance/beneficiaries?limit=101','fin')).status,400);
 assert.equal((await get(api,'/api/v2/admin/finance/beneficiaries?cursor=unsafe','fin')).status,400);
});