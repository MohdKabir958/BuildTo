'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const request=require('supertest');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter,SingleInstanceRateLimiter}=require('../dist/rateLimit.js');
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
 assert.deepEqual(sys.body.data.capabilities,['catalog.discovery','catalog.supplier','catalog.review','delivery.areas','delivery.flat-fees','inventory.warehouses','inventory.adjustments','inventory.transfers','rfq.requests','rfq.quotes','promotions.admin','cart.customer','checkout.pricing','orders.customer','cod.customer','cod.supplier','cod.finance-review','invoices.supplier','fulfillment.supplier','shipments.tracking','returns.customer','support.cases','reviews.moderated','finance.reconciliation','finance.settlement-proposals','finance.cod-commissions','returns.credit-notes','finance.refund-requests','finance.refund-evidence','finance.payout-beneficiaries','finance.payout-reconciliation']);
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
test('in-process limiter enforces limits without external services',async()=>{
 let now=0;
 const limiter=new SingleInstanceRateLimiter(20,()=>now);
 assert.deepEqual(await limiter.check('office-ip',2,60),{remaining:1});
 assert.deepEqual(await limiter.check('office-ip',2,60),{remaining:0});
 await assert.rejects(limiter.check('office-ip',2,60),e=>e.status===429);
 now=61000;
 assert.deepEqual(await limiter.check('office-ip',2,60),{remaining:1});
});
test('rate limiter bounds memory and fails closed when full',async()=>{
 const limiter=new SingleInstanceRateLimiter(10,()=>0);
 for(let i=0;i<10;i++)await limiter.check('subject:'+i,20,60);
 await assert.rejects(limiter.check('eleventh',20,60),e=>e.status===503);
});
test('signed Clerk webhooks have a separate request budget',async()=>{
 const calls=[];
 const app=createV21App({
  db:{$queryRaw:async()=>[{one:1}]},limiter:{check:async(subject,max)=>{calls.push({subject,max});return {remaining:1};}},
  allowedOrigins:[],proxyHops:0,log:()=>{},clerkWebhookSecret:'whsec_fake',
 });
 await request(app).get('/api/v2/system');
 await request(app).post('/api/v2/webhooks/clerk').set('Content-Type','application/json').send('{}');
 assert.equal(calls[0].max,300);
 assert.equal(calls[1].max,240);
 assert.notEqual(calls[0].subject,calls[1].subject);
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
 assert.deepEqual(Object.keys(spec.paths).sort(),["/health","/ready","/api/v2/system","/api/v2/me","/api/v2/admin/access","/api/v2/suppliers/{supplierId}/access","/api/v2/webhooks/clerk","/api/v2/catalog/categories","/api/v2/catalog/brands","/api/v2/catalog/units","/api/v2/catalog/products","/api/v2/catalog/listings","/api/v2/admin/catalog/categories","/api/v2/admin/catalog/categories/{categoryId}","/api/v2/admin/catalog/brands","/api/v2/admin/catalog/products","/api/v2/admin/catalog/products/{productId}","/api/v2/admin/catalog/products/{productId}/conversions","/api/v2/admin/catalog/listings/pending","/api/v2/admin/catalog/listings/{listingId}/review","/api/v2/suppliers/{supplierId}/listings","/api/v2/suppliers/{supplierId}/listings/{listingId}","/api/v2/suppliers/{supplierId}/listings/{listingId}/submit","/api/v2/suppliers/{supplierId}/listings/{listingId}/price-tiers","/api/v2/delivery/cities","/api/v2/delivery/areas","/api/v2/me/addresses","/api/v2/me/addresses/{addressId}","/api/v2/delivery/suppliers/{supplierId}/eligibility","/api/v2/admin/delivery/cities","/api/v2/admin/delivery/cities/{cityId}","/api/v2/admin/delivery/areas","/api/v2/admin/delivery/areas/{areaId}","/api/v2/suppliers/{supplierId}/delivery","/api/v2/suppliers/{supplierId}/delivery/areas/{areaId}","/api/v2/suppliers/{supplierId}/delivery/areas/{areaId}/flat-rate","/api/v2/suppliers/{supplierId}/inventory/warehouses","/api/v2/suppliers/{supplierId}/inventory/warehouses/{warehouseId}","/api/v2/suppliers/{supplierId}/inventory/balances","/api/v2/suppliers/{supplierId}/inventory/warehouses/{warehouseId}/movements","/api/v2/suppliers/{supplierId}/inventory/adjustments","/api/v2/suppliers/{supplierId}/inventory/transfers","/api/v2/rfqs","/api/v2/rfqs/{rfqId}","/api/v2/rfqs/{rfqId}/open","/api/v2/rfqs/{rfqId}/cancel","/api/v2/rfqs/{rfqId}/invitations/{supplierId}","/api/v2/rfqs/{rfqId}/quotes","/api/v2/rfqs/{rfqId}/quotes/{quoteId}/award","/api/v2/suppliers/{supplierId}/rfqs","/api/v2/suppliers/{supplierId}/rfqs/{rfqId}/quotes","/api/v2/admin/promotions","/api/v2/admin/promotions/{promotionId}","/api/v2/cart","/api/v2/cart/lines/{listingId}","/api/v2/cart/clear","/api/v2/checkouts","/api/v2/checkouts/{quoteId}","/api/v2/checkouts/{quoteId}/place","/api/v2/orders","/api/v2/orders/{orderId}","/api/v2/orders/{orderId}/cancel","/api/v2/orders/{orderId}/payments","/api/v2/webhooks/razorpay","/api/v2/orders/{orderId}/cod","/api/v2/orders/{orderId}/invoices","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/cod","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/invoices","/api/v2/admin/finance/cod/{receiptId}/review","/api/v2/suppliers/{supplierId}/orders","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/accept","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/reject","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/shipments","/api/v2/suppliers/{supplierId}/shipments/{shipmentId}/pack","/api/v2/suppliers/{supplierId}/shipments/{shipmentId}/dispatch","/api/v2/suppliers/{supplierId}/shipments/{shipmentId}/out-for-delivery","/api/v2/suppliers/{supplierId}/shipments/{shipmentId}/handover","/api/v2/orders/{orderId}/shipments","/api/v2/orders/{orderId}/shipments/{shipmentId}/otp","/api/v2/admin/shipments/{shipmentId}/exception-approve","/api/v2/orders/{orderId}/returns","/api/v2/returns/{returnId}/cancel","/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/returns","/api/v2/suppliers/{supplierId}/returns/{returnId}/receive","/api/v2/admin/returns","/api/v2/admin/returns/{returnId}/review","/api/v2/support/cases","/api/v2/support/cases/{caseId}","/api/v2/support/cases/{caseId}/messages","/api/v2/admin/support/cases","/api/v2/admin/support/cases/{caseId}","/api/v2/admin/support/cases/{caseId}/messages","/api/v2/orders/{orderId}/reviews","/api/v2/suppliers/{supplierId}/reviews","/api/v2/suppliers/{supplierId}/reviews/manage","/api/v2/admin/reviews","/api/v2/admin/reviews/{reviewId}/moderate","/api/v2/suppliers/{supplierId}/finance/statement","/api/v2/admin/finance/suppliers/{supplierId}","/api/v2/admin/finance/settlements/drafts","/api/v2/admin/finance/settlements/{settlementId}/approve","/api/v2/admin/finance/settlements/{settlementId}/cancel","/api/v2/admin/finance/cod-commissions/{supplierOrderId}/recognize","/api/v2/admin/finance/journals/{journalId}","/api/v2/suppliers/{supplierId}/returns/{returnId}/credit-note","/api/v2/orders/{orderId}/refunds","/api/v2/admin/finance/refunds","/api/v2/admin/finance/refunds/requests/{returnId}","/api/v2/admin/finance/refunds/{refundId}/approve","/api/v2/admin/finance/refunds/{refundId}/reconcile","/api/v2/suppliers/{supplierId}/finance/beneficiaries","/api/v2/suppliers/{supplierId}/finance/payouts","/api/v2/admin/finance/suppliers/{supplierId}/beneficiaries","/api/v2/admin/finance/beneficiaries/{accountId}/approve","/api/v2/admin/finance/settlements/{settlementId}/payout-intent","/api/v2/admin/finance/payouts","/api/v2/admin/finance/payouts/{payoutId}/reconcile","/api/v2/admin/finance/payouts/{payoutId}/bank-attest","/api/v2/admin/finance/payouts-reconciliation,"/api/v2/admin/team","/api/v2/admin/team/{userId}","/api/v2/admin/team/{userId}/revoke""].sort());
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

test('staging boots its configuration without Redis credentials while keeping Clerk mandatory',()=>{
 const config=readConfig({
  BUILDTO_V21_ENV:'staging',
  DATABASE_URL:'postgresql://app:placeholder@ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech/neondb?sslmode=require',
  BUILDTO_V21_CORS_ORIGINS:'https://staging.buildto.test',
  CLERK_ISSUER:'https://example.clerk.accounts.dev',
  CLERK_SECRET_KEY:'sk_test_config-only',
  CLERK_WEBHOOK_SIGNING_SECRET:'whsec_placeholder',
  CLERK_AUTHORIZED_PARTIES:'https://staging.buildto.test',
 });
 assert.equal(config.environment,'staging');
 assert.equal(config.corsOrigins.length,1);
 assert(!('redisRestUrl' in config));
 assert(!('redisRestToken' in config));
});
