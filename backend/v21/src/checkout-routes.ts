import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {readCart,putCartLine,removeCartLine,clearCart} from './cart-service';
import {previewCheckout,getCheckoutQuote,placeCheckoutOrder,
 listCustomerOrders,getCustomerOrder,cancelCustomerOrder} from './order-service';

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
const result=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{
  try{
   res.status(created?201:200).json({data:await fn(req,res),requestId:res.locals.requestId});
  }catch(error){next(error);}
 };
export function registerProtectedCheckout(app:Express,db:PrismaClient,auth:RequestHandler){
 const cart='/api/v2/cart';
 app.get(cart,auth,result((_req,res)=>readCart(db,actor(res))));
 app.put(cart+'/lines/:listingId',auth,result((req,res)=>
  putCartLine(db,actor(res),req.params.listingId,req.body)));
 app.delete(cart+'/lines/:listingId',auth,result((req,res)=>
  removeCartLine(db,actor(res),req.params.listingId,req.body)));
 app.post(cart+'/clear',auth,result((req,res)=>clearCart(db,actor(res),req.body)));
 const checkout='/api/v2/checkouts';
 app.post(checkout,auth,async(req,res,next)=>{
  try{
   const x=await previewCheckout(db,actor(res),idem(req),req.body);
   res.status(x.replayed?200:201).json({data:x.quote,replayed:x.replayed,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get(checkout+'/:quoteId',auth,result((req,res)=>
  getCheckoutQuote(db,actor(res),req.params.quoteId)));
 app.post(checkout+'/:quoteId/place',auth,async(req,res,next)=>{
  try{
   const x=await placeCheckoutOrder(db,actor(res),req.params.quoteId,idem(req),req.body);
   res.status(x.replayed?200:201).json({data:x.order,replayed:x.replayed,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 const orders='/api/v2/orders';
 app.get(orders,auth,result((_req,res)=>listCustomerOrders(db,actor(res))));
 app.get(orders+'/:orderId',auth,result((req,res)=>getCustomerOrder(db,actor(res),req.params.orderId)));
 app.post(orders+'/:orderId/cancel',auth,result((req,res)=>
  cancelCustomerOrder(db,actor(res),req.params.orderId)));
 // PR 09 payment confirmation / PR 10 COD acceptance are intentionally disabled.
}
