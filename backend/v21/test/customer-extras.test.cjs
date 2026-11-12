'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('../../generated/buildto-v21');
const {customerWishlist,saveWishlist,removeWishlist,customerNotifications,markCustomerNotificationRead}=require('../dist/customer-extras-service.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
test('owned wishlist is repeat-safe, private, and requires published supplier listing',async()=>{
 const user=await db.user.create({data:{displayName:'Wishlist test'}});
 const other=await db.user.create({data:{displayName:'Other wishlist'}});
 const supplier=await db.supplier.create({data:{slug:'wishlist-'+randomUUID(),displayName:'Materials Seller',legalName:'Seller Ltd',approval:'APPROVED'}});
 const category=await db.category.create({data:{slug:'wish-'+randomUUID(),name:'Wishlist Materials',active:true}});
 const product=await db.product.create({data:{code:'WISH-'+randomUUID(),categoryId:category.id,name:'Wishlist Cement',active:true}});
 const listing=await db.supplierListing.create({data:{
  supplierId:supplier.id,productId:product.id,sku:'WISH-'+randomUUID(),unitCode:'BAG',unitPrice:'100.0000',
  status:'APPROVED',active:true,publishedAt:new Date()
 }});
 assert.equal((await saveWishlist(db,user.id,listing.id)).created,true);
 assert.equal((await saveWishlist(db,user.id,listing.id)).created,false);
 assert.equal((await customerWishlist(db,user.id)).length,1);
 assert.deepEqual(await customerWishlist(db,other.id),[]);
 assert.equal((await removeWishlist(db,other.id,listing.id)).removed,false);
 assert.equal((await removeWishlist(db,user.id,listing.id)).removed,true);
 assert.equal((await removeWishlist(db,user.id,listing.id)).removed,false);
 await db.supplierListing.update({where:{id:listing.id},data:{status:'SUSPENDED',active:false}});
 await assert.rejects(saveWishlist(db,user.id,listing.id),e=>e.code==='NOT_FOUND');
});
test('notifications are private, limited and idempotently marked read',async()=>{
 const a=await db.user.create({data:{displayName:'Inbox A'}});
 const b=await db.user.create({data:{displayName:'Inbox B'}});
 const notification=await db.notification.create({data:{userId:a.id,kind:'SYSTEM',title:'Test',body:'Private'}});
 assert.equal((await customerNotifications(db,a.id)).items.length,1);
 assert.equal((await customerNotifications(db,b.id)).items.length,0);
 await assert.rejects(markCustomerNotificationRead(db,b.id,notification.id),e=>e.code==='NOT_FOUND');
 assert.equal((await markCustomerNotificationRead(db,a.id,notification.id)).read,true);
 assert.equal((await markCustomerNotificationRead(db,a.id,notification.id)).read,true);
});
