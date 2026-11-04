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
async function user(label){return db.user.create({data:{
 clerkUserId:'user_'+randomUUID().replaceAll('-',''),email:label+'-'+randomUUID()+'@example.test',displayName:label,status:'ACTIVE'
}});}
const app=tokens=>createV21App({db,allowedOrigins:['https://admin.buildto.example'],proxyHops:0,
 limiter:new InMemoryTestLimiter(),log:()=>{},identityVerifier:{verify:async token=>{
  if(!tokens[token])throw new ApiError(401,'INVALID_SESSION','Invalid session');
  return {subject:tokens[token],sessionId:'sess_'+token};
 }}});
const get=(api,path,token)=>api.get(path).set('Authorization','Bearer '+token);
test('A07: admin reads inactive categories/brands/products, while unauthorized users cannot enumerate them',async()=>{
 const catalog=await user('catalog'),outsider=await user('outsider');
 await db.adminMembership.create({data:{userId:catalog.id,role:'CATALOG',active:true}});
 const api=request(app({catalog:catalog.clerkUserId,outsider:outsider.clerkUserId}));
 const slug='test-'+randomUUID().slice(0,8);
 const category=await db.category.create({data:{slug,name:'Inactive construction materials',active:false}});
 const brand=await db.brand.create({data:{slug:slug+'-brand',name:'Test Brand'}});
 const product=await db.product.create({data:{code:'MAT-'+randomUUID().slice(0,8),name:'Hidden cement',categoryId:category.id,brandId:brand.id,active:false}});
 assert.equal((await get(api,'/api/v2/catalog/categories','outsider')).status,200);
 const cat=await get(api,'/api/v2/admin/catalog/categories?limit=50','catalog');
 assert.equal(cat.status,200,JSON.stringify(cat.body));
 assert(cat.body.data.items.some(x=>x.id===category.id&&x.active===false));
 const brands=await get(api,'/api/v2/admin/catalog/brands?limit=50','catalog');
 assert.equal(brands.status,200);
 assert(brands.body.data.items.some(x=>x.id===brand.id));
 const products=await get(api,'/api/v2/admin/catalog/products?limit=50','catalog');
 assert.equal(products.status,200);
 assert(products.body.data.items.some(x=>x.id===product.id&&x.active===false));
 assert.equal((await get(api,'/api/v2/admin/catalog/categories','outsider')).status,403);
 assert.equal((await get(api,'/api/v2/admin/catalog/products','outsider')).status,403);
 assert.equal((await get(api,'/api/v2/admin/catalog/categories?limit=200','catalog')).status,400);
 assert.equal((await get(api,'/api/v2/admin/catalog/products?cursor=invalid','catalog')).status,400);
});
