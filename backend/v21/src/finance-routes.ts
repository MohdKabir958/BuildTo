import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {createSettlementDraft,approveSettlement,cancelHeldSettlement,
 supplierStatement,adminSupplierFinance,recognizeCodCommission,journalDetail} from './finance-service';

function actor(res:Response){
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
}
function idem(req:Request){
 const key=req.header('Idempotency-Key');
 if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required.');
 return key;
}
type Job=(req:Request,res:Response)=>Promise<unknown>;
const go=(job:Job):RequestHandler=>async(req,res,next)=>{
 try{
  res.status(200).json({data:await job(req,res),requestId:res.locals.requestId});
 }catch(err){next(err);}
};
export function registerFinance(app:Express,db:PrismaClient,auth:RequestHandler){
 app.get('/api/v2/suppliers/:supplierId/finance/statement',auth,go((req,res)=>
  supplierStatement(db,actor(res),req.params.supplierId)));
 app.get('/api/v2/admin/finance/suppliers/:supplierId',auth,go((req,res)=>
  adminSupplierFinance(db,actor(res),req.params.supplierId)));
 app.post('/api/v2/admin/finance/settlements/drafts',auth,async(req,res,next)=>{
  try {
   const created=await createSettlementDraft(db,actor(res),idem(req),req.body);
   res.status(created.replayed?200:201).json({data:created.settlement,
    replayed:created.replayed,requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
 app.post('/api/v2/admin/finance/settlements/:settlementId/approve',auth,go((req,res)=>
  approveSettlement(db,actor(res),req.params.settlementId,req.body)));
 app.post('/api/v2/admin/finance/settlements/:settlementId/cancel',auth,go((req,res)=>
  cancelHeldSettlement(db,actor(res),req.params.settlementId,req.body)));
 app.post('/api/v2/admin/finance/cod-commissions/:supplierOrderId/recognize',auth,go((req,res)=>
  recognizeCodCommission(db,actor(res),req.params.supplierOrderId)));
 app.get('/api/v2/admin/finance/journals/:journalId',auth,go((req,res)=>
  journalDetail(db,actor(res),req.params.journalId)));
}
