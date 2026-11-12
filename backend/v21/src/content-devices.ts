import {createCipheriv,createHash,randomBytes} from 'node:crypto';
import type {Express,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,requiredString,integer,boolean,uuid} from './catalog-validation';
import {requireAdminPermission} from './permissions';
import {serializable} from './transaction';
const slug=(input:unknown)=>{if(typeof input!=='string'||! /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(input)||input.length>120)throw new ApiError(400,'INVALID_SLUG','Invalid page slug.');return input;};
export function registerPublicContent(app:Express,db:PrismaClient){
 app.get('/api/v2/content/:slug',async(req,res,next)=>{try{
  const page=await db.contentPage.findFirst({where:{slug:slug(req.params.slug),published:true},select:{slug:true,title:true,body:true,version:true,updatedAt:true}});
  if(!page)throw new ApiError(404,'NOT_FOUND','Page unavailable.');
  res.json({data:{...page,format:'plain-text'},requestId:res.locals.requestId});
 }catch(e){next(e);}});
}
export function registerContentDevices(app:Express,db:PrismaClient,auth:RequestHandler,encryptionKey?:string){
 let key:Buffer|undefined;
 if(encryptionKey){key=Buffer.from(encryptionKey,'base64');if(key.length!==32||key.toString('base64')!==encryptionKey)throw new Error('V21_DEVICE_ENCRYPTION_KEY_INVALID');}
 app.put('/api/v2/admin/content/:slug',auth,async(req,res,next)=>{try{
  const id=slug(req.params.slug),actor=res.locals.principal.id,o=record(req.body,['title','body','published','expectedVersion','reason']);
  const title=requiredString(o.title,'title',200),body=(typeof o.body==='string'&&o.body.trim().length>0&&o.body.length<=30000&&!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(o.body)?o.body:(()=>{throw new ApiError(400,'INVALID_CONTENT','Content body must be plain text up to 30000 characters.');})()),published=boolean(o.published,'published'),version=integer(o.expectedVersion,'expectedVersion',0,2147483646),reason=requiredString(o.reason,'reason',400);
  if(reason.length<8)throw new ApiError(400,'AUDIT_REASON_REQUIRED','Explain the content update.');
  const data=await serializable(db,async tx=>{
   await requireAdminPermission(tx,actor,'SUPPORT_MANAGE');
   const old=await tx.contentPage.findUnique({where:{slug:id}});
   if((old?.version??0)!==version)throw new ApiError(409,'CONTENT_VERSION_CONFLICT','Refresh the content before updating.');
   const saved=await tx.contentPage.upsert({where:{slug:id},create:{slug:id,title,body,published},update:{title,body,published,version:{increment:1}},select:{slug:true,title:true,body:true,version:true,published:true}});
   await tx.auditEvent.create({data:{actorUserId:actor,actorRole:'ADMIN_SUPPORT',entityType:'ContentPage',entityId:id,action:'CONTENT_UPDATED',afterState:{version:saved.version,published,reason}}});return saved;
  });res.json({data,requestId:res.locals.requestId});
 }catch(e){next(e);}});
 app.get('/api/v2/me/devices',auth,async(_req,res,next)=>{try{
  const data=await db.deviceRegistration.findMany({where:{userId:res.locals.principal.id,disabledAt:null},select:{id:true,app:true,platform:true,lastSeenAt:true},take:20,orderBy:{lastSeenAt:'desc'}});
  res.json({data,requestId:res.locals.requestId});
 }catch(e){next(e);}});
 app.post('/api/v2/me/devices',auth,async(req,res,next)=>{try{
  if(!key)throw new ApiError(503,'DEVICE_REGISTRATION_UNAVAILABLE','Device registration is not configured.');
  const actor=res.locals.principal.id,o=record(req.body,['token','app','platform']);
  const token=requiredString(o.token,'token',4096);
  if(token.length<40||!/^[A-Za-z0-9_:\-]+$/.test(token)||!['customer','supplier'].includes(String(o.app))||!['android','ios','web'].includes(String(o.platform)))throw new ApiError(400,'INVALID_DEVICE','Invalid device registration.');
  const hash=createHash('sha256').update(token).digest('hex'),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
  const ciphertext=Buffer.concat([cipher.update(token,'utf8'),cipher.final()]);
  const encrypted=['v1',iv.toString('base64'),cipher.getAuthTag().toString('base64'),ciphertext.toString('base64')].join('.');
  const data=await serializable(db,async tx=>{
   await tx.$queryRawUnsafe('SELECT pg_advisory_xact_lock(hashtextextended($1, 73120)) IS NULL AS locked',actor);
   const existing=await tx.deviceRegistration.findUnique({where:{fcmTokenHash:hash}});
   if(existing&&existing.userId!==actor&&!existing.disabledAt)throw new ApiError(409,'DEVICE_ALREADY_REGISTERED','Sign out of the previous account on this device first.');
   if((!existing||existing.disabledAt||existing.userId!==actor)&&await tx.deviceRegistration.count({where:{userId:actor,disabledAt:null}})>=20)throw new ApiError(422,'DEVICE_LIMIT','Remove an unused device first.');
   return tx.deviceRegistration.upsert({where:{fcmTokenHash:hash},create:{userId:actor,fcmTokenHash:hash,fcmTokenEnc:encrypted,app:String(o.app),platform:String(o.platform)},update:{userId:actor,fcmTokenEnc:encrypted,app:String(o.app),platform:String(o.platform),lastSeenAt:new Date(),disabledAt:null},select:{id:true,app:true,platform:true,lastSeenAt:true}});
  });res.status(201).json({data:{...data,pushDeliveryEnabled:false},requestId:res.locals.requestId});
 }catch(e){next(e);}});
 app.delete('/api/v2/me/devices/:deviceId',auth,async(req,res,next)=>{try{
  const id=uuid(req.params.deviceId,'deviceId'),actor=res.locals.principal.id;
  const saved=await db.deviceRegistration.updateMany({where:{id,userId:actor},data:{disabledAt:new Date()}});
  if(!saved.count)throw new ApiError(404,'NOT_FOUND','Device unavailable.');
  res.json({data:{disabled:true},requestId:res.locals.requestId});
 }catch(e){next(e);}});
}
