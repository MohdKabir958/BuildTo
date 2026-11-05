'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const request=require('supertest');
const {PrismaClient}=require('../../generated/buildto-v21');
const {createV21App}=require('../dist/app.js');
const {InMemoryTestLimiter}=require('../dist/rateLimit.js');
const {ApiError}=require('../dist/errors.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
async function user(name){
  return db.user.create({data:{clerkUserId:'user_'+randomUUID().replaceAll('-',''),
    displayName:name,email:name+'-'+randomUUID()+'@example.test',status:'ACTIVE'}});
}
const app=users=>createV21App({db,allowedOrigins:[],proxyHops:0,
  limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
    if(!users[token])throw new ApiError(401,'INVALID_SESSION','Not signed in.');
    return {subject:users[token],sessionId:'sess_'+token};
  }}});
const get=(api,url,token)=>api.get(url).set('Authorization','Bearer '+token);

test('A14: only AUDIT_READ roles can inspect bounded redacted events',async()=>{
  const auditor=await user('auditAuditor'),owner=await user('auditOwner');
  const finance=await user('auditFinance'),outsider=await user('auditOutsider');
  await db.adminMembership.createMany({data:[
    {userId:auditor.id,role:'AUDITOR',active:true},
    {userId:owner.id,role:'OWNER',active:true},
    {userId:finance.id,role:'FINANCE',active:true},
  ]});
  const token='TEST_A14_'+randomUUID().replaceAll('-','').toUpperCase();
  for(let i=0;i<3;i++)await db.auditEvent.create({data:{
    actorUserId:owner.id,actorRole:'ADMIN_OWNER',action:token,
    entityType:'AuditEvent',entityId:randomUUID(),
    beforeState:{bankAccount:'SECRET_NEVER_EXPOSE',token:'private-session'},
    afterState:{email:'private@example.test',providerResponse:'SECRET_NEVER_EXPOSE'},
    ipHash:'do-not-expose',
  }});
  const api=request(app({auditor:auditor.clerkUserId,owner:owner.clerkUserId,
    finance:finance.clerkUserId,outsider:outsider.clerkUserId}));
  const url='/api/v2/admin/audit?limit=2&action='+token;
  const first=await get(api,url,'auditor');
  assert.equal(first.status,200,JSON.stringify(first.body));
  assert.equal(first.body.data.items.length,2);
  assert.match(first.body.data.nextCursor,/^[0-9a-f-]{36}$/i);
  assert.equal(typeof first.body.data.items[0].createdAt,'string');
  assert.equal(first.body.data.items[0].action,token);
  for(const item of first.body.data.items)assert.deepEqual(
    Object.keys(item).sort(),
    ['id','createdAt','action','entityType','entityId','actorRole','actorUserId'].sort()
  );
  assert(!JSON.stringify(first.body).includes('SECRET_NEVER_EXPOSE'));
  assert(!JSON.stringify(first.body).includes('private@example.test'));
  assert(!JSON.stringify(first.body).includes('ipHash'));
  const second=await get(api,url+'&cursor='+first.body.data.nextCursor,'auditor');
  assert.equal(second.status,200);
  assert.equal(second.body.data.items.length,1);
  assert.equal(second.body.data.nextCursor,null);
  assert.equal((await get(api,url,'owner')).status,200);
  assert.equal((await get(api,url,'finance')).status,403);
  assert.equal((await get(api,url,'outsider')).status,403);
  assert.equal((await api.get(url)).status,401);
});
test('A14: strict input validation fails closed',async()=>{
  const auditor=await user('auditQuery');
  await db.adminMembership.create({data:{userId:auditor.id,role:'AUDITOR',active:true}});
  const api=request(app({auditor:auditor.clerkUserId})),base='/api/v2/admin/audit';
  for(const query of ['?limit=51','?limit=0','?cursor=not-uuid','?entityType=..',
    '?action=SECRET%20TOKEN','?limit=2&limit=3']){
    const r=await get(api,base+query,'auditor');
    assert.equal(r.status,400,query+JSON.stringify(r.body));
  }
});
