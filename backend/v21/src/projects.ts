import type {Express,RequestHandler} from 'express';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {record,uuid,requiredString} from './catalog-validation';
import {phoneE164} from './delivery-validation';
import {serializable} from './transaction';
const missing=()=>new ApiError(404,'NOT_FOUND','Project or site unavailable.');
const projectSelect={id:true,name:true,reference:true,status:true,createdAt:true,updatedAt:true} as const;
const siteSelect={id:true,projectId:true,addressId:true,name:true,contactName:true,contactPhone:true,accessNotes:true,active:true,createdAt:true} as const;
export function registerProjects(app:Express,db:PrismaClient,auth:RequestHandler){
 const route=(fn:(actor:string,req:any)=>Promise<unknown>,created=false):RequestHandler=>async(req,res,next)=>{
  try{res.status(created?201:200).json({data:await fn(res.locals.principal.id,req),requestId:res.locals.requestId});}catch(e){next(e);}
 };
 const lock=async(tx:Prisma.TransactionClient,actor:string)=>{await tx.$queryRaw(Prisma.sql`SELECT id FROM "User" WHERE id=${actor}::uuid FOR UPDATE`);};
 const p='/api/v2/me/projects',s='/api/v2/me/sites';
 app.get(p,auth,route(async(actor,req)=>{
  const cursor=req.query.cursor?uuid(req.query.cursor,'cursor'):null;
  const rows=await db.constructionProject.findMany({where:{customerId:actor,...(cursor?{id:{gt:cursor}}:{})},select:projectSelect,orderBy:{id:'asc'},take:26});
  return {items:rows.slice(0,25),nextCursor:rows.length>25?rows[24].id:null};
 }));
 app.post(p,auth,route(async(actor,req)=>{
  const o=record(req.body,['name','reference']);
  return db.constructionProject.create({data:{customerId:actor,name:requiredString(o.name,'name',200),reference:o.reference==null?null:requiredString(o.reference,'reference',100)},select:projectSelect});
 },true));
 app.get(p+'/:projectId',auth,route(async(actor,req)=>{
  const row=await db.constructionProject.findFirst({where:{id:uuid(req.params.projectId,'projectId'),customerId:actor},select:{...projectSelect,sites:{select:siteSelect,take:100,orderBy:{createdAt:'desc'}}}});
  if(!row)throw missing();return row;
 }));
 const editProject=async(actor:string,req:any,archive=false)=>{
  const id=uuid(req.params.projectId,'projectId'),o=record(req.body??{},archive?[]:['name','reference','status']);
  if(!archive&&!Object.keys(o).length)throw new ApiError(400,'EMPTY_PATCH','Provide fields to update.');
  if(o.status!==undefined&&!['ACTIVE','ON_HOLD','COMPLETED','ARCHIVED'].includes(String(o.status)))throw new ApiError(400,'INVALID_PROJECT_STATUS','Invalid project status.');
  return serializable(db,async tx=>{
   await lock(tx,actor);
   if(!await tx.constructionProject.findFirst({where:{id,customerId:actor}}))throw missing();
   return tx.constructionProject.update({where:{id},data:{...(o.name!==undefined?{name:requiredString(o.name,'name',200)}:{}),...(o.reference!==undefined?{reference:o.reference===null?null:requiredString(o.reference,'reference',100)}:{}),...(archive?{status:'ARCHIVED' as const}:o.status?{status:o.status as 'ACTIVE'}:{})},select:projectSelect});
  });
 };
 app.patch(p+'/:projectId',auth,route((a,r)=>editProject(a,r)));
 app.delete(p+'/:projectId',auth,route((a,r)=>editProject(a,r,true)));
 app.get(s,auth,route(async(actor,req)=>{
  const cursor=req.query.cursor?uuid(req.query.cursor,'cursor'):null;
  const rows=await db.constructionSite.findMany({where:{customerId:actor,...(cursor?{id:{gt:cursor}}:{})},select:siteSelect,orderBy:{id:'asc'},take:26});
  return {items:rows.slice(0,25),nextCursor:rows.length>25?rows[24].id:null};
 }));
 const editSite=async(actor:string,req:any,create=false,remove=false)=>{
  const o=record(req.body??{},remove?[]:['name','projectId','addressId','contactName','contactPhone','accessNotes','active']);
  const data:Record<string,any>={};
  if(create||o.name!==undefined)data.name=requiredString(o.name,'name',200);
  if(create||o.addressId!==undefined)data.addressId=uuid(o.addressId,'addressId');
  if(o.projectId!==undefined)data.projectId=o.projectId===null?null:uuid(o.projectId,'projectId');
  for(const key of ['contactName','accessNotes'])if(o[key]!==undefined)data[key]=o[key]===null?null:requiredString(o[key],key,key==='accessNotes'?2000:160);
  if(o.contactPhone!==undefined)data.contactPhone=o.contactPhone===null?null:phoneE164(o.contactPhone);
  if(o.active!==undefined){if(typeof o.active!=='boolean')throw new ApiError(400,'INVALID_INPUT','Invalid active flag.');data.active=o.active;}
  if(remove)data.active=false;
  if(!create&&!Object.keys(data).length)throw new ApiError(400,'EMPTY_PATCH','Provide fields to update.');
  return serializable(db,async tx=>{
   await lock(tx,actor);
   const id=create?null:uuid(req.params.siteId,'siteId');
   const old=id?await tx.constructionSite.findFirst({where:{id,customerId:actor}}):null;
   if(id&&!old)throw missing();
   const addressId=data.addressId??old?.addressId,projectId=data.projectId===undefined?old?.projectId:data.projectId;
   if(!remove){
    if(!await tx.address.findFirst({where:{id:addressId,userId:actor,deletedAt:null,city:{active:true}}}))throw missing();
    if(projectId&&!await tx.constructionProject.findFirst({where:{id:projectId,customerId:actor,status:'ACTIVE'}}))throw missing();
   }
   return create?tx.constructionSite.create({data:{...data,customerId:actor} as Prisma.ConstructionSiteUncheckedCreateInput,select:siteSelect}):tx.constructionSite.update({where:{id:id!},data,select:siteSelect});
  });
 };
 app.post(s,auth,route((a,r)=>editSite(a,r,true),true));
 app.patch(s+'/:siteId',auth,route((a,r)=>editSite(a,r)));
 app.delete(s+'/:siteId',auth,route((a,r)=>editSite(a,r,false,true)));
}
