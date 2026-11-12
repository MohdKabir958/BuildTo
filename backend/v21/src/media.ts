import {createHash,randomUUID} from 'node:crypto';
import {mkdir,writeFile,readFile,unlink} from 'node:fs/promises';
import {isAbsolute,join} from 'node:path';
import sharp from 'sharp';
import type {Express,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,uuid,integer} from './catalog-validation';
import {requireAdminPermission} from './permissions';
import {serializable} from './transaction';

export interface MediaStore {put(key:string,bytes:Buffer):Promise<void>;get(key:string):Promise<Buffer>;remove(key:string):Promise<void>}
/** Requires a private persistent volume in staging; never expose this directory as static files. */
export class PrivateFileMediaStore implements MediaStore {
 constructor(private root:string){if(!isAbsolute(root))throw new Error('V21_MEDIA_ROOT_MUST_BE_ABSOLUTE');}
 private path(key:string){if(!/^[0-9a-f-]{36}$/.test(key))throw new Error('INVALID_STORAGE_KEY');return join(this.root,key);}
 async put(key:string,bytes:Buffer){await mkdir(this.root,{recursive:true,mode:0o700});await writeFile(this.path(key),bytes,{flag:'wx',mode:0o600});}
 async get(key:string){return readFile(this.path(key));}
 async remove(key:string){await unlink(this.path(key));}
}
const MAX=10*1024*1024;
export async function uploadMedia(db:PrismaClient,store:MediaStore,actor:string,input:unknown){
 const o=record(input,['purpose','mimeType','base64']);
 if(!['EVIDENCE','CATALOG_IMAGE'].includes(String(o.purpose)))throw new ApiError(400,'INVALID_MEDIA_PURPOSE','Choose document or catalog image.');
 if(o.purpose==='CATALOG_IMAGE')await requireAdminPermission(db,actor,'CATALOG_APPROVE');
 if(typeof o.base64!=='string'||o.base64.length>Math.ceil(MAX/3)*4||!o.base64.length||/[^A-Za-z0-9+/=]/.test(o.base64))throw new ApiError(400,'INVALID_MEDIA','Upload a file up to 10 MiB.');
 let bytes=Buffer.from(o.base64,'base64'),mime=String(o.mimeType);
 if(bytes.toString('base64')!==o.base64)throw new ApiError(400,'INVALID_MEDIA','Invalid file encoding.');
 if(bytes.length>MAX)throw new ApiError(413,'PAYLOAD_TOO_LARGE','File exceeds 10 MiB.');
 if(['image/png','image/jpeg'].includes(mime)){
  try{
   const image=sharp(bytes,{limitInputPixels:20_000_000,animated:false});
   const metadata=await image.metadata();
   if(!['png','jpeg'].includes(metadata.format??'')||metadata.pages&&metadata.pages>1)throw new Error();
   bytes=await image.rotate().png().toBuffer();mime='image/png';
  }catch{throw new ApiError(400,'INVALID_IMAGE','Upload a valid single JPEG or PNG image.');}
 }else if(mime==='application/pdf'&&o.purpose==='EVIDENCE'){
  if(!bytes.subarray(0,5).equals(Buffer.from('%PDF-'))||!bytes.subarray(-1024).includes(Buffer.from('%%EOF')))throw new ApiError(400,'INVALID_PDF','Upload a valid PDF document.');
 }else throw new ApiError(415,'MEDIA_TYPE_UNSUPPORTED','Use JPEG/PNG images or a PDF document.');
 if(bytes.length>MAX)throw new ApiError(413,'PAYLOAD_TOO_LARGE','Decoded file exceeds 10 MiB.');
 // The same immutable object survives transaction retries; failed commits remove it.
 const id=randomUUID();await store.put(id,bytes);
 try{return await serializable(db,async tx=>{
  await tx.$queryRawUnsafe('SELECT pg_advisory_xact_lock(hashtextextended($1, 73119)) IS NULL AS locked',actor);
  const recent=await tx.mediaAsset.aggregate({where:{ownerUserId:actor,createdAt:{gte:new Date(Date.now()-86400000)}},_sum:{sizeBytes:true},_count:true});
  if(recent._count>=50||(recent._sum.sizeBytes??0n)+BigInt(bytes.length)>100n*1024n*1024n)throw new ApiError(429,'UPLOAD_QUOTA_EXCEEDED','Daily file upload limit reached.');
  const asset=await tx.mediaAsset.create({data:{id,objectKey:id,ownerUserId:actor,purpose:String(o.purpose),mimeType:mime,sizeBytes:BigInt(bytes.length),sha256:createHash('sha256').update(bytes).digest('hex')},select:{id:true,mimeType:true,sizeBytes:true,sha256:true}});
  return {...asset,sizeBytes:asset.sizeBytes.toString()};
 });}catch(error){await store.remove(id).catch(()=>{});throw error;}
}
export function registerMedia(app:Express,db:PrismaClient,auth:RequestHandler,store?:MediaStore){
 const ready=()=>{if(!store)throw new ApiError(503,'MEDIA_STORAGE_UNAVAILABLE','Document storage is not configured.');return store;};
 app.post('/api/v2/media',auth,async(req,res,next)=>{try{res.status(201).json({data:await uploadMedia(db,ready(),res.locals.principal.id,req.body),requestId:res.locals.requestId});}catch(e){next(e);}});
 app.get('/api/v2/media/:mediaId',auth,async(req,res,next)=>{try{
  const id=uuid(req.params.mediaId,'mediaId'),actor=res.locals.principal.id;
  const asset=await db.mediaAsset.findUnique({where:{id}});
  if(!asset)throw new ApiError(404,'NOT_FOUND','File unavailable.');
  if(asset.ownerUserId!==actor){
   const linked=await db.supplierDocument.findFirst({where:{mediaId:id},select:{supplierId:true}});
   if(!linked)throw new ApiError(404,'NOT_FOUND','File unavailable.');
   await requireAdminPermission(db,actor,'SUPPLIER_APPROVE');
   if(await db.supplierMember.findUnique({where:{supplierId_userId:{supplierId:linked.supplierId,userId:actor}}}))throw new ApiError(403,'INDEPENDENT_SUPPLIER_REVIEW_REQUIRED','Independent reviewer required.');
  }
  const bytes=await ready().get(asset.objectKey);
  if(createHash('sha256').update(bytes).digest('hex')!==asset.sha256)throw new ApiError(503,'MEDIA_INTEGRITY_FAILED','File unavailable.');
  if(req.query.format==='base64'){res.json({data:{base64:bytes.toString('base64'),mimeType:asset.mimeType},requestId:res.locals.requestId});return;}
  res.setHeader('Content-Type',asset.mimeType);res.setHeader('Content-Disposition','attachment; filename="document'+(asset.mimeType==='application/pdf'?'.pdf':'.png')+'"');res.send(bytes);
 }catch(e){next(e);}});
 app.put('/api/v2/admin/catalog/products/:productId/images/:mediaId',auth,async(req,res,next)=>{try{
  const productId=uuid(req.params.productId,'productId'),id=uuid(req.params.mediaId,'mediaId'),actor=res.locals.principal.id;
  const o=record(req.body,['position']),position=integer(o.position,'position',0,11);
  const data=await serializable(db,async tx=>{
   await requireAdminPermission(tx,actor,'CATALOG_APPROVE');
   const asset=await tx.mediaAsset.findFirst({where:{id,ownerUserId:actor,purpose:'CATALOG_IMAGE',mimeType:'image/png',OR:[{productId:null},{productId}]}});
   if(!asset||!await tx.product.findUnique({where:{id:productId}}))throw new ApiError(404,'NOT_FOUND','Image or product unavailable.');
   await tx.mediaAsset.update({where:{id},data:{productId,position}});
   await tx.auditEvent.create({data:{actorUserId:actor,actorRole:'ADMIN_CATALOG',action:'PRODUCT_IMAGE_LINKED',entityType:'Product',entityId:productId,afterState:{mediaId:id,position}}});
   return {id,position,url:'/api/v2/catalog/images/'+id};
  });res.json({data,requestId:res.locals.requestId});
 }catch(e){next(e);}});
 app.delete('/api/v2/admin/catalog/products/:productId/images/:mediaId',auth,async(req,res,next)=>{try{
  const productId=uuid(req.params.productId,'productId'),id=uuid(req.params.mediaId,'mediaId');
  await requireAdminPermission(db,res.locals.principal.id,'CATALOG_APPROVE');
  const saved=await db.mediaAsset.updateMany({where:{id,productId,purpose:'CATALOG_IMAGE'},data:{productId:null}});
  if(!saved.count)throw new ApiError(404,'NOT_FOUND','Image unavailable.');
  res.json({data:{removed:true},requestId:res.locals.requestId});
 }catch(e){next(e);}});
}
export function registerPublicImages(app:Express,db:PrismaClient,store?:MediaStore){
 app.get('/api/v2/catalog/images/:mediaId',async(req,res,next)=>{try{
  const id=uuid(req.params.mediaId,'mediaId');
  const asset=await db.mediaAsset.findFirst({where:{id,purpose:'CATALOG_IMAGE',product:{active:true,category:{active:true}}}});
  if(!asset){next();return;}
  if(!store)throw new ApiError(404,'NOT_FOUND','Image unavailable.');
  const bytes=await store.get(asset.objectKey);
  if(createHash('sha256').update(bytes).digest('hex')!==asset.sha256)throw new ApiError(503,'MEDIA_INTEGRITY_FAILED','Image unavailable.');
  res.type('png').send(bytes);
 }catch(e){next(e);}});
}
