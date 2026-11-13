import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {uuid,cartChange,cartVersion,checkedQuantity} from './checkout-validation';

type Tx=Prisma.TransactionClient;
const itemsSelect={id:true,version:true,updatedAt:true,lines:{
 select:{listingId:true,quantity:true,listing:{
 select:{sku:true,unitCode:true,unitPrice:true,minOrderQty:true,stepQty:true,maxOrderQty:true,active:true,status:true,deletedAt:true,
  supplier:{select:{id:true,displayName:true,approval:true,suspendedAt:true}},
  product:{select:{name:true,imageUrl:true,active:true,category:{select:{active:true}}}},
 }}},orderBy:{listingId:'asc' as const}
}} as const;
function dto(cart:any){
 return {version:cart?.version??0,updatedAt:cart?.updatedAt?.toISOString()??null,
  items:(cart?.lines??[]).map((x:any)=>({
   listingId:x.listingId,quantity:x.quantity.toString(),sku:x.listing.sku,
   unitCode:x.listing.unitCode,displayName:x.listing.product.name,
   supplierId:x.listing.supplier.id,supplierName:x.listing.supplier.displayName,
   unitPrice:x.listing.unitPrice.toString(),imageUrl:x.listing.product.imageUrl,
   minOrderQty:x.listing.minOrderQty.toString(),stepQty:x.listing.stepQty.toString(),maxOrderQty:x.listing.maxOrderQty?.toString()??null,
   available:x.listing.active&&x.listing.status==='APPROVED'&&!x.listing.deletedAt&&
    x.listing.product.active&&x.listing.product.category.active&&
    x.listing.supplier.approval==='APPROVED'&&!x.listing.supplier.suspendedAt
  }))}
}
async function ownedCart(tx:Tx,userId:string) {
 const cart=await tx.cart.upsert({where:{customerId:userId},
  create:{customerId:userId},update:{},select:{id:true}});
 await tx.$queryRaw(Prisma.sql`SELECT id FROM "Cart" WHERE id=${cart.id}::uuid FOR UPDATE`);
 return tx.cart.findUniqueOrThrow({where:{id:cart.id},select:itemsSelect});
}
export async function readCart(db:PrismaClient,userId:string) {
 const cart=await db.cart.findUnique({where:{customerId:userId},select:itemsSelect});
 return dto(cart);
}
export async function putCartLine(db:PrismaClient,userId:string,listingId:string,input:unknown) {
 uuid(listingId,'listingId');
 const command=cartChange(input);
 return serializable(db,async tx=>{
  const cart=await ownedCart(tx,userId);
  if(cart.version!==command.expectedVersion)
   throw new ApiError(409,'CART_VERSION_CONFLICT','Refresh cart before editing.');
  const listing=await tx.supplierListing.findFirst({where:{
   id:listingId,status:'APPROVED',active:true,deletedAt:null,
   supplier:{approval:'APPROVED',suspendedAt:null},
   product:{active:true,category:{active:true}}
  },select:{id:true,minOrderQty:true,maxOrderQty:true,stepQty:true}});
  if(!listing)throw new ApiError(422,'LISTING_UNAVAILABLE','Product is not currently available.');
  checkedQuantity(listing,command.quantity);
  if(cart.lines.length>=30&&!cart.lines.some((x:any)=>x.listingId===listingId))
   throw new ApiError(422,'CART_LIMIT','Maximum 30 products per checkout.');
  await tx.cartLine.upsert({where:{cartId_listingId:{cartId:cart.id,listingId}},
   create:{cartId:cart.id,listingId,quantity:command.quantity},
   update:{quantity:command.quantity}
  });
  const updated=await tx.cart.update({where:{id:cart.id},
   data:{version:{increment:1}},select:itemsSelect});
  return dto(updated);
 });
}
export async function removeCartLine(db:PrismaClient,userId:string,listingId:string,input:unknown){
 uuid(listingId,'listingId');const expected=cartVersion(input);
 return serializable(db,async tx=>{
  const cart=await ownedCart(tx,userId);
  if(cart.version!==expected)throw new ApiError(409,'CART_VERSION_CONFLICT','Refresh cart before editing.');
  const deleted=await tx.cartLine.deleteMany({where:{cartId:cart.id,listingId}});
  if(!deleted.count)throw new ApiError(404,'NOT_FOUND','Cart line not found.');
  const row=await tx.cart.update({where:{id:cart.id},
   data:{version:{increment:1}},select:itemsSelect});
  return dto(row);
 });
}
export async function clearCart(db:PrismaClient,userId:string,input:unknown){
 const expected=cartVersion(input);
 return serializable(db,async tx=>{
  const cart=await ownedCart(tx,userId);
  if(cart.version!==expected)throw new ApiError(409,'CART_VERSION_CONFLICT','Refresh cart before editing.');
  await tx.cartLine.deleteMany({where:{cartId:cart.id}});
  const row=await tx.cart.update({where:{id:cart.id},data:{version:{increment:1}},select:itemsSelect});
  return dto(row);
 });
}
