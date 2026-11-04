import type {Express,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {adminOverview} from './admin-overview-service';
export function registerAdminOverview(app:Express,db:PrismaClient,auth:RequestHandler){
 app.get('/api/v2/admin/overview',auth,async(_req,res:Response,next)=>{
  try{
   const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
   if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
   const data=await adminOverview(db,id);
   res.status(200).json({data,requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
}
