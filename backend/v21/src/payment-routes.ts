import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {startPayment,customerPayments,cancelPaymentSession} from './payment-service';
import type {PaymentGateway} from './payment-gateway';
const actor=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign in required.');
 return id;
};
export function registerProtectedPayments(app:Express,db:PrismaClient,
 auth:RequestHandler,gateway:PaymentGateway){
 app.post('/api/v2/orders/:orderId/payments',auth,async(req,res,next)=>{
  try {
   const key=req.header('Idempotency-Key');
   if(!key)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key required.');
   const result=await startPayment(db,actor(res),req.params.orderId,key,req.body,gateway);
   res.status(result.initializing?202:result.replayed?200:201).json({
    data:result.payment,replayed:result.replayed,
    initializing:result.initializing,requestId:res.locals.requestId
   });
  }catch(error){next(error);}
 });
 app.post('/api/v2/orders/:orderId/payments/:paymentId/cancel',auth,async(req,res,next)=>{
  try{
   if(!req.body||typeof req.body!=='object'||Array.isArray(req.body)||Object.keys(req.body).length)
    throw new ApiError(400,'INVALID_PAYMENT_REQUEST','Cancellation requires empty JSON.');
   const result=await cancelPaymentSession(db,actor(res),req.params.orderId,
    req.params.paymentId,gateway);
   res.status(200).json({data:result,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get('/api/v2/orders/:orderId/payments',auth,async(req,res,next)=>{
  try{
   const payments=await customerPayments(db,actor(res),req.params.orderId,gateway.publicKey);
   res.json({data:payments,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
}
