import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {startPayment,customerPayments} from './payment-service';
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
 app.get('/api/v2/orders/:orderId/payments',auth,async(req,res,next)=>{
  try{
   const payments=await customerPayments(db,actor(res),req.params.orderId,gateway.publicKey);
   res.json({data:payments,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
}
