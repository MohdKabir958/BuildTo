'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {createHash}=require('node:crypto');
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const {readConfig}=require('../dist/config.js');
const {
 REVIEWED_V21_MIGRATIONS,INTEGRITY_COUNTERS,
 assertMigrationLedgerRecords,assertV21AllMigrationsApplied,
 inspectV21FinanceIntegrity,assertV21ReleaseIntegrity,assertV21FinancialCounts
}=require('../dist/release-integrity.js');
const {verifyExistingSchema}=require('../../scripts/v21/schema-contract.cjs');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());

const safeRows=()=>REVIEWED_V21_MIGRATIONS.map((migration_name,i)=>({
 migration_name,checksum:createHash('sha256').update(readFileSync(
  resolve(__dirname,'../../prisma/v21/migrations',migration_name,'migration.sql'))).digest('hex'),
 finished_at:new Date(2026,10,4,0,0,i),rolled_back_at:null
}));
const safeCounts=()=>Object.fromEntries(INTEGRITY_COUNTERS.map(k=>[k,0]));

test('release manifest allows exactly 3 reviewed migrations, all applied with matching SHA256',()=>{
 assert.equal(REVIEWED_V21_MIGRATIONS.length,3);
 assert.doesNotThrow(()=>assertMigrationLedgerRecords(safeRows()));
 assert.throws(()=>assertMigrationLedgerRecords(safeRows().slice(1)),/LEDGER_INCOMPLETE/);
 assert.throws(()=>assertMigrationLedgerRecords([...safeRows(),{
  ...safeRows()[0],migration_name:'20261105_unreviewed'}]),/LEDGER_INCOMPLETE/);
 assert.throws(()=>assertMigrationLedgerRecords(safeRows().map((r,i)=>i===1?
  {...r,checksum:'a'.repeat(64)}:r)),/CHECKSUM_MISMATCH/);
 assert.throws(()=>assertMigrationLedgerRecords(safeRows().map((r,i)=>i===2?
  {...r,finished_at:null}:r)),/CHECKSUM_MISMATCH/);
 assert.throws(()=>assertMigrationLedgerRecords(safeRows().map((r,i)=>i===2?
  {...r,rolled_back_at:new Date()}:r)),/CHECKSUM_MISMATCH/);
 assert.throws(()=>assertMigrationLedgerRecords(safeRows().map((r,i)=>i===2?
  {...r,migration_name:r.migration_name+'-tampered'}:r)),/CHECKSUM_MISMATCH/);
});
test('read-only release check passes on disposable PostGIS with actual Prisma ledger and finance data',async()=>{
 const schema=await verifyExistingSchema(db);
 assert.equal(schema.migrationHistoryExists,true);
 await assertV21AllMigrationsApplied(db);
 const counts=await inspectV21FinanceIntegrity(db);
 assert.deepEqual(counts,safeCounts());
 await assertV21ReleaseIntegrity(db);
});
test('finance preflight blocks every nonzero anomaly, malformed counters and never divulges record identities',()=>{
 assert.doesNotThrow(()=>assertV21FinancialCounts(safeCounts()));
 for(const k of INTEGRITY_COUNTERS){
  const anomaly={...safeCounts(),[k]:1};
  assert.throws(()=>assertV21FinancialCounts(anomaly),err=>
   err.message==='V21_FINANCIAL_INTEGRITY_BLOCKED: finance records require independent investigation.');
 }
 for(const n of [-1,NaN,1.5,Number.MAX_SAFE_INTEGER+1])
  assert.throws(()=>assertV21FinancialCounts({
   ...safeCounts(),malformedCreditNotes:n}),/V21_FINANCIAL_INTEGRITY_BLOCKED/);
});
test('readiness does not claim healthy when release migration integrity check fails',async()=>{
 let checks=0;
 const app=createV21App({db:{$queryRaw:async()=>[{one:1}]},
  limiter:new InMemoryTestLimiter(),log:()=>{},allowedOrigins:[],proxyHops:0,
  readinessCheck:async()=>{checks++;throw new Error('DATABASE_URL secret=never-show');}});
 const healthy=await request(app).get('/health');
 assert.equal(healthy.status,200);
 const ready=await request(app).get('/ready');
 assert.equal(checks,1);
 assert.equal(ready.status,503);
 assert.equal(ready.body.error.code,'DATABASE_UNAVAILABLE');
 assert(!JSON.stringify(ready.body).includes('secret='));
 assert.equal(ready.headers['cache-control'],'no-store');
});
test('system explicitly marks BuildTo V2.1 as unreleased and manual-only for money movement',async()=>{
 const app=createV21App({db:{$queryRaw:async()=>[{one:1}]},
  limiter:new InMemoryTestLimiter(),log:()=>{},allowedOrigins:[],proxyHops:0});
 const response=await request(app).get('/api/v2/system');
 assert.equal(response.status,200);
 const flags=response.body.data;
 assert.equal(flags.releaseStage,'unreleased-staging-candidate');
 assert.equal(flags.productionReady,false);
 assert.equal(flags.automaticRefundExecution,false);
 assert.equal(flags.automaticPayoutExecution,false);
 assert.equal(flags.bankStatementAPIReconciled,false);
 assert.equal(flags.partialGstCreditSupported,false);
});
test('every documented protected finance endpoint denies unauthenticated calls before finance access',async()=>{
 const spec=require('../openapi.json');
 const dbStub={$queryRaw:async()=>[{one:1}]};
 const app=createV21App({db:dbStub,
  limiter:new InMemoryTestLimiter(),log:()=>{},allowedOrigins:[],proxyHops:0,
  identityVerifier:{verify:async()=>{throw new ApiError(401,'INVALID_SESSION','Session invalid');}}});
 const routes=[];
 for(const [path,verbs] of Object.entries(spec.paths)){
  if(!(path.startsWith('/api/v2/admin/finance/')||
   path.includes('/finance/')||path.endsWith('/finance/statement')))continue;
  for(const [method,operation] of Object.entries(verbs)){
   if(!['get','post','patch','put','delete'].includes(method))continue;
   assert.deepEqual(operation.security,[{clerkBearer:[]}],path+' '+method);
   routes.push({path,method});
  }
 }
 assert(routes.length>=20);
 for(const route of routes){
  const path=route.path.replace(/\{[^}]+\}/g,'11111111-1111-4111-8111-111111111111');
  const req=request(app)[route.method](path);
  if(['post','patch','put'].includes(route.method))req.send({});
  const response=await req;
  assert.equal(response.status,401,route.method+' '+route.path+' returned '+response.status);
  assert.equal(response.body.error.code,'INVALID_SESSION');
 }
});
test('refund execute, payout send and production mutation routes are absent, not soft-enabled',async()=>{
 const app=createV21App({db:{$queryRaw:async()=>[{one:1}]},
  limiter:new InMemoryTestLimiter(),log:()=>{},allowedOrigins:[],proxyHops:0});
 for(const path of ['/api/v2/admin/finance/payouts/11111111-1111-4111-8111-111111111111/send',
  '/api/v2/admin/finance/refunds/11111111-1111-4111-8111-111111111111/execute',
  '/api/v2/admin/release/production-cutover']){
  const response=await request(app).post(path).send({});
  assert.equal(response.status,404);
 }
});


test('staging requires exact encrypted PostgreSQL DSN even for approved Neon host',()=>{
 const base={BUILDTO_V21_ENV:'staging',
  DATABASE_URL:'postgresql://user:placeholder@ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech/stagingdb',
  BUILDTO_V21_CORS_ORIGINS:'https://staging.buildto.test'};
 for(const url of [base.DATABASE_URL,base.DATABASE_URL+'?sslmode=disable',
  base.DATABASE_URL+'?sslmode=prefer',
  base.DATABASE_URL+'?sslmode=require&sslmode=disable'])
  assert.throws(()=>readConfig({...base,DATABASE_URL:url}),/V21_STAGING_TLS_REQUIRED/);
 assert.throws(()=>readConfig({...base,DATABASE_URL:base.DATABASE_URL+'?sslmode=require',
  NODE_TLS_REJECT_UNAUTHORIZED:'0'}),/V21_STAGING_TLS_REQUIRED/);
 assert.throws(()=>readConfig({...base,DATABASE_URL:base.DATABASE_URL+'?sslmode=require'}),
  /V21_CLERK_CONFIG_REQUIRED/);
});
test('CORS and Clerk authorized origins cannot include credentials, paths or queries',()=>{
 const root={BUILDTO_V21_ENV:'local',
  DATABASE_URL:'postgresql://tester:placeholder@127.0.0.1:5432/buildto_v21_test'};
 for(const invalid of ['https://allowed.example/path',
  'https://allowed.example?session=secret',
  'https://user:secret@allowed.example','https://allowed.example/',
  'https://allowed.example#fragment','javascript:alert(1)']){
  assert.throws(()=>readConfig({...root,BUILDTO_V21_CORS_ORIGINS:invalid}),
   /V21_CORS_ORIGIN_INVALID/,invalid);
  assert.throws(()=>readConfig({...root,CLERK_AUTHORIZED_PARTIES:invalid}),
   /V21_CLERK_PARTIES_INVALID/,invalid);
 }
 assert.equal(readConfig({...root,BUILDTO_V21_CORS_ORIGINS:'http://localhost:5173',
  CLERK_AUTHORIZED_PARTIES:'http://localhost:3000'})
  .corsOrigins[0],'http://localhost:5173');
});


test('access logs never contain unknown URL segments, customer order IDs or querystring data',async()=>{
 const events=[];
 const app=createV21App({db:{$queryRaw:async()=>[{one:1}]},
  limiter:new InMemoryTestLimiter(),log:e=>events.push(e),
  allowedOrigins:[],proxyHops:0,
  identityVerifier:{verify:async()=>{throw new ApiError(401,'INVALID_SESSION','Invalid');}}});
 const secret='PRIVATE_CUSTOMER_BANK_TOKEN_1234567890';
 const orderId='22222222-2222-4222-8222-222222222222';
 const missing=await request(app).get('/api/v2/unexpected/'+secret+
  '?account=123456789012345&token='+secret);
 assert.equal(missing.status,404);
 assert.equal(events.at(-1).path,'UNMATCHED');
 const denied=await request(app).get('/api/v2/suppliers/'+orderId+'/access')
  .set('Authorization','Bearer invalid');
 assert.equal(denied.status,401);
 assert.equal(events.at(-1).path,'/api/v2/suppliers/:supplierId/access');
 const logged=JSON.stringify(events);
 assert(!logged.includes(secret));
 assert(!logged.includes(orderId));
 assert(!logged.includes('123456789012345'));
 assert(!logged.includes('Bearer'));
 assert(!logged.includes('token='));
});
