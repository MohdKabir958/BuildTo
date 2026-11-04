import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {adminAudit} from './admin-audit-service';

const actor=(res:Response):string=>{
  const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
  if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign-in required.');
  return id;
};
function optional(v:unknown,name:string):string|undefined {
  if(v===undefined)return undefined;
  if(typeof v!=='string')throw new ApiError(400,'INVALID_QUERY','Invalid '+name+'.');
  return v;
}
export function registerAdminAudit(app:Express,db:PrismaClient,auth:RequestHandler) {
  app.get('/api/v2/admin/audit',auth,(async(req:Request,res:Response,next)=>{
    try {
      const data=await adminAudit(db,actor(res),{
        limit:optional(req.query.limit,'limit'),
        cursor:optional(req.query.cursor,'cursor'),
        entityType:optional(req.query.entityType,'entityType'),
        action:optional(req.query.action,'action'),
      });
      res.status(200).json({data,requestId:res.locals.requestId});
    }catch(error){next(error);}
  }) as RequestHandler);
}
