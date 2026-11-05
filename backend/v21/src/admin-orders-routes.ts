import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {adminOrders,adminOrderDetail} from './admin-orders-service';
const actor=(res:Response)=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign-in required.');
 return id;
};
const one=(x:unknown)=>{
 if(x===undefined)return undefined;
 if(typeof x!=='string')throw new ApiError(400,'INVALID_QUERY','Only single filter values are supported.');
 return x;
};
const wrap=(fn:(req:Request,res:Response)=>Promise<unknown>):RequestHandler=>
 async(req,res,next)=>{try{res.json({data:await fn(req,res),requestId:res.locals.requestId});}catch(e){next(e);}};
export function registerAdminOrders(app:Express,db:PrismaClient,auth:RequestHandler){
 const base='/api/v2/admin/orders';
 app.get(base,auth,wrap((req,res)=>{
  const limit=one(req.query.limit);
  if(limit!==undefined&&!/^[1-9][0-9]?$/.test(limit))
   throw new ApiError(400,'INVALID_LIMIT','Limit must be 1–50.');
  return adminOrders(db,actor(res),{
   limit:limit?Number(limit):undefined,cursor:one(req.query.cursor),
   status:one(req.query.status),number:one(req.query.number)
  });
 }));
 app.get(base+'/:orderId',auth,wrap((req,res)=>adminOrderDetail(db,actor(res),req.params.orderId)));
}
