import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {
 submitSupplierApplication,ownSupplierApplications,attachSupplierDocument,
 adminSupplierQueue,adminSupplierDetail,reviewSupplierDocument,reviewSupplierApplication
} from './admin-supplier-service';

const actor=(res:Response)=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
const safe=(handler:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{try{const data=await handler(req,res);res.status(created?201:200).json({data,requestId:res.locals.requestId});}catch(e){next(e);}};
const qs=(value:unknown):string|undefined=>{
 if(value===undefined)return undefined;
 if(typeof value!=='string')throw new ApiError(400,'INVALID_QUERY','Expected single query parameter.');
 return value;
};
const query=(req:Request)=>{
 const limit=qs(req.query.limit);
 if(limit!==undefined&&!/^[1-9][0-9]{0,2}$/.test(limit))throw new ApiError(400,'INVALID_LIMIT','Invalid limit.');
 return {status:qs(req.query.status),cursor:qs(req.query.cursor),limit:limit===undefined?undefined:Number(limit)};
};
export function registerAdminSupplierApplications(app:Express,db:PrismaClient,auth:RequestHandler){
 app.post('/api/v2/supplier-applications',auth,safe((req,res)=>submitSupplierApplication(db,actor(res),req.body),true));
 app.get('/api/v2/me/supplier-applications',auth,safe((_req,res)=>ownSupplierApplications(db,actor(res))));
 app.post('/api/v2/supplier-applications/:supplierId/documents',auth,safe((req,res)=>
  attachSupplierDocument(db,actor(res),req.params.supplierId,req.body),true));
 const admin='/api/v2/admin/suppliers';
 app.get(admin,auth,safe((req,res)=>adminSupplierQueue(db,actor(res),query(req))));
 app.get(admin+'/:supplierId',auth,safe((req,res)=>adminSupplierDetail(db,actor(res),req.params.supplierId)));
 app.post(admin+'/:supplierId/documents/:documentId/review',auth,safe((req,res)=>
  reviewSupplierDocument(db,actor(res),req.params.supplierId,req.params.documentId,req.body)));
 app.post(admin+'/:supplierId/review',auth,safe((req,res)=>
  reviewSupplierApplication(db,actor(res),req.params.supplierId,req.body)));
}
