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
 clerkUserId:'user_'+randomUUID().replaceAll('-',''),
 displayName:label,email:label+randomUUID()+'@example.test',status:'ACTIVE'
 }});}
const app=tokens=>createV21App({db,allowedOrigins:['https://admin.buildto.example'],
 proxyHops:0,limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Not authenticated');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}});
const get=(api,path,t)=>api.get(path).set('Authorization','Bearer '+t);
test('A09: ADMIN_READ gets truthful live counts; finance-only totals remain masked',async()=>{
 const op=await user('overviewOp'),finance=await user('overviewFinance'),customer=await user('overviewCustomer');
 await db.adminMembership.createMany({data:[
  {userId:op.id,role:'OPERATIONS',active:true},{userId:finance.id,role:'FINANCE',active:true}
 ]});
 const supplier=await db.supplier.create({data:{
  slug:'overview-'+randomUUID(),legalName:'Overview Test',displayName:'Overview Test',approval:'PENDING'
 }});
 const api=request(app({op:op.clerkUserId,finance:finance.clerkUserId,customer:customer.clerkUserId}));
 const operation=await get(api,'/api/v2/admin/overview','op');
 assert.equal(operation.status,200,JSON.stringify(operation.body));
 const o=operation.body.data;
 assert.equal(o.financeEvidence,null);
 assert(o.supplierCount>=1);
 assert(o.pendingSuppliers>=1);
 assert.equal(typeof o.totalOrders,'number');
 assert.equal(typeof o.openSupportCases,'number');
 assert(Number.isFinite(Date.parse(o.asOf)));
 const financiallyAllowed=await get(api,'/api/v2/admin/overview','finance');
 assert.equal(financiallyAllowed.status,200);
 assert.match(financiallyAllowed.body.data.financeEvidence.verifiedGatewayCaptureEvidencePaise,/^(0|[1-9][0-9]*)$/);
 assert.equal(financiallyAllowed.body.data.financeEvidence.bankCreditVerified,false);
 assert.equal(financiallyAllowed.body.data.financeEvidence.netRevenueCalculated,false);
 assert.equal((await get(api,'/api/v2/admin/overview','customer')).status,403);
 assert.equal((await api.get('/api/v2/admin/overview')).status,401);
});
