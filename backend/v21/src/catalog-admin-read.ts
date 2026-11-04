import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {requireAdminPermission,isUuid} from './permissions';

type Query={cursor?:string;limit?:number};
const validate=(query:Query)=>{
 const limit=query.limit??25;
 if(!Number.isSafeInteger(limit)||limit<1||limit>50)
  throw new ApiError(400,'INVALID_LIMIT','Limit must be between 1 and 50.');
 if(query.cursor!==undefined&&!isUuid(query.cursor))
  throw new ApiError(400,'INVALID_CURSOR','Invalid catalog cursor.');
 return {limit,cursor:query.cursor};
};
const page=<T extends {id:string}>(rows:T[],limit:number)=>({
 items:rows.slice(0,limit),nextCursor:rows.length>limit?rows[limit-1].id:null
});
export async function adminCategories(db:PrismaClient,actor:string,q:Query){
 await requireAdminPermission(db,actor,'CATALOG_APPROVE');
 const {limit,cursor}=validate(q);
 const rows=await db.category.findMany({where:cursor?{id:{gt:cursor}}:{},
  select:{id:true,parentId:true,slug:true,name:true,displayOrder:true,active:true,createdAt:true},
  orderBy:{id:'asc'},take:limit+1});
 return page(rows.map(x=>({...x,createdAt:x.createdAt.toISOString()})),limit);
}
export async function adminBrands(db:PrismaClient,actor:string,q:Query){
 await requireAdminPermission(db,actor,'CATALOG_APPROVE');
 const {limit,cursor}=validate(q);
 const rows=await db.brand.findMany({where:cursor?{id:{gt:cursor}}:{},
  select:{id:true,slug:true,name:true},orderBy:{id:'asc'},take:limit+1});
 return page(rows,limit);
}
export async function adminProducts(db:PrismaClient,actor:string,q:Query){
 await requireAdminPermission(db,actor,'CATALOG_APPROVE');
 const {limit,cursor}=validate(q);
 const rows=await db.product.findMany({where:cursor?{id:{gt:cursor}}:{},
  select:{id:true,code:true,name:true,active:true,hsnCode:true,categoryId:true,brandId:true,createdAt:true,
   category:{select:{name:true,active:true}},brand:{select:{name:true}}},
  orderBy:{id:'asc'},take:limit+1});
 return page(rows.map(x=>({
  id:x.id,code:x.code,name:x.name,active:x.active,hsnCode:x.hsnCode,categoryId:x.categoryId,
  categoryName:x.category.name,categoryActive:x.category.active,brandId:x.brandId,brandName:x.brand?.name??null,
  createdAt:x.createdAt.toISOString()
 })),limit);
}
