import type {Express,Request,Response,RequestHandler} from 'express';
import type {PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {supplierOrders,acceptSupplierOrder,rejectUnpaidSupplierOrder,
 planShipment,progressShipment,cancelShipment,issueCustomerHandoverOtp,confirmShipmentHandover,
 approveDeliveryException,supplierShipments,customerShipments} from './fulfillment-service';

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
const handle=(fn:(req:Request,res:Response)=>Promise<unknown>,created=false):RequestHandler=>
 async(req,res,next)=>{try{
  const data=await fn(req,res);
  res.status(created?201:200).json({data,requestId:res.locals.requestId});
 }catch(error){next(error);}};
export function registerFulfillment(app:Express,db:PrismaClient,auth:RequestHandler,otpSecret?:string){
 const base='/api/v2/suppliers/:supplierId';
 app.get(base+'/orders',auth,handle((req,res)=>supplierOrders(db,actor(res),req.params.supplierId)));
 app.post(base+'/orders/:supplierOrderId/accept',auth,handle((req,res)=>
  acceptSupplierOrder(db,actor(res),req.params.supplierId,req.params.supplierOrderId)));
 app.post(base+'/orders/:supplierOrderId/reject',auth,handle((req,res)=>
  rejectUnpaidSupplierOrder(db,actor(res),req.params.supplierId,req.params.supplierOrderId,req.body)));
 app.post(base+'/orders/:supplierOrderId/shipments',auth,async(req,res,next)=>{
  try{
   const result=await planShipment(db,actor(res),req.params.supplierId,
    req.params.supplierOrderId,idem(req),req.body);
   res.status(result.replayed?200:201).json({
    data:result.shipment,replayed:result.replayed,requestId:res.locals.requestId});
  }catch(error){next(error);}
 });
 app.get(base+'/orders/:supplierOrderId/shipments',auth,handle((req,res)=>
  supplierShipments(db,actor(res),req.params.supplierId,req.params.supplierOrderId)));
 for(const stage of ['pack','dispatch','out-for-delivery'] as const)
  app.post(base+'/shipments/:shipmentId/'+stage,auth,handle((req,res)=>
   progressShipment(db,actor(res),req.params.supplierId,req.params.shipmentId,stage)));
 app.post(base+'/shipments/:shipmentId/cancel',auth,handle((req,res)=>
  cancelShipment(db,actor(res),req.params.supplierId,req.params.shipmentId,req.body)));
 app.post(base+'/shipments/:shipmentId/handover',auth,handle((req,res)=>
  confirmShipmentHandover(db,actor(res),req.params.supplierId,req.params.shipmentId,
   req.body,otpSecret)));
 app.get('/api/v2/orders/:orderId/shipments',auth,handle((req,res)=>
  customerShipments(db,actor(res),req.params.orderId)));
 app.post('/api/v2/orders/:orderId/shipments/:shipmentId/otp',auth,handle((req,res)=>
  issueCustomerHandoverOtp(db,actor(res),req.params.orderId,req.params.shipmentId,
   req.body,otpSecret)));
 app.post('/api/v2/admin/shipments/:shipmentId/exception-approve',auth,handle((req,res)=>
  approveDeliveryException(db,actor(res),req.params.shipmentId,req.body)));
}
