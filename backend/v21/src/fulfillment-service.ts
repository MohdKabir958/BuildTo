
import {createHmac,randomInt,randomUUID,timingSafeEqual} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {publishOutbox} from './outbox';
import {releaseOrderItemStock} from './inventory-reservations';
import {verifiedFulfillmentPayment} from './payment-funding';
import {isUuid,requireAdminPermission,requireSupplierPermission} from './permissions';

type Tx=Prisma.TransactionClient;
const zero=()=>new Prisma.Decimal(0);
const active=['PLANNED','PACKED','DISPATCHED','OUT_FOR_DELIVERY','PARTIALLY_DELIVERED','DELIVERED'] as const;
const shipSelect={
 id:true,shipmentNumber:true,supplierOrderId:true,supplierId:true,warehouseId:true,status:true,
 carrierName:true,carrierPhoneE164:true,vehicleLabel:true,trackingReference:true,
 scheduledFrom:true,scheduledTo:true,dispatchedAt:true,deliveredAt:true,createdAt:true,
 handoverMethod:true,otpVerifiedAt:true,exceptionApprovedAt:true,
 items:{select:{id:true,supplierOrderItemId:true,quantity:true,deliveredQty:true,rejectedQty:true},
  orderBy:{supplierOrderItemId:'asc' as const}},
 events:{select:{fromStatus:true,toStatus:true,createdAt:true},orderBy:{createdAt:'asc' as const},take:100}
} as const;
function dto(s:any){
 return {id:s.id,shipmentNumber:s.shipmentNumber,supplierOrderId:s.supplierOrderId,
  supplierId:s.supplierId,warehouseId:s.warehouseId,status:s.status,
  carrierName:s.carrierName,carrierPhoneE164:s.carrierPhoneE164,
  vehicleLabel:s.vehicleLabel,trackingReference:s.trackingReference,
  scheduledFrom:s.scheduledFrom?.toISOString()??null,scheduledTo:s.scheduledTo?.toISOString()??null,
  dispatchedAt:s.dispatchedAt?.toISOString()??null,deliveredAt:s.deliveredAt?.toISOString()??null,
  createdAt:s.createdAt.toISOString(),handoverMethod:s.handoverMethod,
  handoverVerified:Boolean(s.otpVerifiedAt||s.exceptionApprovedAt),
  items:s.items.map((x:any)=>({id:x.id,orderItemId:x.supplierOrderItemId,
   quantity:x.quantity.toString(),deliveredQty:x.deliveredQty.toString(),
   rejectedQty:x.rejectedQty.toString()})),
  events:s.events.map((x:any)=>({fromStatus:x.fromStatus,toStatus:x.toStatus,
   at:x.createdAt.toISOString()}))};
}
function record(value:unknown,keys:string[]){
 if(!value||typeof value!=='object'||Array.isArray(value)||
   Object.keys(value).some(k=>!keys.includes(k)))
  throw new ApiError(400,'INVALID_FULFILLMENT_REQUEST','Unexpected fulfillment request fields.');
 return value as Record<string,unknown>;
}
function requiredText(v:unknown,name:string,min:number,max:number){
 if(typeof v!=='string'||v.trim().length<min||v.trim().length>max||
    /[\x00-\x1f\x7f]/.test(v))
  throw new ApiError(400,'INVALID_'+name.toUpperCase(),'Invalid '+name+'.');
 return v.trim();
}
function optText(v:unknown,name:string,max:number){
 return v===undefined||v===null?null:requiredText(v,name,1,max);
}
function quantity(v:unknown){
 if(typeof v!=='string'||!/^[0-9]{1,14}(?:\.[0-9]{1,3})?$/.test(v))
  throw new ApiError(400,'INVALID_SHIPMENT_QUANTITY','Quantities must be exact decimal strings.');
 const x=new Prisma.Decimal(v);
 if(!x.gt(0))throw new ApiError(400,'INVALID_SHIPMENT_QUANTITY','Quantities must be positive.');
 return x;
}
function uuid(v:unknown,name:string):string{
 if(!isUuid(v))throw new ApiError(404,'NOT_FOUND','Invalid '+name+'.');
 return v;
}
function parsePlan(body:unknown){
 const input=record(body,['warehouseId','lines','carrierName','carrierPhoneE164','vehicleLabel','trackingReference','scheduledFrom','scheduledTo']);
 const warehouseId=uuid(input.warehouseId,'warehouseId');
 if(!Array.isArray(input.lines)||input.lines.length===0||input.lines.length>40)
  throw new ApiError(400,'SHIPMENT_LINES_REQUIRED','Shipment requires 1-40 order lines.');
 const seen=new Set<string>();
 const lines=input.lines.map(value=>{
  const row=record(value,['orderItemId','quantity']);
  const orderItemId=uuid(row.orderItemId,'orderItemId');
  if(seen.has(orderItemId))throw new ApiError(400,'DUPLICATE_SHIPMENT_LINE','Repeated shipment item.');
  seen.add(orderItemId);
  return {orderItemId,quantity:quantity(row.quantity)};
 });
 const carrierName=optText(input.carrierName,'carrierName',160);
 const carrierPhoneE164=optText(input.carrierPhoneE164,'carrierPhoneE164',20);
 if(carrierPhoneE164&&!/^\+[1-9][0-9]{7,14}$/.test(carrierPhoneE164))
  throw new ApiError(400,'INVALID_CARRIER_PHONE','Carrier phone must use E.164.');
 const vehicleLabel=optText(input.vehicleLabel,'vehicleLabel',80);
 const trackingReference=optText(input.trackingReference,'trackingReference',100);
 function date(value:unknown):Date|null{
  if(value===undefined||value===null)return null;
  if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(value))
   throw new ApiError(400,'INVALID_SHIPMENT_DATE','Shipment schedules require UTC ISO timestamps.');
  const result=new Date(value);
  if(Number.isNaN(result.getTime()))throw new ApiError(400,'INVALID_SHIPMENT_DATE','Invalid schedule timestamp.');
  return result;
 }
 const scheduledFrom=date(input.scheduledFrom),scheduledTo=date(input.scheduledTo);
 if(scheduledFrom&&scheduledTo&&scheduledFrom>scheduledTo)
  throw new ApiError(400,'INVALID_SHIPMENT_DATE','Shipment schedule end precedes start.');
 return {warehouseId,lines,carrierName,carrierPhoneE164,vehicleLabel,trackingReference,
  scheduledFrom,scheduledTo};
}
async function lockParent(tx:Tx,id:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid FOR UPDATE`);
 if(!rows.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
}
async function source(tx:Tx,supplierId:string,supplierOrderId:string){
 const row=await tx.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
  select:{id:true,purchaseOrderId:true}});
 if(!row)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 await lockParent(tx,row.purchaseOrderId);
 return tx.supplierOrder.findUniqueOrThrow({where:{id:supplierOrderId},select:{
  id:true,supplierId:true,status:true,acceptedAt:true,purchaseOrderId:true,
  purchaseOrder:{select:{status:true,currency:true,totalPaise:true,payments:{
   select:{provider:true,paymentMethod:true,status:true,amountPaise:true,
    capturedPaise:true,verifiedAt:true,providerPayRef:true}}}},
  items:{select:{id:true,listingId:true,quantity:true,allocatedShipmentQty:true,
   reservations:{select:{state:true,quantity:true,balance:{select:{warehouseId:true}}}},
   shipmentLines:{select:{quantity:true,rejectedQty:true,shipment:{select:{status:true,warehouseId:true}}}}
  }}
 }});
}
function paymentReady(order:Awaited<ReturnType<typeof source>>){
 const parent=order.purchaseOrder;
 if(!['CONFIRMED','PARTIALLY_FULFILLED','FULFILLED'].includes(parent.status)||
   parent.currency!=='INR'||
   !verifiedFulfillmentPayment(parent.payments,parent.totalPaise))
  throw new ApiError(409,'FULFILLMENT_PAYMENT_REQUIRED','Order has no reconciled payment or selected COD.');
 if(!order.items.length||order.items.some(item=>
  !item.listingId || !item.reservations.filter(r=>r.state==='COMMITTED')
    .reduce((s,r)=>s.plus(r.quantity),zero()).eq(item.quantity)))
  throw new ApiError(409,'FULFILLMENT_STOCK_REQUIRED','All listed order items must have committed stock.');
}
async function audit(tx:Tx,orderId:string,actorId:string,action:string,role:string){
 await tx.auditEvent.create({data:{entityType:'PurchaseOrder',entityId:orderId,
  action,actorUserId:actorId,actorRole:role}});
 await publishOutbox(tx,{eventKey:'ship:'+randomUUID(),eventType:action,
  aggregateType:'PurchaseOrder',aggregateId:orderId,payload:{orderId}});
}
async function supplierEvent(tx:Tx,supplierOrderId:string,
 from:string,to:'CONFIRMED'|'PACKING'|'READY'|'DISPATCHED'|'PARTIALLY_DELIVERED'|'DELIVERED'|'REJECTED',
 actor:string,reason?:string){
 await tx.supplierOrder.update({where:{id:supplierOrderId},data:{
  status:to,...(to==='CONFIRMED'?{acceptedAt:new Date()}:{} )
 }});
 await tx.supplierOrderEvent.create({data:{supplierOrderId,
  fromStatus:from as any,toStatus:to,actorUserId:actor,reason}});
}
async function shipmentEvent(tx:Tx,id:string,from:string|null,to:
 'PLANNED'|'PACKED'|'DISPATCHED'|'OUT_FOR_DELIVERY'|'PARTIALLY_DELIVERED'|'DELIVERED'|'CANCELLED',
 actor:string,detail?:Prisma.InputJsonObject){
 await tx.shipmentEvent.create({data:{shipmentId:id,fromStatus:from as any,
  toStatus:to,actorId:actor,...(detail?{detail}:{})}});
}
export async function supplierOrders(db:PrismaClient,userId:string,supplierId:string){
 await requireSupplierPermission(db,userId,supplierId,'SUPPLIER_READ');
 const rows=await db.supplierOrder.findMany({where:{supplierId},
  select:{id:true,purchaseOrderId:true,status:true,totalPaise:true,createdAt:true,
   items:{select:{id:true,skuSnapshot:true,quantity:true,unitCode:true}}},
  orderBy:{createdAt:'desc'},take:100});
 return rows.map(s=>({id:s.id,purchaseOrderId:s.purchaseOrderId,status:s.status,
  totalPaise:s.totalPaise.toString(),createdAt:s.createdAt.toISOString(),
  items:s.items.map(i=>({id:i.id,sku:i.skuSnapshot,
   quantity:i.quantity.toString(),unitCode:i.unitCode}))}));
}
export async function acceptSupplierOrder(db:PrismaClient,userId:string,
 supplierId:string,supplierOrderId:string){
 uuid(supplierId,'supplierId');uuid(supplierOrderId,'supplierOrderId');
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const s=await source(tx,supplierId,supplierOrderId);
  paymentReady(s);
  if(s.status==='CONFIRMED')return {id:s.id,status:s.status,replayed:true};
  if(s.status!=='PENDING_ACCEPTANCE')
   throw new ApiError(409,'ORDER_STATE_CONFLICT','Supplier order cannot be newly accepted.');
  await supplierEvent(tx,s.id,s.status,'CONFIRMED',userId);
  await audit(tx,s.purchaseOrderId,userId,'SUPPLIER_ORDER_ACCEPTED','SUPPLIER_FULFILLMENT');
  return {id:s.id,status:'CONFIRMED',replayed:false};
 });
}
/** Unpaid supplier refusal. Paid/COD orders must use a reconciled adjustment/refund path. */
export async function rejectUnpaidSupplierOrder(db:PrismaClient,userId:string,
 supplierId:string,supplierOrderId:string,body:unknown){
 uuid(supplierId,'supplierId');uuid(supplierOrderId,'supplierOrderId');
 const input=record(body,['reason']);
 const reason=requiredText(input.reason,'reason',12,200);
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const s=await source(tx,supplierId,supplierOrderId);
  if(s.status==='REJECTED')return {id:s.id,status:'REJECTED',replayed:true};
  if(s.status!=='PENDING_ACCEPTANCE')
   throw new ApiError(409,'ORDER_STATE_CONFLICT','Only pending supplier orders may be refused.');
  if(s.purchaseOrder.payments.length)
   throw new ApiError(409,'FINANCIAL_ADJUSTMENT_REQUIRED','Paid or COD-selected supplier orders need refund or finance reconciliation.');
  for(const r of await tx.inventoryReservation.findMany({where:{
   orderItem:{supplierOrderId},state:'HELD'},select:{id:true},orderBy:{id:'asc'}}))
   await releaseOrderItemStock(tx,r.id);
  await supplierEvent(tx,s.id,s.status,'REJECTED',userId,reason);
  await audit(tx,s.purchaseOrderId,userId,'UNPAID_SUPPLIER_ORDER_REJECTED','SUPPLIER_FULFILLMENT');
  return {id:s.id,status:'REJECTED',replayed:false};
 });
}
/** Atomic shipment line allocation, checked again by DB triggers under row locks. */
export async function planShipment(db:PrismaClient,userId:string,supplierId:string,
 supplierOrderId:string,key:string,body:unknown){
 uuid(supplierId,'supplierId');uuid(supplierOrderId,'supplierOrderId');
 const input=parsePlan(body);
 const result=await executeIdempotently(db,{actorId:userId,
  scope:'ship:'+supplierOrderId,requestKey:key,requestPayload:body,
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
   const order=await source(tx,supplierId,supplierOrderId);
   paymentReady(order);
   if(!['CONFIRMED','PACKING','READY','DISPATCHED','PARTIALLY_DELIVERED'].includes(order.status))
    throw new ApiError(409,'ORDER_STATE_CONFLICT','Supplier order cannot allocate shipment.');
   const wh=await tx.warehouse.findFirst({where:{
    id:input.warehouseId,supplierId,active:true},select:{id:true}});
   if(!wh)throw new ApiError(404,'NOT_FOUND','Warehouse not available.');
   const byId=new Map(order.items.map(i=>[i.id,i]));
   for(const line of input.lines){
    const item=byId.get(line.orderItemId);
    if(!item||!item.listingId)throw new ApiError(404,'NOT_FOUND','Supplier line not found.');
    const committed=item.reservations.filter(r=>r.state==='COMMITTED'&&
      r.balance.warehouseId===input.warehouseId).reduce((s,r)=>s.plus(r.quantity),zero());
    const already=item.shipmentLines.filter(r=>r.shipment.warehouseId===input.warehouseId&&
      active.includes(r.shipment.status as typeof active[number]))
      .reduce((s,r)=>s.plus(r.quantity.minus(r.shipment.status==='PARTIALLY_DELIVERED'?r.rejectedQty:zero())),zero());
    if(!committed.gte(already.plus(line.quantity))||
      !item.quantity.gte(item.allocatedShipmentQty.plus(line.quantity)))
     throw new ApiError(409,'SHIPMENT_ALLOCATION_EXCEEDED','Requested shipment exceeds committed unallocated stock.');
   }
   const created=await tx.shipment.create({data:{
    shipmentNumber:'SH-'+randomUUID().replaceAll('-','').slice(0,28).toUpperCase(),
    supplierOrderId,supplierId,warehouseId:input.warehouseId,
    status:'PLANNED',carrierName:input.carrierName,carrierPhoneE164:input.carrierPhoneE164,
    vehicleLabel:input.vehicleLabel,trackingReference:input.trackingReference,
    scheduledFrom:input.scheduledFrom,scheduledTo:input.scheduledTo
   },select:{id:true}});
   for(const line of input.lines.sort((a,b)=>a.orderItemId.localeCompare(b.orderItemId)))
    await tx.shipmentItem.create({data:{shipmentId:created.id,
     supplierOrderItemId:line.orderItemId,quantity:line.quantity}});
   await shipmentEvent(tx,created.id,null,'PLANNED',userId);
   if(order.status==='CONFIRMED')
    await supplierEvent(tx,supplierOrderId,order.status,'PACKING',userId);
   await audit(tx,order.purchaseOrderId,userId,'SHIPMENT_PLANNED','SUPPLIER_FULFILLMENT');
   return {result:created.id,resultRef:created.id,responseCode:201};
  }});
 await requireSupplierPermission(db,userId,supplierId,'ORDERS_FULFILL');
 const s=await db.shipment.findFirst({where:{id:result.resultRef,supplierId,supplierOrderId},select:shipSelect});
 if(!s)throw new ApiError(404,'NOT_FOUND','Shipment unavailable.');
 return {shipment:dto(s),replayed:result.kind==='replayed'};
}
async function shipmentSource(tx:Tx,supplierId:string,shipmentId:string){
 const found=await tx.shipment.findFirst({where:{id:shipmentId,supplierId},
  select:{id:true,supplierOrderId:true}});
 if(!found)throw new ApiError(404,'NOT_FOUND','Shipment unavailable.');
 const order=await source(tx,supplierId,found.supplierOrderId);
 const shipment=await tx.shipment.findUniqueOrThrow({where:{id:shipmentId},
  select:{id:true,supplierOrderId:true,status:true,otpIssuedAt:true,otpExpiresAt:true,
   deliveryOtpHash:true,otpVerifiedAt:true,otpAttempts:true,otpLockedUntil:true,
   exceptionApprovedAt:true,exceptionApprovedById:true,deliveredAt:true,
   items:{select:{id:true,supplierOrderItemId:true,quantity:true,deliveredQty:true,rejectedQty:true}}
  }});
 return {order,shipment};
}
export async function progressShipment(db:PrismaClient,userId:string,supplierId:string,
 shipmentId:string,action:'pack'|'dispatch'|'out-for-delivery'){
 uuid(supplierId,'supplierId');uuid(shipmentId,'shipmentId');
 const choices={
  pack:{from:'PLANNED',to:'PACKED'},dispatch:{from:'PACKED',to:'DISPATCHED'},
  'out-for-delivery':{from:'DISPATCHED',to:'OUT_FOR_DELIVERY'}
 } as const;
 const step=choices[action];
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const {order,shipment}=await shipmentSource(tx,supplierId,shipmentId);
  paymentReady(order);
  if(shipment.status===step.to)return {id:shipment.id,status:step.to,replayed:true};
  if(shipment.status!==step.from)
   throw new ApiError(409,'SHIPMENT_STATE_CONFLICT','Shipment cannot make that transition.');
  await tx.shipment.update({where:{id:shipment.id},data:{
   status:step.to,...(step.to==='DISPATCHED'?{dispatchedAt:new Date()}:{})
  }});
  await shipmentEvent(tx,shipment.id,step.from,step.to,userId);
  if(step.to==='PACKED'&&order.status==='PACKING')
   await supplierEvent(tx,order.id,order.status,'READY',userId);
  if(step.to==='DISPATCHED'&&['READY','PACKING','CONFIRMED'].includes(order.status))
   await supplierEvent(tx,order.id,order.status,'DISPATCHED',userId);
  await audit(tx,order.purchaseOrderId,userId,'SHIPMENT_'+step.to,'SUPPLIER_FULFILLMENT');
  return {id:shipment.id,status:step.to,replayed:false};
 });
}

/** Cancel before dispatch only. Database status trigger releases allocation. */
export async function cancelShipment(db:PrismaClient,userId:string,
 supplierId:string,shipmentId:string,body:unknown){
 uuid(supplierId,'supplierId');uuid(shipmentId,'shipmentId');
 const input=record(body,['reason']);
 const reason=requiredText(input.reason,'reason',8,500);
 return serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const {order,shipment}=await shipmentSource(tx,supplierId,shipmentId);
  if(shipment.status==='CANCELLED')
   return {shipmentId,status:'CANCELLED',replayed:true};
  if(!['PLANNED','PACKED'].includes(shipment.status))
   throw new ApiError(409,'SHIPMENT_ALREADY_DISPATCHED',
    'Dispatched loads require a separate carrier reconciliation.');
  await tx.shipment.update({where:{id:shipmentId},data:{status:'CANCELLED'}});
  await shipmentEvent(tx,shipmentId,shipment.status,'CANCELLED',userId,{reason});
  await audit(tx,order.purchaseOrderId,userId,'SHIPMENT_CANCELLED_BEFORE_DISPATCH',
   'SUPPLIER_FULFILLMENT');
  return {shipmentId,status:'CANCELLED',replayed:false};
 });
}

function otpHash(secret:string,shipmentId:string,time:Date,otp:string){
 return createHmac('sha256',secret).update('buildto:v21:delivery:'+
  shipmentId+':'+time.getTime()+':'+otp).digest('hex');
}
export async function issueCustomerHandoverOtp(db:PrismaClient,customerId:string,
 orderId:string,shipmentId:string,body:unknown,secret:string|undefined){
 uuid(orderId,'orderId');uuid(shipmentId,'shipmentId');record(body,[]);
 if(!secret||Buffer.byteLength(secret)<32)
  throw new ApiError(503,'OTP_SERVICE_NOT_CONFIGURED','Delivery verification is unavailable.');
 return serializable(db,async tx=>{
  const own=await tx.purchaseOrder.findFirst({where:{id:orderId,customerId},
   select:{id:true}});
  if(!own)throw new ApiError(404,'NOT_FOUND','Order not found.');
  await lockParent(tx,orderId);
  const found=await tx.shipment.findFirst({where:{
   id:shipmentId,supplierOrder:{purchaseOrderId:orderId}},
   select:{id:true,status:true,otpIssuedAt:true,otpExpiresAt:true,
    otpAttempts:true,otpLockedUntil:true}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Shipment not found.');
  if(found.status!=='OUT_FOR_DELIVERY')
   throw new ApiError(409,'OTP_NOT_AVAILABLE','Shipment is not ready for handover.');
  const now=new Date();
  if(found.otpLockedUntil&&found.otpLockedUntil>now)
   throw new ApiError(429,'OTP_LOCKED','Too many delivery OTP attempts.');
  if(found.otpExpiresAt&&found.otpExpiresAt>now)
   throw new ApiError(409,'OTP_ALREADY_ISSUED','Existing delivery code is still valid.');
  const otp=String(randomInt(0,1000000)).padStart(6,'0');
  const expiresAt=new Date(now.getTime()+5*60000);
  await tx.shipment.update({where:{id:shipmentId},data:{
   deliveryOtpHash:otpHash(secret,shipmentId,now,otp),
   otpIssuedAt:now,otpExpiresAt:expiresAt,otpVerifiedAt:null,
   otpAttempts:0,otpLockedUntil:null
  }});
  await audit(tx,orderId,customerId,'CUSTOMER_DELIVERY_OTP_ISSUED','CUSTOMER');
  // Returned to the authenticated CUSTOMER exactly once, NEVER to supplier.
  return {shipmentId,otp,expiresAt:expiresAt.toISOString()};
 });
}
async function fullyDelivered(tx:Tx,order:Awaited<ReturnType<typeof source>>,
 shipmentId:string,actor:string,method:'OTP'|'APPROVED_EXCEPTION',data:{
 otpVerifiedAt?:Date}){
 const ship=await tx.shipment.findUniqueOrThrow({where:{id:shipmentId},select:{
  status:true,items:{select:{id:true,quantity:true,deliveredQty:true,rejectedQty:true}}
 }});
 if(!ship.items.length||ship.items.some(i=>i.deliveredQty.gt(0)||i.rejectedQty.gt(0)))
  throw new ApiError(409,'SHIPMENT_QUANTITY_CONFLICT','Handover requires fully unconfirmed shipment lines.');
 for(const line of ship.items)
  await tx.shipmentItem.update({where:{id:line.id},data:{deliveredQty:line.quantity}});
 const now=new Date();
 await tx.shipment.update({where:{id:shipmentId},data:{
  status:'DELIVERED',deliveredAt:now,handoverMethod:method,...data
 }});
 await shipmentEvent(tx,shipmentId,ship.status,'DELIVERED',actor,
  {method,kind:'COMPLETE_SHIPMENT_HANDOVER'});
 // All purchased quantities must be delivered to mark the child delivered.
 const lines=await tx.supplierOrderItem.findMany({where:{supplierOrderId:order.id},
  select:{quantity:true,shipmentLines:{select:{deliveredQty:true,shipment:{select:{status:true}}}}}});
 const complete=lines.length>0&&lines.every(i=>i.shipmentLines
  .filter(s=>s.shipment.status==='DELIVERED'||s.shipment.status==='PARTIALLY_DELIVERED')
  .reduce((sum,s)=>sum.plus(s.deliveredQty),zero()).eq(i.quantity));
 const newState=complete?'DELIVERED':'PARTIALLY_DELIVERED';
 if(order.status!==newState)
  await supplierEvent(tx,order.id,order.status,newState,actor);
 await audit(tx,order.purchaseOrderId,actor,'SHIPMENT_DELIVERED_'+method,'SUPPLIER_FULFILLMENT');
 return {id:shipmentId,status:'DELIVERED' as const,
  supplierOrderStatus:newState,handoverMethod:method,replayed:false};
}
export async function confirmShipmentHandover(db:PrismaClient,userId:string,
 supplierId:string,shipmentId:string,body:unknown,secret:string|undefined){
 uuid(supplierId,'supplierId');uuid(shipmentId,'shipmentId');
 const input=record(body,['method','otp','mediaId','receivedBy']);
 if(input.method!=='OTP'&&input.method!=='EXCEPTION')
  throw new ApiError(400,'INVALID_HANDOVER_METHOD','Use OTP or EXCEPTION.');
 const receivedBy=input.receivedBy===undefined?null:requiredText(input.receivedBy,'receivedBy',2,160);
 const mediaId=input.mediaId===undefined?null:uuid(input.mediaId,'mediaId');
 if(input.method==='OTP'&&(typeof input.otp!=='string'||!/^[0-9]{6}$/.test(input.otp)))
  throw new ApiError(400,'INVALID_OTP','Enter the six digit delivery OTP.');
 if(input.method==='EXCEPTION'&&input.otp!==undefined)
  throw new ApiError(400,'INVALID_HANDOVER_REQUEST','Exception handover does not accept OTP.');
 if(input.method==='OTP'&&(!secret||Buffer.byteLength(secret)<32))
  throw new ApiError(503,'OTP_SERVICE_NOT_CONFIGURED','Delivery verification is unavailable.');
 const response=await serializable(db,async tx=>{
  await requireSupplierPermission(tx,userId,supplierId,'ORDERS_FULFILL');
  const {order,shipment}=await shipmentSource(tx,supplierId,shipmentId);
  paymentReady(order);
  if(shipment.status==='DELIVERED')
   return {kind:'success' as const,result:{id:shipmentId,status:'DELIVERED',replayed:true}};
  if(shipment.status!=='OUT_FOR_DELIVERY')
   throw new ApiError(409,'SHIPMENT_STATE_CONFLICT','Shipment is not awaiting handover.');
  if(mediaId){
   const asset=await tx.mediaAsset.findFirst({where:{id:mediaId,ownerUserId:userId},
    select:{id:true}});
   if(!asset)throw new ApiError(404,'NOT_FOUND','Owned evidence media not found.');
  }
  const now=new Date();
  if(input.method==='OTP'){
   if(shipment.otpLockedUntil&&shipment.otpLockedUntil>now)
    throw new ApiError(429,'OTP_LOCKED','Too many failed OTP submissions.');
   if(!shipment.otpIssuedAt||!shipment.deliveryOtpHash||!shipment.otpExpiresAt||
    shipment.otpExpiresAt<=now)
    throw new ApiError(409,'OTP_EXPIRED','Customer must issue a new delivery OTP.');
   const expected=Buffer.from(shipment.deliveryOtpHash,'hex');
   const got=Buffer.from(otpHash(secret!,shipmentId,shipment.otpIssuedAt,input.otp as string),'hex');
   if(expected.length!==32||!timingSafeEqual(expected,got)){
    const attempts=shipment.otpAttempts+1;
    const lockedUntil=attempts>=5?new Date(now.getTime()+30*60000):null;
    await tx.shipment.update({where:{id:shipmentId},data:{
     otpAttempts:Math.min(5,attempts),otpLockedUntil:lockedUntil
    }});
    await audit(tx,order.purchaseOrderId,userId,'SHIPMENT_OTP_ATTEMPT_FAILED','SUPPLIER_FULFILLMENT');
    return {kind:'bad' as const,locked:Boolean(lockedUntil)};
   }
   const done=await fullyDelivered(tx,order,shipmentId,userId,'OTP',{otpVerifiedAt:now});
   if(mediaId)await tx.deliveryProof.create({data:{shipmentId,mediaId,
    type:'HANDOVER_PHOTO',receivedBy}});
   return {kind:'success' as const,result:done};
  }
  if(!shipment.exceptionApprovedAt||!shipment.exceptionApprovedById)
   throw new ApiError(409,'EXCEPTION_APPROVAL_REQUIRED','Independent exception approval is required.');
  const done=await fullyDelivered(tx,order,shipmentId,userId,'APPROVED_EXCEPTION',{});
  if(mediaId)await tx.deliveryProof.create({data:{shipmentId,mediaId,
   type:'HANDOVER_PHOTO',receivedBy}});
  return {kind:'success' as const,result:done};
 });
 // Wrong attempts must commit the counter even though the API returns an error.
 if(response.kind==='bad')
  throw new ApiError(response.locked?429:422,response.locked?'OTP_LOCKED':'OTP_INCORRECT',
   response.locked?'Too many failed delivery OTP attempts.':'Delivery OTP did not match.');
 return response.result;
}
export async function approveDeliveryException(db:PrismaClient,adminId:string,
 shipmentId:string,body:unknown){
 uuid(shipmentId,'shipmentId');
 const input=record(body,['reason']);
 const reason=requiredText(input.reason,'reason',12,500);
 return serializable(db,async tx=>{
  await requireAdminPermission(tx,adminId,'SUPPORT_MANAGE');
  const found=await tx.shipment.findFirst({where:{id:shipmentId},
   select:{id:true,supplierId:true,supplierOrderId:true,
    supplierOrder:{select:{purchaseOrderId:true}}}});
  if(!found)throw new ApiError(404,'NOT_FOUND','Shipment not found.');
  await lockParent(tx,found.supplierOrder.purchaseOrderId);
  const member=await tx.supplierMember.findUnique({where:{
   supplierId_userId:{supplierId:found.supplierId,userId:adminId}},
   select:{active:true,revokedAt:true}});
  if(member?.active&&!member.revokedAt)
   throw new ApiError(403,'EXCEPTION_REQUIRES_INDEPENDENT_ADMIN',
    'Supplier personnel cannot approve their own delivery exception.');
  const s=await tx.shipment.findUniqueOrThrow({where:{id:shipmentId},
   select:{status:true,exceptionApprovedAt:true,exceptionApprovedById:true}});
  if(s.status!=='OUT_FOR_DELIVERY')
   throw new ApiError(409,'SHIPMENT_STATE_CONFLICT','Exceptions require a shipment awaiting handover.');
  if(s.exceptionApprovedAt)
   return {shipmentId,approved:true,replayed:true};
  await tx.shipment.update({where:{id:shipmentId},data:{
   exceptionReason:reason,exceptionApprovedById:adminId,exceptionApprovedAt:new Date()
  }});
  await audit(tx,found.supplierOrder.purchaseOrderId,adminId,
   'SHIPMENT_EXCEPTION_INDEPENDENTLY_APPROVED','ADMIN_SUPPORT');
  return {shipmentId,approved:true,replayed:false};
 });
}
export async function supplierShipments(db:PrismaClient,userId:string,supplierId:string,
 supplierOrderId:string){
 uuid(supplierId,'supplierId');uuid(supplierOrderId,'supplierOrderId');
 await requireSupplierPermission(db,userId,supplierId,'SUPPLIER_READ');
 const order=await db.supplierOrder.findFirst({where:{id:supplierOrderId,supplierId},
  select:{id:true}});
 if(!order)throw new ApiError(404,'NOT_FOUND','Supplier order not found.');
 const list=await db.shipment.findMany({where:{supplierOrderId,supplierId},
  select:shipSelect,orderBy:{createdAt:'asc'},take:100});
 return list.map(dto);
}
export async function customerShipments(db:PrismaClient,customerId:string,orderId:string){
 uuid(orderId,'orderId');
 const owner=await db.purchaseOrder.findFirst({where:{id:orderId,customerId},
  select:{id:true}});
 if(!owner)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const list=await db.shipment.findMany({where:{supplierOrder:{purchaseOrderId:orderId}},
  select:shipSelect,orderBy:{createdAt:'asc'},take:100});
 return list.map(dto);
}
