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
const subject=()=> 'user_'+randomUUID().replaceAll('-','');
async function createUser(label) {
 const id=randomUUID();
 return db.user.create({data:{
   clerkUserId:subject(),email:label+'-'+id+'@example.test',displayName:label+' '+id.slice(0,8),status:'ACTIVE'
 }});
}
const app=tokens=>createV21App({
 db,allowedOrigins:['https://admin.buildto.example'],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
   if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
   return {subject:tokens[token],sessionId:'sess_'+token.replace(/[^a-zA-Z0-9]/g,'')};
 }}
});
const auth=(api,method,path,token,body)=>{
 const r=api[method](path).set('Authorization','Bearer '+token);
 return body===undefined?r:r.send(body);
};
test('A04: OWNER can grant, list, change role and revoke a previously verified Clerk account; all actions audited',async()=>{
 const owner=await createUser('owner'),target=await createUser('catalog');
 await db.adminMembership.create({data:{userId:owner.id,role:'OWNER',active:true}});
 const api=request(app({owner:owner.clerkUserId,catalog:target.clerkUserId}));
 const reason='Approved by marketplace operator';
 const initial=await auth(api,'get','/api/v2/admin/team','owner');
 assert.equal(initial.status,200);
 assert(initial.body.data.items.some(x=>x.userId===owner.id&&x.role==='OWNER'));
 const granted=await auth(api,'post','/api/v2/admin/team','owner',{
   email:target.email,role:'CATALOG',reason,
 });
 assert.equal(granted.status,201,JSON.stringify(granted.body));
 assert.equal(granted.body.data.role,'CATALOG');
 assert.equal(granted.body.data.email,target.email);
 assert.equal(granted.body.data.active,true);
 assert.equal((await auth(api,'get','/api/v2/admin/access','catalog')).status,200);
 const changed=await auth(api,'patch','/api/v2/admin/team/'+target.id,'owner',{
   role:'SUPPORT',reason:'Reassign to customer service desk',
 });
 assert.equal(changed.status,200,JSON.stringify(changed.body));
 assert.equal(changed.body.data.role,'SUPPORT');
 const revoked=await auth(api,'post','/api/v2/admin/team/'+target.id+'/revoke','owner',{
   reason:'Access no longer required',
 });
 assert.equal(revoked.status,200);
 assert.equal(revoked.body.data.active,false);
 assert.equal((await auth(api,'get','/api/v2/admin/access','catalog')).status,403);
 const audits=await db.auditEvent.findMany({where:{entityType:'AdminMembership',entityId:target.id},orderBy:{createdAt:'asc'}});
 assert.equal(audits.length,3);
 assert.deepEqual(audits.map(x=>x.action),['ADMIN_ACCESS_GRANTED','ADMIN_ROLE_CHANGED','ADMIN_ACCESS_REVOKED']);
 assert(audits.every(x=>x.actorUserId===owner.id));
});
test('A04: role checks, verified account requirement and self-management fail closed',async()=>{
 const owner=await createUser('owner'),viewer=await createUser('viewer'),pending=await createUser('pending');
 await db.adminMembership.create({data:{userId:owner.id,role:'OWNER',active:true}});
 await db.adminMembership.create({data:{userId:viewer.id,role:'CATALOG',active:true}});
 const api=request(app({owner:owner.clerkUserId,viewer:viewer.clerkUserId,pending:pending.clerkUserId}));
 assert.equal((await auth(api,'get','/api/v2/admin/team','viewer')).status,403);
 assert.equal((await auth(api,'post','/api/v2/admin/team','viewer',{
   email:pending.email,role:'OWNER',reason:'Unauthorized role grant',
 })).status,403);
 assert.equal((await auth(api,'get','/api/v2/admin/team','pending')).status,403);
 assert.equal((await auth(api,'post','/api/v2/admin/team','owner',{
   email:owner.email,role:'CATALOG',reason:'Cannot change own role',
 })).status,409);
 assert.equal((await auth(api,'post','/api/v2/admin/team/'+owner.id+'/revoke','owner',{
   reason:'Cannot revoke own account',
 })).status,409);
 assert.equal((await auth(api,'post','/api/v2/admin/team','owner',{
   email:'unknown-'+randomUUID()+'@example.test',role:'FINANCE',reason:'Unrecognized account',
 })).status,404);
 assert.equal((await auth(api,'post','/api/v2/admin/team','owner',{
   email:pending.email,role:'SUPERUSER',reason:'Invalid role',
 })).status,400);
 assert.equal((await auth(api,'post','/api/v2/admin/team','owner',{
   email:pending.email,role:'FINANCE',reason:'short',
 })).status,400);
 assert.equal(await db.adminMembership.count({where:{userId:pending.id}}),0);
});
test('A04: concurrent duplicate grants cannot create two active memberships or duplicate audit',async()=>{
 const owner=await createUser('owner'),target=await createUser('finance');
 await db.adminMembership.create({data:{userId:owner.id,role:'OWNER',active:true}});
 const api=request(app({owner:owner.clerkUserId}));
 const input={email:target.email,role:'FINANCE',reason:'Finance operator verified by owner'};
 const results=await Promise.all([
   auth(api,'post','/api/v2/admin/team','owner',input),
   auth(api,'post','/api/v2/admin/team','owner',input),
 ]);
 assert.deepEqual(results.map(r=>r.status).sort(),[201,409]);
 assert.equal(await db.adminMembership.count({where:{userId:target.id,role:'FINANCE',active:true}}),1);
 assert.equal(await db.auditEvent.count({where:{entityType:'AdminMembership',entityId:target.id,action:'ADMIN_ACCESS_GRANTED'}}),1);
});
