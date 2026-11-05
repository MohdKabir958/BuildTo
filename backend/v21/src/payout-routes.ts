import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import type {PayoutEvidenceGateway} from './payout-gateway';
import {registerBeneficiary,approveBeneficiary,supplierBeneficiaries} from './payout-beneficiary-service';
import {reservePayout,supplierPayouts,adminPayoutQueue} from './payout-service';
import {reconcilePayout} from './payout-reconciliation';
import {attestBankDebit,financePayoutReport} from './payout-bank-statement';
import {financeBeneficiaries} from './admin-money-reads';

const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
const key=(req:Request):string=>{
 const v=req.header('Idempotency-Key');
 if(!v)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required.');
 return v;
};
const go=(handler:(req:Request,res:Response)=>Promise<unknown>):RequestHandler=>
 async(req,res,next)=>{
  try{res.json({data:await handler(req,res),requestId:res.locals.requestId});}
  catch(e){next(e);}
 };
export function registerPayouts(app:Express,db:PrismaClient,auth:RequestHandler,
 gateway?:PayoutEvidenceGateway){
 app.get('/api/v2/suppliers/:supplierId/finance/beneficiaries',auth,go((req,res)=>
  supplierBeneficiaries(db,actor(res),req.params.supplierId)));
 app.get('/api/v2/suppliers/:supplierId/finance/payouts',auth,go((req,res)=>
  supplierPayouts(db,actor(res),req.params.supplierId)));
 app.get('/api/v2/admin/finance/suppliers/:supplierId/beneficiaries',auth,go((req,res)=>
  financeBeneficiaries(db,actor(res),req.params.supplierId)));
 app.post('/api/v2/admin/finance/suppliers/:supplierId/beneficiaries',auth,
  async(req,res,next)=>{
   try{
    const r=await registerBeneficiary(db,actor(res),req.params.supplierId,req.body,gateway);
    res.status(r.replayed?200:201).json({data:r.beneficiary,replayed:r.replayed,
     requestId:res.locals.requestId});
   }catch(e){next(e);}
  });
 app.post('/api/v2/admin/finance/beneficiaries/:accountId/approve',auth,go((req,res)=>
  approveBeneficiary(db,actor(res),req.params.accountId,req.body,gateway)));
 app.post('/api/v2/admin/finance/settlements/:settlementId/payout-intent',auth,
  async(req,res,next)=>{
   try{
    const r=await reservePayout(db,actor(res),req.params.settlementId,key(req),req.body);
    res.status(r.replayed?200:201).json({data:r.payout,replayed:r.replayed,
     requestId:res.locals.requestId});
   }catch(e){next(e);}
  });
 app.get('/api/v2/admin/finance/payouts',auth,go((_req,res)=>
  adminPayoutQueue(db,actor(res))));
 app.post('/api/v2/admin/finance/payouts/:payoutId/reconcile',auth,go((req,res)=>
  reconcilePayout(db,actor(res),req.params.payoutId,req.body,gateway)));
 app.post('/api/v2/admin/finance/payouts/:payoutId/bank-attest',auth,go((req,res)=>
  attestBankDebit(db,actor(res),req.params.payoutId,req.body)));
 app.get('/api/v2/admin/finance/payouts-reconciliation',auth,go((_req,res)=>
  financePayoutReport(db,actor(res))));
}
