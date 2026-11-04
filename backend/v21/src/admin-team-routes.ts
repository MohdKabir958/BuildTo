import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {listAdminTeam,grantAdmin,changeAdminRole,revokeAdmin} from './admin-team-service';

const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Administrator session required.');
 return id;
};
const route=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{
   try{const data=await fn(req,res);res.status(created?201:200).json({data,requestId:res.locals.requestId});}
   catch(e){next(e);}
 };
function query(req:Request) {
 const cursor=req.query.cursor;
 const limit=req.query.limit;
 if(cursor!==undefined&&typeof cursor!=='string')
   throw new ApiError(400,'INVALID_CURSOR','Invalid team pagination cursor.');
 if(limit!==undefined&&(typeof limit!=='string'||!/^[1-9][0-9]{0,2}$/.test(limit)))
   throw new ApiError(400,'INVALID_LIMIT','Invalid team page size.');
 return {cursor:cursor as string|undefined,limit:limit===undefined?undefined:Number(limit)};
}
export function registerAdminTeam(app:Express,db:PrismaClient,auth:RequestHandler){
 const base='/api/v2/admin/team';
 app.get(base,auth,route((req,res)=>listAdminTeam(db,actor(res),query(req))));
 app.post(base,auth,route((req,res)=>grantAdmin(db,actor(res),req.body),true));
 app.patch(base+'/:userId',auth,route((req,res)=>changeAdminRole(db,actor(res),req.params.userId,req.body)));
 app.post(base+'/:userId/revoke',auth,route((req,res)=>revokeAdmin(db,actor(res),req.params.userId,req.body)));
}
