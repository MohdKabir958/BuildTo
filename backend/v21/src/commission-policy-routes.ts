import type {Express,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {getCommissionPolicy,setCommissionPolicy} from './commission-policy';

const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
export function registerCommissionPolicy(app:Express,db:PrismaClient,auth:RequestHandler){
 const url='/api/v2/admin/finance/commission-policy';
 app.get(url,auth,async(_req,res,next)=>{
  try{res.json({data:await getCommissionPolicy(db,actor(res)),requestId:res.locals.requestId});}
  catch(e){next(e);}
 });
 app.put(url,auth,async(req,res,next)=>{
  try{res.json({data:await setCommissionPolicy(db,actor(res),req.body),requestId:res.locals.requestId});}
  catch(e){next(e);}
 });
}
