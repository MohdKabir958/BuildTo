import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {isUuid} from './permissions';

export async function customerWishlist(db:PrismaClient,userId:string){
 const rows=await db.wishlistItem.findMany({where:{customerId:userId},
  orderBy:{createdAt:'desc'},take:100,
  select:{listingId:true,createdAt:true,listing:{
   select:{sku:true,unitPrice:true,unitCode:true,status:true,active:true,deletedAt:true,
    product:{select:{id:true,name:true,active:true,category:{select:{active:true}}}},
    supplier:{select:{id:true,displayName:true,approval:true,suspendedAt:true}}}
  }}});
 return rows.map(x=>({listingId:x.listingId,addedAt:x.createdAt.toISOString(),
  productId:x.listing.product.id,productName:x.listing.product.name,
  supplierId:x.listing.supplier.id,supplierName:x.listing.supplier.displayName,
  sku:x.listing.sku,unitPrice:x.listing.unitPrice.toString(),unitCode:x.listing.unitCode,
  available:x.listing.status==='APPROVED'&&x.listing.active&&!x.listing.deletedAt&&
    x.listing.product.active&&x.listing.product.category.active&&
    x.listing.supplier.approval==='APPROVED'&&!x.listing.supplier.suspendedAt}));
}
export async function saveWishlist(db:PrismaClient,userId:string,listingId:string){
 if(!isUuid(listingId))throw new ApiError(404,'NOT_FOUND','Listing not found.');
 return serializable(db,async tx=>{
  await tx.$queryRaw(Prisma.sql`SELECT id FROM "User" WHERE id=${userId}::uuid FOR UPDATE`);
  const listing=await tx.supplierListing.findFirst({where:{
   id:listingId,active:true,status:'APPROVED',deletedAt:null,publishedAt:{not:null},
   supplier:{approval:'APPROVED',suspendedAt:null},product:{active:true,category:{active:true}}
  },select:{id:true}});
  if(!listing)throw new ApiError(404,'NOT_FOUND','Listing is not available.');
  const existing=await tx.wishlistItem.findUnique({where:{customerId_listingId:{customerId:userId,listingId}},select:{createdAt:true}});
  if(existing)return {listingId,addedAt:existing.createdAt.toISOString(),created:false};
  const count=await tx.wishlistItem.count({where:{customerId:userId}});
  if(count>=100)throw new ApiError(422,'WISHLIST_LIMIT','Wishlist cannot exceed 100 listings.');
  const created=await tx.wishlistItem.create({data:{customerId:userId,listingId},select:{createdAt:true}});
  return {listingId,addedAt:created.createdAt.toISOString(),created:true};
 });
}
export async function removeWishlist(db:PrismaClient,userId:string,listingId:string){
 if(!isUuid(listingId))throw new ApiError(404,'NOT_FOUND','Listing not found.');
 const result=await db.wishlistItem.deleteMany({where:{customerId:userId,listingId}});
 return {removed:result.count>0};
}
export async function customerNotifications(db:PrismaClient,userId:string,cursor?:string){
 if(cursor && !isUuid(cursor))throw new ApiError(400,'INVALID_CURSOR','Invalid notification cursor.');
 const items=await db.notification.findMany({where:{userId},
  select:{id:true,kind:true,title:true,body:true,deepLink:true,payload:true,readAt:true,createdAt:true},
  orderBy:[{createdAt:'desc'},{id:'desc'}],take:51,
  ...(cursor?{cursor:{id:cursor},skip:1}:{})
 });
 return {items:items.slice(0,50).map(x=>({...x,createdAt:x.createdAt.toISOString(),
  readAt:x.readAt?.toISOString()??null})),
  nextCursor:items.length>50?items[49].id:null};
}
export async function markCustomerNotificationRead(db:PrismaClient,userId:string,notificationId:string){
 if(!isUuid(notificationId))throw new ApiError(404,'NOT_FOUND','Notification not found.');
 const existing=await db.notification.findFirst({where:{id:notificationId,userId},
  select:{id:true,readAt:true}});
 if(!existing)throw new ApiError(404,'NOT_FOUND','Notification not found.');
 if(!existing.readAt)await db.notification.updateMany({
  where:{id:notificationId,userId,readAt:null},data:{readAt:new Date()}
 });
 return {id:notificationId,read:true};
}
