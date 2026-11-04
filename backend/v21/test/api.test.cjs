'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter,RedisRestRateLimiter}=require('../dist/rateLimit.js');
const {paiseString,parsePaise,decimalString,utcTimestamp,publicMoneyDTO,stableRequestHash}=require('../dist/contracts.js');
const {readConfig}=require('../dist/config.js');
const {ApiError}=require('../dist/errors.js');
function appWith({db={$queryRaw:async()=>[{one:1}]},limiter=new InMemoryTestLimiter(),origins=['https://staging.buildto.test']}={}) {
 return createV21App({db,limiter,allowedOrigins:origins,proxyHops:0,log:()=>{}});
}
test('only safe public foundation routes are exposed',async()=>{
 const app=appWith();
 const health=await request(app).get('/health');
 assert.equal(health.status,200);
 assert.equal(health.body.service,'buildto-v21-api');
 assert.equal(health.body.requestId,health.headers['x-request-id']);
 const ready=await request(app).get('/ready');
 assert.equal(ready.status,200);
 assert.equal(ready.body.ready,true);
 const sys=await request(app).get('/api/v2/system');
 assert.equal(sys.status,200);
 assert.deepEqual(sys.body.data.capabilities,['catalog.discovery','catalog.supplier','catalog.review']);
 assert.equal(sys.body.data.moneyFormat,'decimal-string-paise');
 assert.equal((await request(app).post('/api/v2/orders').send({})).status,404);
 assert.equal((await request(app).get('/api/v2/suppliers')).status,404);
});
test('readiness database failures are redacted',async()=>{
 const app=appWith({db:{$queryRaw:async()=>{throw new Error('postgresql://user:password@host');}}});
 const response=await request(app).get('/ready');
 assert.equal(response.status,503);
 assert.equal(response.body.error.code,'DATABASE_UNAVAILABLE');
 assert(!JSON.stringify(response.body).includes('password'));
});
test('request IDs are validated and propagated',async()=>{
 const app=appWith();
 const good=await request(app).get('/health').set('x-request-id','request_ID_123456789');
 assert.equal(good.headers['x-request-id'],'request_ID_123456789');
 const bad=await request(app).get('/health').set('x-request-id','short');
 assert.notEqual(bad.headers['x-request-id'],'short');
 assert.equal(bad.body.requestId,bad.headers['x-request-id']);
});
test('CORS is exact-match, OPTIONS safe and default response secure',async()=>{
 const app=appWith();
 const ok=await request(app).get('/api/v2/system').set('Origin','https://staging.buildto.test');
 assert.equal(ok.status,200);
 assert.equal(ok.headers['access-control-allow-origin'],'https://staging.buildto.test');
 assert.equal(ok.headers['x-content-type-options'],'nosniff');
 assert.equal(ok.headers['x-frame-options'],'DENY');
 const bad=await request(app).get('/api/v2/system').set('Origin','https://attacker.example');
 assert.equal(bad.status,403);
 assert.equal(bad.body.error.code,'ORIGIN_NOT_ALLOWED');
 assert(!bad.headers['access-control-allow-origin']);
 assert.equal((await request(app).options('/api/v2/system').set('Origin','https://staging.buildto.test')).status,204);
});
test('Redis rate limiter runs an atomic script and hashes sensitive subjects',async()=>{
 const redis=new RedisRestRateLimiter('https://redis.example','secret','unique-hmac',async(_,options)=>{
   assert.equal(options.headers.Authorization,'Bearer secret');
   const command=JSON.parse(options.body);
   assert.equal(command[0],'EVAL');
   assert(!options.body.includes('private-ip-or-account'));
   return {ok:true,json:async()=>({result:1})};
 });
 const r=await redis.check('private-ip-or-account',2,60);
 assert.deepEqual(r,{remaining:1});
 const exhausted=new RedisRestRateLimiter('https://redis.example','secret','unique-hmac',async()=>({ok:true,json:async()=>({result:3})}));
 await assert.rejects(exhausted.check('ip',2,60),e=>e instanceof ApiError&&e.status===429);
 const broken=new RedisRestRateLimiter('https://redis.example','secret','unique-hmac',async()=>{throw new Error('private connection details');});
 await assert.rejects(broken.check('ip',2,60),e=>e.status===503&&!e.message.includes('private'));
});
test('app maps expected limiter failure to 429',async()=>{
 const app=appWith({limiter:{check:async()=>{throw new ApiError(429,'RATE_LIMITED','Too many requests.');}}});
 const response=await request(app).get('/api/v2/system');
 assert.equal(response.status,429);
 assert.equal(response.body.error.code,'RATE_LIMITED');
});
test('paise, decimal and date DTOs preserve precision',()=>{
 assert.equal(paiseString(9007199254740995n),'9007199254740995');
 assert.equal(decimalString('12.000001'),'12.000001');
 assert.equal(parsePaise('9223372036854775807'),9223372036854775807n);
 assert.deepEqual(publicMoneyDTO({totalPaise:2345n,currency:'INR'}),{totalPaise:'2345',currency:'INR'});
 assert.throws(()=>parsePaise(1234),/PAISE_MUST/);
 assert.throws(()=>parsePaise('9223372036854775808'),/EXCEEDS/);
 assert.throws(()=>decimalString('0.1e5'),/INVALID/);
 assert.equal(utcTimestamp(new Date('2026-11-03T14:30:00.000Z')),'2026-11-03T14:30:00.000Z');
});
test('canonical request fingerprints do not depend on JSON object property ordering',()=>{
 const a=stableRequestHash({b:[1,'x'],a:{p:true,q:3}});
 const b=stableRequestHash({a:{q:3,p:true},b:[1,'x']});
 assert.equal(a,b);
 assert.notEqual(a,stableRequestHash({b:[2,'x'],a:{p:true,q:3}}));
});
test('config refuses production, unrelated Neon databases and wildcard CORS',()=>{
 assert.throws(()=>readConfig({BUILDTO_V21_ENV:'production',DATABASE_URL:'postgresql://x@host/db'}),/NOT_ALLOWED/);
 assert.throws(()=>readConfig({BUILDTO_V21_ENV:'staging',DATABASE_URL:'postgresql://x@wrong.example/neondb',BUILDTO_V21_CORS_ORIGINS:'https://test'}),/TARGET_DENIED/);
 assert.throws(()=>readConfig({BUILDTO_V21_ENV:'local',DATABASE_URL:'postgresql://x@neon.example/neondb'}),/TARGET_DENIED/);
 assert.throws(()=>readConfig({BUILDTO_V21_ENV:'local',DATABASE_URL:'postgresql://x@127.0.0.1:5432/local',BUILDTO_V21_CORS_ORIGINS:'*'}),/CORS_ORIGIN_INVALID/);
 const c=readConfig({BUILDTO_V21_ENV:'local',DATABASE_URL:'postgresql://x@127.0.0.1:5432/buildto_v21_test',PORT:'5101'});
 assert.equal(c.proxyHops,0);
});
test('documented OpenAPI includes exactly implemented routes',()=>{
 const spec=require('../openapi.json');
 assert.deepEqual(Object.keys(spec.paths).sort(),['/api/v2/system','/health','/ready','/api/v2/me','/api/v2/admin/access','/api/v2/suppliers/{supplierId}/access','/api/v2/webhooks/clerk',...['categories','brands','units','products','listings'].map(s=>'/api/v2/catalog/'+s),'/api/v2/admin/catalog/categories','/api/v2/admin/catalog/categories/{categoryId}','/api/v2/admin/catalog/brands','/api/v2/admin/catalog/products','/api/v2/admin/catalog/products/{productId}','/api/v2/admin/catalog/products/{productId}/conversions','/api/v2/admin/catalog/listings/pending','/api/v2/admin/catalog/listings/{listingId}/review','/api/v2/suppliers/{supplierId}/listings','/api/v2/suppliers/{supplierId}/listings/{listingId}','/api/v2/suppliers/{supplierId}/listings/{listingId}/submit','/api/v2/suppliers/{supplierId}/listings/{listingId}/price-tiers'].sort());
 assert.equal(spec.openapi,'3.0.3');
});


test('rate limits use a shared budget even when a caller changes the supplier ID in the URL',async()=>{
 const subjects=[];
 const app=createV21App({
   db:{$queryRaw:async()=>[{one:1}]},
   limiter:{check:async subject=>{subjects.push(subject);return {remaining:49};}},
   log:()=>{},allowedOrigins:[],proxyHops:0,
   identityVerifier:{verify:async()=>{throw new ApiError(401,'INVALID_SESSION','Invalid session.');}}
 });
 const uuid1='11111111-1111-4111-8111-111111111111';
 const uuid2='22222222-2222-4222-8222-222222222222';
 await request(app).get('/api/v2/suppliers/'+uuid1+'/access').set('Authorization','Bearer invalid');
 await request(app).get('/api/v2/suppliers/'+uuid2+'/access').set('Authorization','Bearer invalid');
 assert.equal(subjects.length,2);
 assert.equal(subjects[0],subjects[1]);
});

test('serialization conflicts are safe 409s rather than unknown 500s',()=>{
 const {normalizeError}=require('../dist/errors.js');
 const err=normalizeError({code:'P2034',message:'private query metadata'});
 assert.equal(err.status,409);
 assert.equal(err.code,'CONCURRENT_MODIFICATION');
 assert(!err.message.includes('private'));
});
