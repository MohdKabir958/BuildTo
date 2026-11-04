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
async function user(label){
  return db.user.create({data:{clerkUserId:'user_'+randomUUID().replaceAll('-',''),
    displayName:label,email:label+'-'+randomUUID()+'@example.test',status:'ACTIVE'}});
}
const app=tokens=>createV21App({db,allowedOrigins:[],proxyHops:0,
  limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
    if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Sign in required.');
    return {subject:tokens[token],sessionId:'sess_'+token};
  }}});
const get=(api,path,token)=>api.get(path).set('Authorization','Bearer '+token);

test('A13: refund candidates and masked beneficiaries enforce independent FINANCE role',async()=>{
  const finance=await user('moneyFinance'),owner=await user('moneyOwner');
  const support=await user('moneySupport'),customer=await user('moneyCustomer');
  await db.adminMembership.createMany({data:[
    {userId:finance.id,role:'FINANCE',active:true},
    {userId:owner.id,role:'OWNER',active:true},
    {userId:support.id,role:'SUPPORT',active:true}
  ]});
  const supplier=await db.supplier.create({data:{
    slug:'a13-'+randomUUID(),legalName:'Secure Materials Supplier',
    displayName:'Secure Materials Supplier',approval:'APPROVED'
  }});
  await db.supplierPayoutAccount.create({data:{
    supplierId:supplier.id,bankAccountLast4:'9876',
    providerTokenRef:'fa_'+randomUUID().replaceAll('-',''),
    validationRef:'fav_'+randomUUID().replaceAll('-',''),
    accountHolder:'PRIVATE_BANK_NAME',ifsc:'ABCD0000123',upiIdEnc:'PRIVATE_ENCRYPTED_TOKEN',
    active:false,registeredById:owner.id,approvedById:null,verifiedAt:null
  }});
  const api=request(app({fin:finance.clerkUserId,owner:owner.clerkUserId,
    support:support.clerkUserId,customer:customer.clerkUserId}));
  const candidates=await get(api,'/api/v2/admin/finance/refund-candidates?limit=5','fin');
  assert.equal(candidates.status,200,JSON.stringify(candidates.body));
  assert(Array.isArray(candidates.body.data.items));
  assert('nextCursor' in candidates.body.data);
  assert(candidates.body.data.items.every(x=>x.fullRefundEligible===false));
  const path='/api/v2/admin/finance/suppliers/'+supplier.id+'/beneficiaries';
  const beneficiary=await get(api,path,'fin');
  assert.equal(beneficiary.status,200,JSON.stringify(beneficiary.body));
  assert.equal(beneficiary.body.data.length,1);
  assert.equal(beneficiary.body.data[0].maskedBankAccount,'****9876');
  const serialized=JSON.stringify(beneficiary.body);
  for(const secret of ['PRIVATE_BANK_NAME','PRIVATE_ENCRYPTED_TOKEN','ABCD0000123','fa_','fav_']){
    assert(!serialized.includes(secret),'Leaked a sensitive bank field: '+secret);
  }
  assert.equal((await get(api,path,'owner')).status,200);
  assert.equal((await get(api,path,'support')).status,403);
  assert.equal((await get(api,path,'customer')).status,403);
  assert.equal((await api.get(path)).status,401);
  assert.equal((await get(api,'/api/v2/admin/finance/refund-candidates','support')).status,403);
  assert.equal((await get(api,'/api/v2/admin/finance/refund-candidates?limit=99','fin')).status,400);
  assert.equal((await get(api,'/api/v2/admin/finance/refund-candidates?cursor=bad','fin')).status,400);
});
