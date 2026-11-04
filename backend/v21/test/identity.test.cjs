'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,createHmac}=require('node:crypto');
const request=require('supertest');
const {PrismaClient}=require('../../generated/buildto-v21');
const {ApiError}=require('../dist/errors.js');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {requireSupplierPermission,requireAdminPermission,SUPPLIER_PERMISSIONS,ADMIN_PERMISSIONS}=require('../dist/permissions.js');
const {verifyClerkWebhook}=require('../dist/clerk-webhooks.js');

const db=new PrismaClient();
test.after(async()=>db.$disconnect());
const subject=()=> 'user_'+randomUUID().replaceAll('-','');
const name=()=> 'CI '+randomUUID().slice(0,12);
const supplierData=()=>({slug:'ci-'+randomUUID(),legalName:name()+' Ltd',displayName:name(),approval:'APPROVED'});
const secret='whsec_'+Buffer.from('0123456789abcdef0123456789abcdef').toString('base64');
const signing=(body,id='msg_'+randomUUID().replaceAll('-',''),time=Math.floor(Date.now()/1000))=>{
  const raw=Buffer.from(JSON.stringify(body));
  const sig=createHmac('sha256',Buffer.from(secret.slice(6),'base64'))
   .update(id+'.'+time+'.').update(raw).digest('base64');
  return {raw,id,ts:String(time),sig:'v1,'+sig};
};
const app=(tokens={})=>createV21App({
  db,allowedOrigins:['https://staging.buildto.example'],proxyHops:0,
  limiter:new InMemoryTestLimiter(),log:()=>{},clerkWebhookSecret:secret,
  identityVerifier:{verify:async token=>{
    if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Authentication required or session expired.');
    return {subject:tokens[token],sessionId:'sess_'+token.replace(/[^a-zA-Z0-9]/g,'')};
  }}
});
async function webhook(client,body,options={}) {
  const sig=signing(body,options.id,options.time);
  return client.post('/api/v2/webhooks/clerk').set('Content-Type','application/json')
    .set('svix-id',sig.id).set('svix-timestamp',sig.ts)
    .set('svix-signature',options.signature||sig.sig).send(sig.raw.toString('utf8'));
}
test('signed webhook creates identity; duplicate returns receipt without changes',async()=>{
  const actor=subject(),client=request(app({}));
  const first=await webhook(client,{type:'user.created',data:{id:actor,first_name:'Build',last_name:'Tester'}});
  assert.equal(first.status,200);assert.equal(first.body.duplicate,false);
  const stored=await db.user.findUniqueOrThrow({where:{clerkUserId:actor}});
  assert.equal(stored.displayName,'Build Tester');
  assert.equal(stored.status,'ACTIVE');
  assert.equal(await db.adminMembership.count({where:{userId:stored.id}}),0);
  assert.equal(await db.supplierMember.count({where:{userId:stored.id}}),0);
  // Verbatim provider retry is idempotent by signed message id, not just user id.
  const signed=signing({type:'user.updated',data:{id:actor,first_name:'New',last_name:'Name'}});
  const send=()=>client.post('/api/v2/webhooks/clerk').set('Content-Type','application/json')
   .set('svix-id',signed.id).set('svix-timestamp',signed.ts).set('svix-signature',signed.sig).send(signed.raw.toString('utf8'));
  assert.equal((await send()).body.duplicate,false);
  assert.equal((await send()).body.duplicate,true);
  assert.equal((await db.user.findUniqueOrThrow({where:{id:stored.id}})).displayName,'New Name');
});
test('signature, timestamp and original payload are mandatory',async()=>{
  const payload={type:'user.created',data:{id:subject(),first_name:'Test'}};
  const good=signing(payload);
  const verified=verifyClerkWebhook(good.raw,{id:good.id,timestamp:good.ts,signature:good.sig},secret);
  assert.equal(verified.event.type,'user.created');
  assert.throws(()=>verifyClerkWebhook(Buffer.from('{}'),{id:good.id,timestamp:good.ts,signature:good.sig},secret),
    e=>e.code==='INVALID_WEBHOOK_SIGNATURE');
  assert.throws(()=>verifyClerkWebhook(good.raw,{id:good.id,timestamp:good.ts,signature:'v1,AAAA'},secret),
    e=>e.code==='INVALID_WEBHOOK_SIGNATURE');
  assert.throws(()=>verifyClerkWebhook(good.raw,{id:good.id,timestamp:String(Math.floor(Date.now()/1000)-601),signature:good.sig},secret),
    e=>e.code==='INVALID_WEBHOOK_SIGNATURE');
  assert.equal((await request(app()).post('/api/v2/webhooks/clerk').set('Content-Type','application/json').send(JSON.stringify(payload))).status,401);
});
test('deleted identity is tombstoned and cannot regain permissions from stale updates',async()=>{
  const actor=subject(),client=request(app({valid:actor}));
  assert.equal((await webhook(client,{type:'user.created',data:{id:actor,first_name:'Before'}})).status,200);
  const user=await db.user.findUniqueOrThrow({where:{clerkUserId:actor}});
  const supplier=await db.supplier.create({data:supplierData()});
  await db.supplierMember.create({data:{supplierId:supplier.id,userId:user.id,active:true,role:'OWNER'}});
  await db.adminMembership.create({data:{userId:user.id,role:'OWNER',active:true}});
  assert.equal((await webhook(client,{type:'user.deleted',data:{id:actor,deleted:true}})).status,200);
  const deleted=await db.user.findUniqueOrThrow({where:{id:user.id}});
  assert.equal(deleted.status,'CLOSED');assert(deleted.deletedAt);
  assert.equal((await db.supplierMember.findUniqueOrThrow({where:{supplierId_userId:{supplierId:supplier.id,userId:user.id}}})).active,false);
  assert.equal((await db.adminMembership.findUniqueOrThrow({where:{userId:user.id}})).active,false);
  assert.equal((await webhook(client,{type:'user.updated',data:{id:actor,first_name:'Stale'}})).status,200);
  assert.equal((await db.user.findUniqueOrThrow({where:{id:user.id}})).status,'CLOSED');
  const denied=await client.get('/api/v2/me').set('Authorization','Bearer valid').set('x-request-id','unit_test_123456');
  assert.equal(denied.status,403);
  assert.equal(denied.body.error.code,'ACCOUNT_SUSPENDED');
});
test('unknown token and missing DB identity are denied; no self-provisioning from token claims',async()=>{
 const actor=subject(),client=request(app({valid:actor}));
 assert.equal((await client.get('/api/v2/me')).status,401);
 assert.equal((await client.get('/api/v2/me').set('Authorization','Bearer bogus')).status,401);
 const missing=await client.get('/api/v2/me').set('Authorization','Bearer valid');
 assert.equal(missing.status,403);
 assert.equal(missing.body.error.code,'PROFILE_NOT_PROVISIONED');
 assert.equal(await db.user.count({where:{clerkUserId:actor}}),0);
});
test('only active membership on an approved supplier grants supplier access',async()=>{
 const actor=subject(),other=subject();
 const [user,outsider]=await Promise.all([
 db.user.create({data:{clerkUserId:actor,displayName:'Owner'}}),
 db.user.create({data:{clerkUserId:other,displayName:'Outsider'}}),
 ]);
 const supplier=await db.supplier.create({data:supplierData()});
 const client=request(app({owner:actor,stranger:other}));
 const route='/api/v2/suppliers/'+supplier.id+'/access';
 assert.equal((await client.get(route).set('Authorization','Bearer owner')).status,404);
 await db.supplierMember.create({data:{supplierId:supplier.id,userId:user.id,role:'CATALOG',active:true}});
 const granted=await client.get(route).set('Authorization','Bearer owner');
 assert.equal(granted.status,200);assert.equal(granted.body.data.role,'CATALOG');
 assert.equal((await client.get(route).set('Authorization','Bearer stranger')).status,404);
 await assert.rejects(requireSupplierPermission(db,user.id,supplier.id,'INVENTORY_WRITE'),e=>e.status===403);
 assert.deepEqual((await client.get('/api/v2/me').set('Authorization','Bearer owner')).body.data.suppliers,
   [{supplierId:supplier.id,role:'CATALOG'}]);
 await db.supplierMember.update({where:{supplierId_userId:{supplierId:supplier.id,userId:user.id}},data:{active:false,revokedAt:new Date()}});
 assert.equal((await client.get(route).set('Authorization','Bearer owner')).status,404);
 await db.supplierMember.update({where:{supplierId_userId:{supplierId:supplier.id,userId:user.id}},data:{active:true,revokedAt:null}});
 await db.supplier.update({where:{id:supplier.id},data:{approval:'SUSPENDED',suspendedAt:new Date()}});
 assert.equal((await client.get(route).set('Authorization','Bearer owner')).status,404);
 // No blanket admin bypass of supplier-specific object ownership.
 assert.equal((await client.get(route).set('Authorization','Bearer stranger')).status,404);
});
test('active administrator membership grants only explicitly permitted actions',async()=>{
 const actor=subject(),user=await db.user.create({data:{clerkUserId:actor,displayName:'Admin candidate'}});
 const client=request(app({admin:actor}));
 assert.equal((await client.get('/api/v2/admin/access').set('Authorization','Bearer admin')).status,403);
 await db.adminMembership.create({data:{userId:user.id,role:'AUDITOR',active:true}});
 const granted=await client.get('/api/v2/admin/access').set('Authorization','Bearer admin');
 assert.equal(granted.status,200);assert.equal(granted.body.data.role,'AUDITOR');
 await assert.rejects(requireAdminPermission(db,user.id,'TEAM_MANAGE'),e=>e.status===403);
 assert.equal((await requireAdminPermission(db,user.id,'AUDIT_READ')).role,'AUDITOR');
 await db.adminMembership.update({where:{userId:user.id},data:{revokedAt:new Date(),active:false}});
 assert.equal((await client.get('/api/v2/admin/access').set('Authorization','Bearer admin')).status,403);
});
test('each supplier/admin role has explicit action membership only',()=>{
 assert(SUPPLIER_PERMISSIONS.OWNER.includes('MEMBERS_MANAGE'));
 assert(!SUPPLIER_PERMISSIONS.CATALOG.includes('FINANCE_READ'));
 assert(!SUPPLIER_PERMISSIONS.VIEWER.includes('INVENTORY_WRITE'));
 assert(ADMIN_PERMISSIONS.OWNER.includes('TEAM_MANAGE'));
 assert(!ADMIN_PERMISSIONS.AUDITOR.includes('SUPPLIER_APPROVE'));
 assert(!ADMIN_PERMISSIONS.SUPPORT.includes('FINANCE_MANAGE'));
});

test('Clerk primary verified contact sync, partial update preservation and unverified rejection',async()=>{
 const actor=subject(),client=request(app({}));
 const unique=randomUUID().replaceAll('-','').slice(0,14);
 const email='CI'+unique+'@example.test',phone='+919012345678';
 const primary={
  type:'user.created',data:{id:actor,first_name:'Primary',
   primary_email_address_id:'id_main',primary_phone_number_id:'phone_main',
   email_addresses:[
    {id:'id_other',email_address:'wrong@example.test',verification:{status:'verified'}},
    {id:'id_main',email_address:email,verification:{status:'verified'}}
   ],
   phone_numbers:[
    {id:'phone_other',phone_number:'+918888888888',verification:{status:'verified'}},
    {id:'phone_main',phone_number:phone,verification:{status:'verified'}}
   ]
  }
 };
 assert.equal((await webhook(client,primary)).status,200);
 let user=await db.user.findUniqueOrThrow({where:{clerkUserId:actor}});
 assert.equal(user.email,email.toLowerCase());assert.equal(user.phoneE164,phone);
 // Clerk user.updated can omit unchanged collections. Existing contact survives.
 assert.equal((await webhook(client,{type:'user.updated',data:{
  id:actor,first_name:'Renamed'}})).status,200);
 user=await db.user.findUniqueOrThrow({where:{id:user.id}});
 assert.equal(user.email,email.toLowerCase());assert.equal(user.phoneE164,phone);
 assert.equal((await webhook(client,{type:'user.updated',data:{
  id:actor,primary_email_address_id:'id_unverified',
  email_addresses:[{id:'id_unverified',email_address:'attacker@example.test',
    verification:{status:'unverified'}}]
 }})).status,200);
 assert.equal((await db.user.findUniqueOrThrow({where:{id:user.id}})).email,null);
});
