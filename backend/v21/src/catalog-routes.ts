import express, {type Express,type Request,type Response,type NextFunction,type RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {publicCategories,publicBrands,publicProducts,publicUnits,publicListings} from './catalog-read';
import {createCategory,updateCategory,createBrand,createProduct,updateProduct,addProductConversion} from './catalog-admin';
import {adminCategories,adminBrands,adminProducts} from './catalog-admin-read';
import {createListing,ownListings,updateListing,submitListing,replacePriceTiers,pendingListings,reviewListing} from './catalog-listings';
import {productPhotoContentType,readProductPhoto,storeProductPhoto} from './catalog-photos';

const queryString=(x:unknown,name:string):string|undefined=>{
 if(x===undefined)return undefined;
 if(typeof x!=='string')throw new ApiError(400,'INVALID_QUERY','Invalid '+name+' query.');
 return x;
};
function owned(res:Response) {
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Authentication required.');
 return id;
}
const handlers=(fn:(req:Request,res:Response)=>Promise<unknown>):RequestHandler=>
 async (req,res,next)=>{
  try{const data=await fn(req,res);if(!res.headersSent)res.status(200).json({data,requestId:res.locals.requestId});}
  catch(error){next(error);}
 };
const created=(fn:(req:Request,res:Response)=>Promise<unknown>):RequestHandler=>
 async(req,res,next)=>{
  try{const data=await fn(req,res);res.status(201).json({data,requestId:res.locals.requestId});}
  catch(error){next(error);}
 };
export function registerPublicCatalog(app:Express,db:PrismaClient) {
 app.get('/api/v2/catalog/categories',handlers(()=>publicCategories(db)));
 app.get('/api/v2/catalog/brands',handlers(()=>publicBrands(db)));
 app.get('/api/v2/catalog/units',handlers(()=>publicUnits(db)));
 app.get('/api/v2/catalog/products',handlers(req=>publicProducts(db,{
   categoryId:queryString(req.query.categoryId,'categoryId'),cursor:queryString(req.query.cursor,'cursor'),
   search:queryString(req.query.search,'search'),
 })));
 app.get('/api/v2/catalog/images/:imageId',async(req,res,next)=>{
  try{
   const photo=await readProductPhoto(db,req.params.imageId);
   res.setHeader('Content-Type',photo.mimeType);
   res.setHeader('Cache-Control','public, max-age=86400');
   res.setHeader('X-Content-Type-Options','nosniff');
   res.status(200).send(Buffer.from(photo.bytes));
  }catch(error){next(error);}
 });
 app.get('/api/v2/catalog/listings',handlers(req=>{
   const productId=queryString(req.query.productId,'productId');
   if(!productId)throw new ApiError(400,'PRODUCT_ID_REQUIRED','productId filter is required.');
   return publicListings(db,productId);
 }));
}
export function registerProtectedCatalog(app:Express,db:PrismaClient,auth:RequestHandler) {
 const a='/api/v2/admin/catalog';
 const listQuery=(req:Request)=>{
  const cursor=queryString(req.query.cursor,'cursor');
  const raw=queryString(req.query.limit,'limit');
  if(raw!==undefined&&!/^[1-9][0-9]?$/.test(raw))throw new ApiError(400,'INVALID_LIMIT','Limit must be 1–50.');
  return {cursor,limit:raw===undefined?undefined:Number(raw)};
 };
 app.get(a+'/categories',auth,handlers((req,res)=>adminCategories(db,owned(res),listQuery(req))));
 app.get(a+'/brands',auth,handlers((req,res)=>adminBrands(db,owned(res),listQuery(req))));
 app.get(a+'/products',auth,handlers((req,res)=>adminProducts(db,owned(res),listQuery(req))));
 app.post(a+'/categories',auth,created((req,res)=>createCategory(db,owned(res),req.body)));
 app.patch(a+'/categories/:categoryId',auth,handlers((req,res)=>
   updateCategory(db,owned(res),req.params.categoryId,req.body)));
 app.post(a+'/brands',auth,created((req,res)=>createBrand(db,owned(res),req.body)));
 app.post(a+'/products',auth,created((req,res)=>createProduct(db,owned(res),req.body)));
 app.patch(a+'/products/:productId',auth,handlers((req,res)=>
   updateProduct(db,owned(res),req.params.productId,req.body)));
 app.post(a+'/products/:productId/conversions',auth,created((req,res)=>
   addProductConversion(db,owned(res),req.params.productId,req.body)));
 app.get(a+'/listings/pending',auth,handlers((_req,res)=>pendingListings(db,owned(res))));
 app.post(a+'/listings/:listingId/review',auth,handlers((req,res)=>
   reviewListing(db,owned(res),req.params.listingId,req.body)));
 app.post('/api/v2/suppliers/:supplierId/product-photos',auth,
  express.raw({limit:'8mb',type:req=>productPhotoContentType(String(req.headers['content-type']||''))!==null}),
  async(req,res,next)=>{
   try{
    if(!Buffer.isBuffer(req.body)||req.body.length===0)
     throw new ApiError(415,'UNSUPPORTED_IMAGE','Use a JPEG, PNG, WebP, GIF, BMP, HEIC, or AVIF photo.');
    const saved=await storeProductPhoto(db,owned(res),req.params.supplierId,req.body,String(req.header('content-type')||''));
    res.status(201).json({data:saved,requestId:res.locals.requestId});
   }catch(error){next(error);}
  });
 const s='/api/v2/suppliers/:supplierId/listings';
 app.get(s,auth,handlers((req,res)=>ownListings(db,owned(res),req.params.supplierId)));
 app.post(s,auth,async(req,res,next)=>{
   try{
     const key=req.header('Idempotency-Key');
     if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key header required.');
     const saved=await createListing(db,owned(res),req.params.supplierId,key,req.body);
     res.status(saved.replayed?200:201).json({data:saved.listing,replayed:saved.replayed,requestId:res.locals.requestId});
   }catch(error){next(error);}
 });
 app.patch(s+'/:listingId',auth,handlers((req,res)=>
   updateListing(db,owned(res),req.params.supplierId,req.params.listingId,req.body)));
 app.post(s+'/:listingId/submit',auth,handlers((req,res)=>
   submitListing(db,owned(res),req.params.supplierId,req.params.listingId,req.body)));
 app.put(s+'/:listingId/price-tiers',auth,handlers((req,res)=>
   replacePriceTiers(db,owned(res),req.params.supplierId,req.params.listingId,req.body)));
}
