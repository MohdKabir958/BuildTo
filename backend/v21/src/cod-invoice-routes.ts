import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {selectCod,recordCod,reviewCod,listSupplierCod} from './cod-service';
import {issueSupplierInvoice,supplierInvoices,customerInvoices} from './invoice-service';

const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
const idem=(req:Request):string=>{
 const key=req.header('Idempotency-Key');
 if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required.');
 return key;
};
type Op=(req:Request,res:Response)=>Promise<unknown>;
const action=(work:Op,created=false):RequestHandler=>async(req,res,next)=>{
 try{
  const data=await work(req,res);
  res.status(created?201:200).json({data,requestId:res.locals.requestId});
 }catch(error){next(error);}
};
export function registerCodAndInvoices(app:Express,db:PrismaClient,auth:RequestHandler){
 app.post('/api/v2/orders/:orderId/cod',auth,async(req,res,next)=>{
  try{
   const selected=await selectCod(db,actor(res),req.params.orderId,idem(req),req.body);
   res.status(selected.replayed?200:201).json({data:selected,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get('/api/v2/orders/:orderId/invoices',auth,action((req,res)=>
  customerInvoices(db,actor(res),req.params.orderId)));
 const supplier='/api/v2/suppliers/:supplierId/orders/:supplierOrderId';
 app.post(supplier+'/cod',auth,async(req,res,next)=>{
  try{
   const x=await recordCod(db,actor(res),req.params.supplierId,req.params.supplierOrderId,
    idem(req),req.body);
   res.status(x.replayed?200:201).json({data:x.receipt,replayed:x.replayed,
    requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get(supplier+'/cod',auth,action((req,res)=>
  listSupplierCod(db,actor(res),req.params.supplierId,req.params.supplierOrderId)));
 app.post('/api/v2/admin/finance/cod/:receiptId/review',auth,async(req,res,next)=>{
  try{
   const x=await reviewCod(db,actor(res),req.params.receiptId,req.body);
   res.json({data:x.receipt,replayed:x.replayed,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.post(supplier+'/invoices',auth,async(req,res,next)=>{
  try{
   const x=await issueSupplierInvoice(db,actor(res),req.params.supplierId,
    req.params.supplierOrderId,req.body);
   res.status(x.replayed?200:201).json({data:x.invoice,replayed:x.replayed,
    requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get(supplier+'/invoices',auth,action((req,res)=>
  supplierInvoices(db,actor(res),req.params.supplierId,req.params.supplierOrderId)));
}
