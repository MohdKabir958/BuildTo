import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {createWarehouse,changeWarehouse,listWarehouses,listStock,listMovements,adjustStock} from './inventory-stock';
import {transferStock} from './inventory-transfer';
import {uuid} from './inventory-validation';

const principal=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
const query=(value:unknown,name:string)=>{
 if(value===undefined)return undefined;
 if(typeof value!=='string')throw new ApiError(400,'INVALID_QUERY','Invalid '+name+' filter.');
 return uuid(value,name);
};
const wrap=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{
  try{
   const data=await fn(req,res);
   res.status(created?201:200).json({data,requestId:res.locals.requestId});
  }catch(error){next(error);}
 };
const idempotency=(req:Request)=>{
 const key=req.header('Idempotency-Key');
 if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required for stock changes.');
 return key;
};
export function registerProtectedInventory(app:Express,db:PrismaClient,auth:RequestHandler) {
 const base='/api/v2/suppliers/:supplierId/inventory';
 app.get(base+'/warehouses',auth,wrap((req,res)=>
  listWarehouses(db,principal(res),req.params.supplierId)));
 app.post(base+'/warehouses',auth,wrap((req,res)=>
  createWarehouse(db,principal(res),req.params.supplierId,req.body),true));
 app.patch(base+'/warehouses/:warehouseId',auth,wrap((req,res)=>
  changeWarehouse(db,principal(res),req.params.supplierId,req.params.warehouseId,req.body)));
 app.get(base+'/balances',auth,wrap((req,res)=>
  listStock(db,principal(res),req.params.supplierId,query(req.query.listingId,'listingId'))));
 app.get(base+'/warehouses/:warehouseId/movements',auth,wrap((req,res)=>
  listMovements(db,principal(res),req.params.supplierId,req.params.warehouseId,
   query(req.query.listingId,'listingId'))));
 app.post(base+'/adjustments',auth,async(req,res,next)=>{
  try{
   const value=await adjustStock(db,principal(res),req.params.supplierId,
    idempotency(req),req.body);
   res.status(value.replayed?200:201).json({data:value,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.post(base+'/transfers',auth,async(req,res,next)=>{
  try{
   const value=await transferStock(db,principal(res),req.params.supplierId,
    idempotency(req),req.body);
   res.status(value.replayed?200:201).json({data:value,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 // No public /reservations route: only checkout/order transactions may invoke
 // holdOrderItemStock, releaseOrderItemStock or commitOrderItemStock.
}
