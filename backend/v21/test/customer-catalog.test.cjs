const test=require('node:test');
const assert=require('node:assert/strict');
const {publicProducts,publicListings,publicSuppliers}=require('../dist/catalog-read');
const id='00000000-0000-4000-8000-000000000001';
test('customer product cards receive exact unit prices without internal listing rows',async()=>{
 let query;const db={product:{findMany:async input=>{query=input;return [{id,name:'Cement',listings:[{unitPrice:'390.50',unitCode:'BAG',taxInclusive:true}]}];}}};
 const data=await publicProducts(db,{supplierId:id});
 assert.equal(data.items[0].fromPrice,'390.50');assert.equal(data.items[0].fromUnit,'BAG');assert.equal(data.items[0].fromPriceTaxInclusive,true);
 assert.equal(data.items[0].listings,undefined);assert.equal(query.where.listings.some.supplierId,id);assert.equal(query.select.listings.where.supplierId,id);assert.equal(query.select.listings.where.supplier.approval,'APPROVED');
});
test('public storefront directory is bounded and selects no private supplier fields',async()=>{
 let query;const db={supplier:{findMany:async input=>{query=input;return Array.from({length:21},(_,i)=>({id:String(i),displayName:'Supplier '+i,profileImageId:id,publicLatitude:'17.4',publicLongitude:'78.4',contactEmail:'private@example.com'}));}}};
 const data=await publicSuppliers(db,undefined,'17.4','78.4');
 assert.equal(data.items.length,20);assert.equal(data.nextCursor,'19');assert.deepEqual(query.select,{id:true,displayName:true,profileImageId:true,publicLatitude:true,publicLongitude:true});
 assert.deepEqual(data.items[0],{id:'0',displayName:'Supplier 0',profileImageUrl:'/api/v2/catalog/images/'+id,latitude:'17.4',longitude:'78.4'});
 assert.ok(query.where.AND[0].publicLatitude.gte<17.4);assert.ok(query.where.AND[0].publicLongitude.lte>78.4);
 await assert.rejects(publicSuppliers(db,undefined,'17.4'));assert.equal(query.where.approval,'APPROVED');assert.equal(query.where.suspendedAt,null);assert.equal(query.where.listings.some.status,'APPROVED');
 await assert.rejects(publicSuppliers(db,'invalid'));
});
test('supplier offers expose display name and preserve approved-only publication filters',async()=>{
 let query;const db={supplierListing:{findMany:async input=>{query=input;return [{id,productId:id,supplierId:id,supplier:{displayName:'Local Materials'},sku:'CEM',unitCode:'BAG',packSize:'1',minOrderQty:'10',stepQty:'5',maxOrderQty:null,unitPrice:'390.00',mrpPaise:null,taxRateBps:1800,taxInclusive:true,status:'APPROVED',active:true,version:1,publishedAt:new Date(),priceTiers:[]}];}}};
 const offers=await publicListings(db,id);assert.equal(offers[0].supplierName,'Local Materials');assert.equal(offers[0].supplier,undefined);assert.equal(query.where.supplier.suspendedAt,null);assert.deepEqual(query.select.supplier,{select:{displayName:true}});
});
