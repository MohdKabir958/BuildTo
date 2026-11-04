import {createHash,createHmac,timingSafeEqual,randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {publishOutbox} from './outbox';
import {commitOrderItemStock} from './inventory-reservations';
import type {PaymentGateway} from './payment-gateway';

type Tx=Prisma.TransactionClient;
const validUuid=(id:string)=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
const validKey=(key:string)=>/^[A-Za-z0-9:_-]{8,150}$/.test(key);
type PaymentMethod='UPI'|'CARD'|'NET_BANKING';
function parseMethod(body:unknown):PaymentMethod {
 if(!body||typeof body!=='object'||Array.isArray(body)||
  Object.keys(body).some(x=>x!=='paymentMethod'))
  throw new ApiError(400,'INVALID_PAYMENT_REQUEST','Only paymentMethod is accepted.');
 const method=(body as {paymentMethod?:unknown}).paymentMethod;
 if(method!=='UPI'&&method!=='CARD'&&method!=='NET_BANKING')
  throw new ApiError(422,'PAYMENT_METHOD_UNSUPPORTED','Select UPI, card or net banking.');
 return method;
}
function dto(p:{id:string;purchaseOrderId:string;paymentMethod:string;status:string;
 providerOrderRef:string|null;amountPaise:bigint;capturedPaise:bigint;createdAt:Date},publicKey:string){
 return {id:p.id,orderId:p.purchaseOrderId,provider:'RAZORPAY',paymentMethod:p.paymentMethod,
  status:p.status,providerOrderId:p.providerOrderRef,
  amountPaise:p.amountPaise.toString(),capturedPaise:p.capturedPaise.toString(),
  currency:'INR',keyId:publicKey,createdAt:p.createdAt.toISOString()};
}
async function lockOrder(tx:Tx,orderId:string){
 const rows=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${orderId}::uuid FOR UPDATE
 `);
 return rows.length>0;
}
async function audit(tx:Tx,orderId:string,actorId:string|null,action:string){
 await tx.auditEvent.create({data:{entityType:'PurchaseOrder',entityId:orderId,
  action,actorUserId:actorId,actorRole:actorId?'CUSTOMER_PAYMENT':'RAZORPAY_SIGNED_WEBHOOK'}});
 await publishOutbox(tx,{eventKey:'payment:'+randomUUID(),eventType:action,
  aggregateType:'PurchaseOrder',aggregateId:orderId,payload:{orderId}});
}

/** Create an internal attempt BEFORE any provider call. Replays never call the gateway again. */
export async function startPayment(db:PrismaClient,userId:string,orderId:string,
 key:string,body:unknown,gateway:PaymentGateway){
 if(!validUuid(orderId))throw new ApiError(400,'INVALID_ORDER_ID','Invalid order reference.');
 if(!validKey(key))throw new ApiError(400,'BAD_IDEMPOTENCY_KEY','Invalid Idempotency-Key.');
 const paymentMethod=parseMethod(body);
 const state=await serializable(db,async tx=>{
  if(!await lockOrder(tx,orderId))throw new ApiError(404,'NOT_FOUND','Order not found.');
  const order=await tx.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},
   select:{id:true,totalPaise:true,currency:true,status:true,
    supplierOrders:{select:{items:{select:{listingId:true,quantity:true,reservations:{
     select:{state:true,quantity:true,expiresAt:true}}}}}}}});
  if(!order)throw new ApiError(404,'NOT_FOUND','Order not found.');
  const previous=await tx.paymentAttempt.findUnique({where:{
   purchaseOrderId_idempotencyKey:{purchaseOrderId:orderId,idempotencyKey:key}
  }});
  if(previous){
   if(previous.paymentMethod!==paymentMethod)
    throw new ApiError(409,'IDEMPOTENCY_KEY_REUSED','Payment method differs from prior request.');
   return {id:previous.id,created:false};
  }
  if(order.status!=='PLACED')
   throw new ApiError(409,'ORDER_NOT_PAYABLE','Order is not waiting for payment.');
  if(order.currency!=='INR'||order.totalPaise<100n||order.totalPaise>100000000000n)
   throw new ApiError(422,'PAYMENT_AMOUNT_UNSUPPORTED','Order total cannot be paid online.');
  const all=order.supplierOrders.flatMap(s=>s.items);
  if(!all.length||all.some(i=>i.listingId &&
       !i.reservations.filter(r=>r.state==='HELD')
        .reduce((sum,r)=>sum.plus(r.quantity),new Prisma.Decimal(0)).eq(i.quantity)))
   throw new ApiError(409,'STOCK_NOT_RESERVED','The entire ordered quantity must be reserved.');
  if(all.some(i=>i.reservations.some(r=>r.state==='HELD'&&
       (!r.expiresAt||r.expiresAt.getTime()<=Date.now()+10_000))))
   throw new ApiError(409,'STOCK_RESERVATION_EXPIRED','Recreate the checkout order; stock hold expired.');
  const competing=await tx.paymentAttempt.findFirst({where:{
   purchaseOrderId:orderId,status:{in:['CREATED','PENDING','AUTHORIZED','CAPTURED']}
  },select:{id:true}});
  if(competing)throw new ApiError(409,'PAYMENT_ALREADY_IN_PROGRESS',
   'Existing payment must be reconciled before another attempt.');
  const created=await tx.paymentAttempt.create({data:{
   purchaseOrderId:orderId,provider:'RAZORPAY',paymentMethod,
   amountPaise:order.totalPaise,currency:'INR',idempotencyKey:key,status:'CREATED'
  },select:{id:true}});
  await audit(tx,orderId,userId,'PAYMENT_ATTEMPT_CREATED');
  return {id:created.id,created:true};
 });
 if(!state.created){
  const previous=await db.paymentAttempt.findUniqueOrThrow({where:{id:state.id}});
  return {payment:dto(previous,gateway.publicKey),replayed:true,
   initializing:previous.status==='CREATED'};
 }
 // Provider creation is deliberately OUTSIDE the transaction.
 const receipt='BT'+state.id.replaceAll('-','');
 let provider;
 try {
  provider=await gateway.createOrder({amount:BigInt((await db.paymentAttempt.findUniqueOrThrow({
   where:{id:state.id},select:{amountPaise:true}})).amountPaise),receipt});
 } catch {
  // Unknown external outcome: the receipt may already exist at Razorpay.
  // DO NOT retry blindly and risk a second provider order.
  throw new ApiError(503,'PAYMENT_INITIALIZATION_UNKNOWN',
   'Payment initialization is awaiting provider reconciliation.');
 }
 const stored=await serializable(db,async tx=>{
  if(!await lockOrder(tx,orderId))throw new Error('PAYMENT_ORDER_MISSING');
  const attempt=await tx.paymentAttempt.findUniqueOrThrow({where:{id:state.id}});
  if(attempt.amountPaise!==provider.amount||provider.receipt!==receipt||
   provider.currency!=='INR')
   throw new ApiError(503,'PAYMENT_PROVIDER_MISMATCH','Payment order mismatch.');
  if(attempt.providerOrderRef&&attempt.providerOrderRef!==provider.id)
   throw new ApiError(409,'PAYMENT_PROVIDER_CONFLICT','Payment order already associated.');
  if(attempt.status==='CREATED'){
   await tx.paymentAttempt.update({where:{id:attempt.id},data:{
    providerOrderRef:provider.id,status:'PENDING'
   }});
  }
  return tx.paymentAttempt.findUniqueOrThrow({where:{id:attempt.id}});
 });
 return {payment:dto(stored,gateway.publicKey),replayed:false,initializing:false};
}
export async function customerPayments(db:PrismaClient,userId:string,orderId:string,publicKey:string){
 if(!validUuid(orderId))throw new ApiError(400,'INVALID_ORDER_ID','Invalid order reference.');
 const order=await db.purchaseOrder.findFirst({where:{id:orderId,customerId:userId},
  select:{id:true,payments:{orderBy:{createdAt:'desc'},take:20}}});
 if(!order)throw new ApiError(404,'NOT_FOUND','Order not found.');
 return order.payments.map(p=>dto(p,publicKey));
}
export interface VerifiedGatewayEvent {
 id:string;name:string;hash:string;
 payment:{id:string;orderId:string;amount:bigint;currency:string;status:string;method:string}|null;
}
export function verifyRazorpayWebhook(body:Buffer,signature:string|undefined,
 eventId:string|undefined,secret:string):VerifiedGatewayEvent {
 if(!Buffer.isBuffer(body)||body.length===0||body.length>131072||
   !secret||!signature||!/^[0-9a-f]{64}$/i.test(signature)||
   !eventId||!/^[A-Za-z0-9_-]{6,180}$/.test(eventId))
  throw new ApiError(401,'INVALID_GATEWAY_WEBHOOK','Invalid payment notification.');
 const expected=createHmac('sha256',secret).update(body).digest();
 const supplied=Buffer.from(signature,'hex');
 if(supplied.length!==expected.length||!timingSafeEqual(expected,supplied))
  throw new ApiError(401,'INVALID_GATEWAY_WEBHOOK','Invalid payment notification.');
 let raw:unknown;
 try {raw=JSON.parse(body.toString('utf8'));}catch{
  throw new ApiError(400,'INVALID_GATEWAY_PAYLOAD','Invalid payment notification.');
 }
 if(!raw||typeof raw!=='object'||Array.isArray(raw))
  throw new ApiError(400,'INVALID_GATEWAY_PAYLOAD','Invalid payment notification.');
 const x=raw as Record<string,any>;
 if(typeof x.event!=='string'||x.event.length>120)
  throw new ApiError(400,'INVALID_GATEWAY_PAYLOAD','Invalid payment event.');
 const e=x.payload?.payment?.entity;
 let payment:VerifiedGatewayEvent['payment']=null;
 if(e&&typeof e==='object'&&typeof e.id==='string'&&
   typeof e.order_id==='string'&&Number.isSafeInteger(e.amount)&&e.amount>=0&&
   typeof e.currency==='string'&&typeof e.status==='string'&&
   typeof e.method==='string')
   payment={id:e.id,orderId:e.order_id,amount:BigInt(e.amount),
    currency:e.currency,status:e.status,method:e.method};
 return {id:eventId,name:x.event,hash:createHash('sha256').update(body).digest('hex'),payment};
}
export async function receiveRazorpayEvent(db:PrismaClient,event:VerifiedGatewayEvent){
 return serializable(db,async tx=>{
  // Event-ID unique across retries; reject same ID with a different signed body.
  const existing=await tx.providerWebhookEvent.findUnique({where:{
   provider_providerEventId:{provider:'RAZORPAY',providerEventId:event.id}
  }});
  if(existing&&existing.payloadHash!==event.hash)
   throw new ApiError(409,'WEBHOOK_REPLAY_CONFLICT','Event ID conflicts with previous payload.');
  if(existing?.processedAt)return {duplicate:true,retry:false};
  if(!existing)await tx.providerWebhookEvent.create({data:{
   provider:'RAZORPAY',providerEventId:event.id,eventType:event.name,
   payloadHash:event.hash,signatureOk:true
  }});
  const finish=async(code:string|null)=>tx.providerWebhookEvent.update({
   where:{provider_providerEventId:{provider:'RAZORPAY',providerEventId:event.id}},
   data:{processedAt:new Date(),errorCode:code}
  });
  if(!['payment.authorized','payment.captured','payment.failed','order.paid'].includes(event.name)){
   await finish('IGNORED_EVENT');return {duplicate:false,retry:false};
  }
  const payment=event.payment;
  if(!payment||!/^pay_[A-Za-z0-9]{8,60}$/.test(payment.id)||
   !/^order_[A-Za-z0-9]{8,60}$/.test(payment.orderId)){
   await finish('INVALID_EVENT_SHAPE');return {duplicate:false,retry:false};
  }
  // Lookup first, then lock parent order before payment row (same order as cancellation).
  const found=await tx.paymentAttempt.findUnique({where:{
   provider_providerOrderRef:{provider:'RAZORPAY',providerOrderRef:payment.orderId}
  },select:{id:true,purchaseOrderId:true}});
  if(!found){
   await tx.providerWebhookEvent.update({where:{
    provider_providerEventId:{provider:'RAZORPAY',providerEventId:event.id}
   },data:{errorCode:'PAYMENT_ATTEMPT_NOT_READY'}});
   return {duplicate:false,retry:true};
  }
  await lockOrder(tx,found.purchaseOrderId);
  const attempt=await tx.paymentAttempt.findUniqueOrThrow({where:{id:found.id}});
  const order=await tx.purchaseOrder.findUniqueOrThrow({where:{id:found.purchaseOrderId},
   select:{id:true,customerId:true,status:true,totalPaise:true,currency:true,
    supplierOrders:{select:{items:{select:{
     listingId:true,quantity:true,reservations:{select:{id:true,quantity:true,state:true,expiresAt:true}}
    }}}}}});
  if(payment.amount!==attempt.amountPaise||payment.amount!==order.totalPaise||
   payment.currency!=='INR'||order.currency!=='INR'||attempt.providerOrderRef!==payment.orderId){
   await finish('PAYMENT_AMOUNT_MISMATCH');
   await audit(tx,order.id,null,'PAYMENT_SECURITY_REVIEW_REQUIRED');
   return {duplicate:false,retry:false};
  }
  // A failure may describe only one failed checkout try within the same
  // Razorpay Order. It is NOT proof the entire order has permanently failed.
  if(event.name==='payment.failed'){
   await finish(null);return {duplicate:false,retry:false};
  }
  if(event.name==='payment.authorized'){
   if(payment.status==='authorized' && attempt.status==='PENDING'){
    await tx.paymentAttempt.update({where:{id:attempt.id},data:{
     status:'AUTHORIZED',providerPayRef:payment.id,verifiedAt:new Date()
    }});
   }
   await finish(null);return {duplicate:false,retry:false};
  }
  if(payment.status!=='captured'){
   await finish('CAPTURE_NOT_PROVEN');return {duplicate:false,retry:false};
  }
  if(attempt.status==='CAPTURED'){
   if(attempt.providerPayRef!==payment.id)await audit(tx,order.id,null,'PAYMENT_DUPLICATE_CAPTURE_REVIEW');
   await finish(attempt.providerPayRef===payment.id?null:'DUPLICATE_CAPTURE');
   return {duplicate:false,retry:false};
  }
  const other=await tx.paymentAttempt.findFirst({where:{purchaseOrderId:order.id,
   id:{not:attempt.id},status:'CAPTURED'},select:{id:true}});
  await tx.paymentAttempt.update({where:{id:attempt.id},data:{
   status:'CAPTURED',providerPayRef:payment.id,capturedPaise:payment.amount,
   verifiedAt:new Date()
  }});
  const items=order.supplierOrders.flatMap(s=>s.items);
  const holds=items.flatMap(i=>i.reservations.filter(r=>r.state==='HELD'));
  const invalidStock=items.some(i=>i.listingId&&
   !i.reservations.filter(r=>r.state==='HELD')
    .reduce((sum,r)=>sum.plus(r.quantity),new Prisma.Decimal(0)).eq(i.quantity))||
   holds.some(r=>!r.expiresAt||r.expiresAt.getTime()<=Date.now());
  if(other||order.status!=='PLACED'||invalidStock){
   // Money has arrived but fulfillment is NOT authorized. Finance must
   // reconcile/refund; never turn stale or cancelled stock into a sale.
   await audit(tx,order.id,null,'PAYMENT_CAPTURED_REQUIRES_REVIEW');
   await finish('MANUAL_REVIEW');
   return {duplicate:false,retry:false};
  }
  for(const hold of holds.sort((a,b)=>a.id.localeCompare(b.id)))
   await commitOrderItemStock(tx,hold.id);
  await tx.purchaseOrder.update({where:{id:order.id},data:{status:'CONFIRMED'}});
  await audit(tx,order.id,null,'PAYMENT_CAPTURED_ORDER_CONFIRMED');
  await finish(null);
  return {duplicate:false,retry:false};
 });
}
