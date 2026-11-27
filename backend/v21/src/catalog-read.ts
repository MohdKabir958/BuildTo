import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {uuid} from './catalog-validation';

const LISTING_DISCOVERED={
 status:'APPROVED' as const,active:true,deletedAt:null,publishedAt:{not:null},
 supplier:{approval:'APPROVED' as const,suspendedAt:null},
 product:{active:true,category:{active:true}},
 unit:{active:true},
};
const productSelect={
 id:true,code:true,name:true,description:true,hsnCode:true,specification:true,imageUrl:true,
 images:{where:{purpose:'CATALOG_IMAGE'},select:{id:true,position:true},orderBy:{position:'asc' as const},take:12},
 category:{select:{id:true,name:true,slug:true}},brand:{select:{id:true,name:true,slug:true}},
 listings:{where:LISTING_DISCOVERED,select:{unitPrice:true,unitCode:true,taxInclusive:true},orderBy:[{unitCode:'asc' as const},{unitPrice:'asc' as const}],take:1},
} as const;
function listingDTO(listing:any) {
 // A strict allowlist: no supplier contacts, private business data, stock, or ORM rows.
 const tiers=(listing.priceTiers||[]).map((tier:any)=>({
   minQty:tier.minQty.toString(),pricePerUnit:tier.pricePerUnit.toString(),
   effectiveFrom:tier.effectiveFrom.toISOString(),
   effectiveUntil:tier.effectiveUntil?.toISOString()??null,
 }));
 return {
   id:listing.id,productId:listing.productId,supplierId:listing.supplierId,
   supplierName:listing.supplier?.displayName??null,
   sku:listing.sku,unitCode:listing.unitCode,
   packSize:listing.packSize.toString(),minOrderQty:listing.minOrderQty.toString(),
   stepQty:listing.stepQty.toString(),maxOrderQty:listing.maxOrderQty?.toString()??null,
   unitPrice:listing.unitPrice.toString(),mrpPaise:listing.mrpPaise?.toString()??null,
   taxRateBps:listing.taxRateBps,taxInclusive:listing.taxInclusive,
   status:listing.status,active:listing.active,version:listing.version,
   productName:listing.product?.name??null,
   imageUrl:listing.product?.imageUrl??null,
   publishedAt:listing.publishedAt?.toISOString()??null,
   priceTiers:tiers,
 };
}
export {listingDTO};
export async function publicCategories(db:PrismaClient) {
 const categories=await db.category.findMany({
   where:{active:true},orderBy:[{displayOrder:'asc'},{slug:'asc'}],
   select:{id:true,parentId:true,slug:true,name:true,displayOrder:true},
   take:250,
 });
 return categories;
}
export async function publicBrands(db:PrismaClient) {
 // Brands have no active flag in V2.1. Only brands referenced by
 // active products in active categories are publicly discoverable.
 return db.brand.findMany({
   where:{products:{some:{active:true,category:{active:true}}}},
   select:{id:true,slug:true,name:true},orderBy:{name:'asc'},take:100,
 });
}
export async function publicUnits(db:PrismaClient) {
 return db.unitOfMeasure.findMany({where:{active:true},
  select:{code:true,name:true,dimension:true,scale:true},orderBy:{code:'asc'},take:100});
}
export async function publicProducts(db:PrismaClient,params:{categoryId?:string;cursor?:string;search?:string;supplierId?:string}) {
 if(params.supplierId)uuid(params.supplierId,'supplierId');
 if(params.categoryId)uuid(params.categoryId,'categoryId');
 if(params.cursor)uuid(params.cursor,'cursor');
 if(params.search!==undefined && (params.search.length>80||!/^[a-zA-Z0-9 ._\-/]+$/.test(params.search)))
   throw new ApiError(400,'INVALID_SEARCH','Invalid search filter.');
 const products=await db.product.findMany({
   where:{active:true,category:{active:true},
     ...(params.categoryId?{categoryId:params.categoryId}:{}),
     ...(params.supplierId?{listings:{some:{...LISTING_DISCOVERED,supplierId:params.supplierId}}}:{}),
     ...(params.search?{name:{contains:params.search,mode:'insensitive' as const}}:{})
   },
   select:{...productSelect,listings:{...productSelect.listings,orderBy:[...productSelect.listings.orderBy],where:{...LISTING_DISCOVERED,...(params.supplierId?{supplierId:params.supplierId}:{})}}},
   orderBy:{id:'asc'},take:26,
   ...(params.cursor?{cursor:{id:params.cursor},skip:1}:{})
 });
 const page=products.slice(0,25);
 return {items:page.map(({listings,...product})=>({...product,fromPrice:listings[0]?.unitPrice.toString()??null,fromUnit:listings[0]?.unitCode??null,fromPriceTaxInclusive:listings[0]?.taxInclusive??null})),nextCursor:products.length>25?page.at(-1)?.id??null:null};
}
export async function publicListings(db:PrismaClient,productId:string) {
 uuid(productId,'productId');
 const now=new Date();
 const rows=await db.supplierListing.findMany({
   where:{...LISTING_DISCOVERED,productId},
   select:{
     id:true,productId:true,supplierId:true,supplier:{select:{displayName:true}},sku:true,unitCode:true,
     packSize:true,minOrderQty:true,stepQty:true,maxOrderQty:true,
     unitPrice:true,mrpPaise:true,taxRateBps:true,taxInclusive:true,
     status:true,active:true,version:true,publishedAt:true,
     priceTiers:{where:{active:true,effectiveFrom:{lte:now},OR:[
       {effectiveUntil:null},{effectiveUntil:{gt:now}}
     ]},select:{minQty:true,pricePerUnit:true,effectiveFrom:true,effectiveUntil:true},
     orderBy:[{minQty:'asc'},{effectiveFrom:'desc'}],take:30}
   },orderBy:{id:'asc'},take:100,
 });
 return rows.map(listingDTO);
}

/** Public storefront directory. Never returns contacts, KYC, bank or warehouse data. */
// A narrow bounding box limits the query. The app checks the exact 1 km
// straight-line distance and sorts results from every matching page.
function storefrontBounds(latitude?:string,longitude?:string):Prisma.SupplierWhereInput {
 if(latitude===undefined&&longitude===undefined)return {};
 const valid=(value:string|undefined)=>value!==undefined&&/^-?\d{1,3}(?:\.\d{1,7})?$/.test(value);
 const lat=Number(latitude),lng=Number(longitude);
 if(!valid(latitude)||!valid(longitude)||Math.abs(lat)>90||Math.abs(lng)>180)
  throw new ApiError(400,'INVALID_COORDINATE','Provide valid latitude and longitude.');
 // Storefront coordinates are published only for the supported market.
 const deltaLat=0.0091;
 if(lat<6-deltaLat||lat>38+deltaLat||lng<67.98||lng>98.02)
  return {id:{in:[]}};
 const deltaLng=deltaLat/Math.cos(lat*Math.PI/180);
 return {
  publicLatitude:{gte:lat-deltaLat,lte:lat+deltaLat},
  publicLongitude:{gte:lng-deltaLng,lte:lng+deltaLng}
 };
}
export async function publicSuppliers(db:PrismaClient,cursor?:string,latitude?:string,longitude?:string){
 if(cursor)uuid(cursor,'cursor');
 const location=storefrontBounds(latitude,longitude);
 const rows=await db.supplier.findMany({
  where:{approval:'APPROVED',suspendedAt:null,listings:{some:LISTING_DISCOVERED},AND:[location,...(cursor?[{id:{gt:cursor}}]:[])]},
  select:{id:true,displayName:true,profileImageId:true,publicLatitude:true,publicLongitude:true},
  orderBy:{id:'asc'},take:21
 });
 const items=rows.slice(0,20).map(row=>({
  id:row.id,displayName:row.displayName,
  profileImageUrl:row.profileImageId?'/api/v2/catalog/images/'+row.profileImageId:null,
  latitude:row.publicLatitude?.toString()??null,
  longitude:row.publicLongitude?.toString()??null
 }));
 return {items,nextCursor:rows.length>20?rows[19].id:null};
}
