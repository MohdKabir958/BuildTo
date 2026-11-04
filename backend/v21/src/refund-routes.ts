import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import type {PaymentGateway} from './payment-gateway';
import {issueReturnCreditNote} from './credit-note-service';
import {requestFullRefund,approveFullRefund,customerRefunds,financeRefundQueue} from './refund-service';
import {reconcileRefund} from './refund-reconciliation';
import {refundCandidates} from './admin-money-reads';
function moneyListQuery(req:Request){
 const limit=req.query.limit,cursor=req.query.cursor;
 if(cursor!==undefined&&typeof cursor!=='string')throw new ApiError(400,'INVALID_CURSOR','Invalid cursor.');
 if(limit!==undefined&&(typeof limit!=='string'||!/^[1-9][0-9]?$/.test(limit)))
  throw new ApiError(400,'INVALID_LIMIT','Invalid list page size.');
 return {cursor:cursor as string|undefined,limit:limit===undefined?undefined:Number(limit)};
}


const user=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
function idem(req:Request){
 const key=req.header('Idempotency-Key');
 if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required.');
 return key;
}
const op=(handler:(req:Request,res:Response)=>Promise<unknown>):RequestHandler=>
 async(req,res,next)=>{
  try{res.json({data:await handler(req,res),requestId:res.locals.requestId});}
  catch(e){next(e);}
 };
export function registerReturnsFinance(app:Express,db:PrismaClient,auth:RequestHandler,
 gateway?:PaymentGateway){
 app.post('/api/v2/suppliers/:supplierId/returns/:returnId/credit-note',auth,
  async(req,res,next)=>{
   try{
    const found=await issueReturnCreditNote(db,user(res),req.params.supplierId,
     req.params.returnId,req.body);
    res.status(found.replayed?200:201).json({data:found.creditNote,
     replayed:found.replayed,requestId:res.locals.requestId});
   }catch(e){next(e);}
  });
 app.get('/api/v2/orders/:orderId/refunds',auth,op((req,res)=>
  customerRefunds(db,user(res),req.params.orderId)));
 app.get('/api/v2/admin/finance/refund-candidates',auth,op((req,res)=>
  refundCandidates(db,user(res),moneyListQuery(req))));
 app.get('/api/v2/admin/finance/refunds',auth,op((_req,res)=>
  financeRefundQueue(db,user(res))));
 app.post('/api/v2/admin/finance/refunds/requests/:returnId',auth,
  async(req,res,next)=>{
   try{
    const found=await requestFullRefund(db,user(res),req.params.returnId,
     idem(req),req.body);
    res.status(found.replayed?200:201).json({data:found.refund,replayed:found.replayed,
     requestId:res.locals.requestId});
   }catch(e){next(e);}
  });
 app.post('/api/v2/admin/finance/refunds/:refundId/approve',auth,op((req,res)=>
  approveFullRefund(db,user(res),req.params.refundId,req.body)));
 app.post('/api/v2/admin/finance/refunds/:refundId/reconcile',auth,op((req,res)=>
  reconcileRefund(db,user(res),req.params.refundId,req.body,gateway)));
}
