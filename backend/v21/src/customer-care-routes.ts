import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {createReturn,customerReturns,supplierReturns,customerCancelReturn,
 adminReturns,adminReviewReturn,supplierReceiveReturn} from './returns-service';
import {createSupportCase,customerCases,getSupportCase,
 postSupportMessage,adminCases,adminUpdateCase} from './support-service';
import {createReview,customerReviews,supplierOwnReviews,publicSupplierReviews,
 adminReviewQueue,moderateReview} from './review-service';

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
type Job=(req:Request,res:Response)=>Promise<unknown>;
const go=(job:Job,created=false):RequestHandler=>async(req,res,next)=>{
 try{
  const data=await job(req,res);
  res.status(created?201:200).json({data,requestId:res.locals.requestId});
 }catch(e){next(e);}
};
export function registerReturnsSupportReviews(app:Express,db:PrismaClient,auth:RequestHandler){
 app.post('/api/v2/orders/:orderId/returns',auth,async(req,res,next)=>{
  try{
   const result=await createReturn(db,actor(res),req.params.orderId,idem(req),req.body);
   res.status(result.replayed?200:201).json({data:result.value,replayed:result.replayed,
    requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
 app.get('/api/v2/orders/:orderId/returns',auth,go((req,res)=>
  customerReturns(db,actor(res),req.params.orderId)));
 app.post('/api/v2/returns/:returnId/cancel',auth,go((req,res)=>
  customerCancelReturn(db,actor(res),req.params.returnId)));
 app.get('/api/v2/suppliers/:supplierId/orders/:supplierOrderId/returns',auth,go((req,res)=>
  supplierReturns(db,actor(res),req.params.supplierId,req.params.supplierOrderId)));
 app.post('/api/v2/suppliers/:supplierId/returns/:returnId/receive',auth,go((req,res)=>
  supplierReceiveReturn(db,actor(res),req.params.supplierId,req.params.returnId,req.body)));
 app.get('/api/v2/admin/returns',auth,go((_req,res)=>adminReturns(db,actor(res))));
 app.post('/api/v2/admin/returns/:returnId/review',auth,go((req,res)=>
  adminReviewReturn(db,actor(res),req.params.returnId,req.body)));

 app.post('/api/v2/support/cases',auth,async(req,res,next)=>{
  try{
   const result=await createSupportCase(db,actor(res),idem(req),req.body);
   res.status(result.replayed?200:201).json({data:result.value,replayed:result.replayed,
    requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
 app.get('/api/v2/support/cases',auth,go((_req,res)=>customerCases(db,actor(res))));
 app.get('/api/v2/support/cases/:caseId',auth,go((req,res)=>
  getSupportCase(db,actor(res),req.params.caseId)));
 app.post('/api/v2/support/cases/:caseId/messages',auth,go((req,res)=>
  postSupportMessage(db,actor(res),req.params.caseId,req.body)));
 app.get('/api/v2/admin/support/cases',auth,go((_req,res)=>adminCases(db,actor(res))));
 app.get('/api/v2/admin/support/cases/:caseId',auth,go((req,res)=>
  getSupportCase(db,actor(res),req.params.caseId,true)));
 app.post('/api/v2/admin/support/cases/:caseId/messages',auth,go((req,res)=>
  postSupportMessage(db,actor(res),req.params.caseId,req.body,true)));
 app.patch('/api/v2/admin/support/cases/:caseId',auth,go((req,res)=>
  adminUpdateCase(db,actor(res),req.params.caseId,req.body)));

 app.post('/api/v2/orders/:orderId/reviews',auth,go((req,res)=>
  createReview(db,actor(res),req.params.orderId,req.body),true));
 app.get('/api/v2/orders/:orderId/reviews',auth,go((req,res)=>
  customerReviews(db,actor(res),req.params.orderId)));
 app.get('/api/v2/suppliers/:supplierId/reviews/manage',auth,go((req,res)=>
  supplierOwnReviews(db,actor(res),req.params.supplierId)));
 app.get('/api/v2/admin/reviews',auth,go((_req,res)=>adminReviewQueue(db,actor(res))));
 app.post('/api/v2/admin/reviews/:reviewId/moderate',auth,go((req,res)=>
  moderateReview(db,actor(res),req.params.reviewId,req.body)));
}

/** Published reviews are genuinely public; moderation and write endpoints are not. */
export function registerPublicReviews(app:Express,db:PrismaClient){
 app.get('/api/v2/suppliers/:supplierId/reviews',go(req=>
  publicSupplierReviews(db,req.params.supplierId)));
}
