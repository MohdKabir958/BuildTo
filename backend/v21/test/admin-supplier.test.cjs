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
async function user(label){
 const u=await db.user.create({data:{clerkUserId:subject(),email:label+'-'+randomUUID()+'@example.test',displayName:label,status:'ACTIVE'}});
 return u;
}
const app=tokens=>createV21App({
 db,allowedOrigins:['https://admin.buildto.example'],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},
 identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}
});
const auth=(api,method,path,token,body)=>{
 const r=api[method](path).set('Authorization','Bearer '+token);
 return body===undefined?r:r.send(body);
};
const apply=(applicant)=>({
 slug:'supplier-'+randomUUID().slice(0,8),
 legalName:'Example Materials Pvt Ltd',displayName:'Example Materials',
 contactEmail:applicant.email,gstRegistration:'UNREGISTERED',
 billingAddress:{line1:'Main Building Road 42',city:'Hyderabad',state:'Telangana',pinCode:'500001'}
});
async function evidence(owner){
 return db.mediaAsset.create({data:{objectKey:'private/suppliers/'+randomUUID(),ownerUserId:owner.id,
  mimeType:'application/pdf',sizeBytes:BigInt(1024),sha256:'a'.repeat(64)}});
}
test('A05: signed-in applicant cannot use supplier endpoints before independent approval; reviewed evidence unlocks owner',async()=>{
 const applicant=await user('applicant'),operator=await user('operator');
 await db.adminMembership.create({data:{userId:operator.id,role:'OPERATIONS',active:true}});
 const api=request(app({applicant:applicant.clerkUserId,operator:operator.clerkUserId}));
 const submitted=await auth(api,'post','/api/v2/supplier-applications','applicant',apply(applicant));
 assert.equal(submitted.status,201,JSON.stringify(submitted.body));
 const id=submitted.body.data.id;
 assert.equal(submitted.body.data.approval,'PENDING');
 assert.equal((await auth(api,'get','/api/v2/suppliers/'+id+'/access','applicant')).status,404);
 assert.equal((await auth(api,'get','/api/v2/admin/suppliers','applicant')).status,403);
 const first=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/review','operator',{decision:'APPROVED',reason:'Verified business identity and records'});
 assert.equal(first.status,409,'Unverified documents must block approval');
 const media=await evidence(applicant);
 const attachment=await auth(api,'post','/api/v2/supplier-applications/'+id+'/documents','applicant',
  {mediaId:media.id,documentType:'BUSINESS_REGISTRATION'});
 assert.equal(attachment.status,201,JSON.stringify(attachment.body));
 const docId=attachment.body.data.id;
 const verified=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/documents/'+docId+'/review','operator',
  {decision:'VERIFIED',reason:'Document checked against registered business'});
 assert.equal(verified.status,200,JSON.stringify(verified.body));
 const approved=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/review','operator',
  {decision:'APPROVED',reason:'All required verified records checked'});
 assert.equal(approved.status,200,JSON.stringify(approved.body));
 assert.equal(approved.body.data.approval,'APPROVED');
 assert.equal((await auth(api,'get','/api/v2/suppliers/'+id+'/access','applicant')).status,200);
 const details=await auth(api,'get','/api/v2/admin/suppliers/'+id,'operator');
 assert.equal(details.status,200);
 assert.equal(details.body.data.documents[0].digestAvailable,true);
 assert(!JSON.stringify(details.body).includes(media.objectKey),'Do not expose private storage keys');
 const suspended=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/review','operator',
  {decision:'SUSPENDED',reason:'Verified compliance investigation opened'});
 assert.equal(suspended.status,200);
 assert.equal((await auth(api,'get','/api/v2/suppliers/'+id+'/access','applicant')).status,404);
 const audit=await db.auditEvent.findMany({where:{entityType:'Supplier',entityId:id}});
 assert(audit.some(a=>a.action==='SUPPLIER_APPROVAL_CHANGED'));
});
test('A05: self-review, unrelated evidence and invalid contacts fail closed',async()=>{
 const member=await user('member'),other=await user('other');
 await db.adminMembership.create({data:{userId:member.id,role:'OWNER',active:true}});
 const api=request(app({member:member.clerkUserId,other:other.clerkUserId}));
 const invalid=await auth(api,'post','/api/v2/supplier-applications','member',
  {...apply(member),contactEmail:other.email});
 assert.equal(invalid.status,403);
 const submitted=await auth(api,'post','/api/v2/supplier-applications','member',apply(member));
 assert.equal(submitted.status,201);
 const id=submitted.body.data.id;
 const media=await evidence(other);
 assert.equal((await auth(api,'post','/api/v2/supplier-applications/'+id+'/documents','member',
  {mediaId:media.id,documentType:'BUSINESS_REGISTRATION'})).status,403);
 assert.equal((await auth(api,'post','/api/v2/supplier-applications/'+id+'/documents','other',
  {mediaId:media.id,documentType:'BUSINESS_REGISTRATION'})).status,404);
 assert.equal((await auth(api,'post','/api/v2/admin/suppliers/'+id+'/review','member',
  {decision:'REJECTED',reason:'Cannot review own supplier application'})).status,403);
 assert.equal((await auth(api,'get','/api/v2/admin/suppliers','other')).status,403);
});
test('A05: registered GST suppliers require separately verified current GST evidence',async()=>{
 const applicant=await user('gst-applicant'),admin=await user('gst-reviewer');
 await db.adminMembership.create({data:{userId:admin.id,role:'OPERATIONS',active:true}});
 const api=request(app({applicant:applicant.clerkUserId,admin:admin.clerkUserId}));
 const result=await auth(api,'post','/api/v2/supplier-applications','applicant',{
  ...apply(applicant),gstRegistration:'REGULAR',gstin:'36'+randomUUID().replaceAll('-','').slice(0,5).toUpperCase().replace(/[0-9]/g,x=>String.fromCharCode(65+Number(x)))+randomUUID().replaceAll('-','').slice(0,4).replace(/[a-f]/g,x=>String(parseInt(x,16)%10))+'A1Z5'
 });
 assert.equal(result.status,201,JSON.stringify(result.body));
 const id=result.body.data.id;
 const asset=await evidence(applicant);
 const doc=await auth(api,'post','/api/v2/supplier-applications/'+id+'/documents','applicant',
  {mediaId:asset.id,documentType:'BUSINESS_REGISTRATION'});
 assert.equal(doc.status,201);
 const check=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/documents/'+doc.body.data.id+'/review','admin',
  {decision:'VERIFIED',reason:'Government business registration checked'});
 assert.equal(check.status,200);
 const noGst=await auth(api,'post','/api/v2/admin/suppliers/'+id+'/review','admin',
  {decision:'APPROVED',reason:'Check both verification requirements'});
 assert.equal(noGst.status,409);
});
