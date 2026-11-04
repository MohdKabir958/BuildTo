import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {
 createCustomerRfq,listCustomerRfqs,customerRfq,openCustomerRfq,
 inviteSupplier,cancelCustomerRfq,invitedSupplierRfqs,submitSupplierQuote,
 mySupplierQuotes,customerQuotes,acceptCustomerQuote
} from './rfq-service';
import {createPromotion,listPromotions,setPromotionActive} from './promotion-service';

const user=(res:Response):string=>{
 const id=(res.locals.principal as {id?:unknown}|undefined)?.id;
 if(typeof id!=='string')throw new ApiError(401,'INVALID_SESSION','Sign-in required.');
 return id;
};
const key=(req:Request):string=>{
 const value=req.header('Idempotency-Key');
 if(!value)throw new ApiError(428,'IDEMPOTENCY_REQUIRED','Idempotency-Key header required.');
 return value;
};
const wrap=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{
  try{
   const data=await fn(req,res);
   res.status(created?201:200).json({data,requestId:res.locals.requestId});
  }catch(e){next(e);}
 };
export function registerRfqAndPromotions(app:Express,db:PrismaClient,auth:RequestHandler) {
 const rfq='/api/v2/rfqs';
 app.get(rfq,auth,wrap((_req,res)=>listCustomerRfqs(db,user(res))));
 app.post(rfq,auth,async(req,res,next)=>{
  try{
   const created=await createCustomerRfq(db,user(res),key(req),req.body);
   res.status(created.replayed?200:201).json({data:created.rfq,
    replayed:created.replayed,requestId:res.locals.requestId});
  }catch(e){next(e);}
 });
 app.get(rfq+'/:rfqId',auth,wrap((req,res)=>customerRfq(db,user(res),req.params.rfqId)));
 app.post(rfq+'/:rfqId/open',auth,wrap((req,res)=>
  openCustomerRfq(db,user(res),req.params.rfqId)));
 app.post(rfq+'/:rfqId/invitations/:supplierId',auth,wrap((req,res)=>
  inviteSupplier(db,user(res),req.params.rfqId,req.params.supplierId)));
 app.post(rfq+'/:rfqId/cancel',auth,wrap((req,res)=>
  cancelCustomerRfq(db,user(res),req.params.rfqId)));
 app.get(rfq+'/:rfqId/quotes',auth,wrap((req,res)=>
  customerQuotes(db,user(res),req.params.rfqId)));
 app.post(rfq+'/:rfqId/quotes/:quoteId/award',auth,wrap((req,res)=>
  acceptCustomerQuote(db,user(res),req.params.rfqId,req.params.quoteId)));
 const supplier='/api/v2/suppliers/:supplierId/rfqs';
 app.get(supplier,auth,wrap((req,res)=>
  invitedSupplierRfqs(db,user(res),req.params.supplierId)));
 app.post(supplier+'/:rfqId/quotes',auth,async(req,res,next)=>{
  try{
   const result=await submitSupplierQuote(db,user(res),req.params.supplierId,
    req.params.rfqId,req.body,key(req));
   res.status(result.replayed?200:201).json({
    data:result.quote,replayed:result.replayed,requestId:res.locals.requestId
   });
  }catch(e){next(e);}
 });
 app.get(supplier+'/:rfqId/quotes',auth,wrap((req,res)=>
  mySupplierQuotes(db,user(res),req.params.supplierId,req.params.rfqId)));
 const promotions='/api/v2/admin/promotions';
 app.get(promotions,auth,wrap((_req,res)=>listPromotions(db,user(res))));
 app.post(promotions,auth,wrap((req,res)=>
  createPromotion(db,user(res),req.body),true));
 app.patch(promotions+'/:promotionId',auth,wrap((req,res)=>
  setPromotionActive(db,user(res),req.params.promotionId,req.body)));
 // Promotion calculation/redemption are DB transaction-only functions called
 // by checkout PR 08. Clients cannot provide arbitrary subtotal values.
}
