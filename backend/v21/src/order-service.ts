import {randomUUID} from 'node:crypto';
import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {serializable} from './transaction';
import {executeIdempotently} from './idempotency';
import {stableRequestHash} from './contracts';
import {publishOutbox} from './outbox';
import {priceCheckout,lockedCartSnapshot,PricedCheckout} from './checkout-pricing';
import {recordOrderPromotion} from './promotion-service';
import {holdOrderItemStock,releaseOrderItemStock} from './inventory-reservations';
import {checkoutInput,placementInput,uuid} from './checkout-validation';

type Tx=Prisma.TransactionClient;
const quoteSelect={
 id:true,customerId:true,addressId:true,siteId:true,cartVersion:true,
 cartFingerprint:true,quoteSnapshot:true,subtotalPaise:true,discountPaise:true,
 taxPaise:true,deliveryPaise:true,totalPaise:true,status:true,expiresAt:true,createdAt:true
} as const;
function quoteDTO(quote:any){
 return {id:quote.id,addressId:quote.addressId,siteId:quote.siteId,
  cartVersion:quote.cartVersion,status:quote.status,
  expiresAt:quote.expiresAt.toISOString(),
  subtotalPaise:quote.subtotalPaise.toString(),
  discountPaise:quote.discountPaise.toString(),taxPaise:quote.taxPaise.toString(),
  deliveryPaise:quote.deliveryPaise.toString(),totalPaise:quote.totalPaise.toString(),
  breakdown:quote.quoteSnapshot};
}
const orderSelect={
 id:true,publicNumber:true,customerId:true,checkoutQuoteId:true,status:true,
 subtotalPaise:true,discountPaise:true,taxPaise:true,deliveryPaise:true,totalPaise:true,
 placedAt:true,cancelledAt:true,addressSnapshot:true,
 supplierOrders:{select:{
  id:true,supplierId:true,sourceQuoteId:true,status:true,subtotalPaise:true,discountPaise:true,
  taxPaise:true,deliveryPaise:true,totalPaise:true,
  items:{select:{id:true,listingId:true,skuSnapshot:true,nameSnapshot:true,
   unitCode:true,quantity:true,unitPrice:true,taxablePaise:true,
   discountPaise:true,taxPaise:true,lineTotalPaise:true,
   reservations:{where:{state:'HELD' as const},select:{expiresAt:true}}
  },orderBy:{id:'asc' as const}}
 },orderBy:{supplierId:'asc' as const}}
} as const;
function orderDTO(o:any){
 const expiry=o.supplierOrders.flatMap((s:any)=>s.items.flatMap((i:any)=>
  i.reservations.map((r:any)=>r.expiresAt?.toISOString()).filter(Boolean))).sort()[0]??null;
 return {
  id:o.id,publicNumber:o.publicNumber,checkoutQuoteId:o.checkoutQuoteId,
  status:o.status,paymentStatus:'AWAITING_PAYMENT_INTEGRATION',
  reservationExpiresAt:expiry,placedAt:o.placedAt.toISOString(),
  subtotalPaise:o.subtotalPaise.toString(),discountPaise:o.discountPaise.toString(),
  taxPaise:o.taxPaise.toString(),deliveryPaise:o.deliveryPaise.toString(),
  totalPaise:o.totalPaise.toString(),addressSnapshot:o.addressSnapshot,
  suppliers:o.supplierOrders.map((s:any)=>({
   id:s.id,supplierId:s.supplierId,sourceQuoteId:s.sourceQuoteId,status:s.status,
   subtotalPaise:s.subtotalPaise.toString(),discountPaise:s.discountPaise.toString(),
   taxPaise:s.taxPaise.toString(),deliveryPaise:s.deliveryPaise.toString(),
   totalPaise:s.totalPaise.toString(),
   items:s.items.map((i:any)=>({
    id:i.id,listingId:i.listingId,sku:i.skuSnapshot,name:i.nameSnapshot,
    unitCode:i.unitCode,quantity:i.quantity.toString(),unitPrice:i.unitPrice.toString(),
    taxablePaise:i.taxablePaise.toString(),discountPaise:i.discountPaise.toString(),
    taxPaise:i.taxPaise.toString(),lineTotalPaise:i.lineTotalPaise.toString()
   }))
  }))
 };
}
export async function outbox(tx:Tx,entityId:string,userId:string,eventType:string){
 await tx.auditEvent.create({data:{
  actorUserId:userId,actorRole:'CUSTOMER_ORDER',action:eventType,
  entityType:'PurchaseOrder',entityId
 }});
 await publishOutbox(tx,{eventKey:'order:'+randomUUID(),eventType,
  aggregateType:'PurchaseOrder',aggregateId:entityId,payload:{orderId:entityId}});
}
export async function previewCheckout(db:PrismaClient,userId:string,key:string,payload:unknown){
 const command=checkoutInput(payload);
 // Do not let an old abandoned checkout make currently available stock appear sold out.
 await recoverExpiredOrders(db,10);
 const saved=await executeIdempotently(db,{
  actorId:userId,scope:'checkout-preview',requestKey:key,requestPayload:payload,
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   const pricing=await priceCheckout(tx,userId,command);
   if(pricing.cartVersion!==command.expectedCartVersion)
    throw new ApiError(409,'CART_VERSION_CONFLICT','Refresh cart before pricing.');
   const row=await tx.checkoutQuote.create({data:{
    customerId:userId,addressId:command.addressId,siteId:command.siteId,
    cartVersion:pricing.cartVersion,
    cartFingerprint:stableRequestHash(pricing.items.map(x=>({id:x.listingId,qty:x.quantity}))),
    addressSnapshot:pricing.addressSnapshot,
    quoteSnapshot:pricing as unknown as Prisma.InputJsonObject,
    currency:'INR',subtotalPaise:BigInt(pricing.subtotalPaise),
    discountPaise:BigInt(pricing.discountPaise),taxPaise:BigInt(pricing.taxPaise),
    deliveryPaise:BigInt(pricing.deliveryPaise),totalPaise:BigInt(pricing.totalPaise),
    expiresAt:new Date(Date.now()+10*60000)
   },select:{id:true}});
   return {result:row.id,resultRef:row.id,responseCode:201};
  }
 });
 const quote=await db.checkoutQuote.findFirst({where:{id:saved.resultRef,customerId:userId},
  select:quoteSelect});
 if(!quote)throw new ApiError(404,'NOT_FOUND','Checkout quote not found.');
 return {quote:quoteDTO(quote),replayed:saved.kind==='replayed'};
}
export async function getCheckoutQuote(db:PrismaClient,userId:string,id:string){
 uuid(id,'quoteId');
 const quote=await db.checkoutQuote.findFirst({where:{id,customerId:userId},select:quoteSelect});
 if(!quote)throw new ApiError(404,'NOT_FOUND','Checkout quote not found.');
 return quoteDTO(quote);
}
async function ensureOrder(db:PrismaClient,userId:string,id:string){
 const row=await db.purchaseOrder.findFirst({where:{id,customerId:userId},select:orderSelect});
 if(!row)throw new ApiError(404,'NOT_FOUND','Order not found.');
 return orderDTO(row);
}
export async function listCustomerOrders(db:PrismaClient,userId:string){
 const rows=await db.purchaseOrder.findMany({where:{customerId:userId},
  select:orderSelect,orderBy:{placedAt:'desc'},take:100});
 return rows.map(orderDTO);
}
export async function getCustomerOrder(db:PrismaClient,userId:string,id:string){
 uuid(id,'orderId');
 return ensureOrder(db,userId,id);
}
export async function reserveStock(tx:Tx,itemId:string,listingId:string,supplierId:string,quantity:string,expiresAt:Date){
 let need=new Prisma.Decimal(quantity);
 const balances=await tx.inventoryBalance.findMany({where:{
  listingId,warehouse:{supplierId,active:true}
 },select:{warehouseId:true,onHandQty:true,reservedQty:true},orderBy:{warehouseId:'asc'}});
 for(const b of balances){
  const available=b.onHandQty.minus(b.reservedQty);
  if(available.lte(0))continue;
  const portion=Prisma.Decimal.min(available,need);
  await holdOrderItemStock(tx,{supplierId,orderItemId:itemId,warehouseId:b.warehouseId,
   quantity:portion.toFixed(3),expiresAt});
  need=need.minus(portion);
  if(need.isZero())break;
 }
 if(!need.isZero())throw new ApiError(409,'INSUFFICIENT_AVAILABLE_STOCK',
  'Another order changed warehouse stock. Refresh checkout.');
}
export async function placeCheckoutOrder(db:PrismaClient,userId:string,quoteId:string,
 key:string,payload:unknown){
 uuid(quoteId,'quoteId');
 const command=placementInput(payload);
 // Reclaim abandoned holds in bounded batches without a second service.
 // PR 09 will coordinate payment state with this expiry/cancellation policy.
 await recoverExpiredOrders(db,10);
 const saved=await executeIdempotently(db,{
  actorId:userId,scope:'checkout-place',requestKey:key,
  requestPayload:{quoteId,clientRequestId:command.clientRequestId},
  expiresAt:new Date(Date.now()+86400000),
  execute:async tx=>{
   const locks=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
    SELECT id FROM "CheckoutQuote" WHERE id=${quoteId}::uuid
     AND "customerId"=${userId}::uuid FOR UPDATE
   `);
   if(!locks.length)throw new ApiError(404,'NOT_FOUND','Checkout quote not found.');
   const quote=await tx.checkoutQuote.findUniqueOrThrow({where:{id:quoteId},select:quoteSelect});
   if(quote.status!=='OPEN'||quote.expiresAt<=new Date())
    throw new ApiError(409,'CHECKOUT_QUOTE_EXPIRED','Checkout quote is not active. Create a new one.');
   const savedPricing=quote.quoteSnapshot as unknown as PricedCheckout;
   const priced=await priceCheckout(tx,userId,{
    addressId:quote.addressId,siteId:quote.siteId,
    promotionCode:savedPricing.promotionCode
   });
   if(priced.cartVersion!==quote.cartVersion||
      stableRequestHash(priced)!==stableRequestHash(savedPricing))
    throw new ApiError(409,'CHECKOUT_CHANGED','Prices, address, freight or cart changed. Recheck checkout.');
   if(priced.totalPaise!==quote.totalPaise.toString()||
      priced.subtotalPaise!==quote.subtotalPaise.toString()||
      priced.taxPaise!==quote.taxPaise.toString()||
      priced.deliveryPaise!==quote.deliveryPaise.toString()||
      priced.discountPaise!==quote.discountPaise.toString())
    throw new ApiError(409,'CHECKOUT_CHANGED','Order totals no longer match.');
   const previous=await tx.purchaseOrder.findUnique({where:{
    customerId_clientRequestId:{customerId:userId,clientRequestId:command.clientRequestId}
   },select:{id:true}});
   if(previous)throw new ApiError(409,'CLIENT_REQUEST_ID_REUSED','Use a new request ID for a new order.');
   const order=await tx.purchaseOrder.create({data:{
    customerId:userId,checkoutQuoteId:quoteId,clientRequestId:command.clientRequestId,
    publicNumber:'BT-'+randomUUID().replaceAll('-','').slice(0,26).toUpperCase(),
    currency:'INR',status:'PLACED',addressSnapshot:priced.addressSnapshot,
    siteId:priced.siteId,subtotalPaise:BigInt(priced.subtotalPaise),
    discountPaise:BigInt(priced.discountPaise),taxPaise:BigInt(priced.taxPaise),
    deliveryPaise:BigInt(priced.deliveryPaise),totalPaise:BigInt(priced.totalPaise)
   },select:{id:true}});
   // All split supplier orders, line snapshots, and warehouse holds commit
   // together. Failure for one supplier rolls back the ENTIRE customer order.
   const expiresAt=new Date(Date.now()+20*60000);
   for(const supplier of priced.suppliers){
    const child=await tx.supplierOrder.create({data:{
     purchaseOrderId:order.id,supplierId:supplier.supplierId,
     status:'PENDING_ACCEPTANCE',subtotalPaise:BigInt(supplier.subtotalPaise),
     discountPaise:BigInt(supplier.discountPaise),taxPaise:BigInt(supplier.taxPaise),
     deliveryPaise:BigInt(supplier.deliveryPaise),totalPaise:BigInt(supplier.totalPaise)
    },select:{id:true}});
    for(const item of priced.items.filter(x=>x.supplierId===supplier.supplierId)
     .sort((a,b)=>a.listingId.localeCompare(b.listingId))){
     const created=await tx.supplierOrderItem.create({data:{
      supplierOrderId:child.id,listingId:item.listingId,
      skuSnapshot:item.sku,nameSnapshot:item.productName,brandSnapshot:item.brandName,
      hsnSnapshot:item.hsnCode,unitCode:item.unitCode,
      packSizeSnapshot:new Prisma.Decimal(item.packSize),
      quantity:new Prisma.Decimal(item.quantity),unitPrice:new Prisma.Decimal(item.unitPrice),
      taxRateBps:item.taxRateBps,taxablePaise:BigInt(item.taxablePaise),
      taxPaise:BigInt(item.taxPaise),discountPaise:BigInt(item.discountPaise),
      cgstPaise:BigInt(item.cgstPaise),sgstPaise:BigInt(item.sgstPaise),
      utgstPaise:BigInt(item.utgstPaise),igstPaise:BigInt(item.igstPaise),
      cessPaise:BigInt(item.cessPaise),
      lineTotalPaise:BigInt(item.lineTotalPaise),
      attributesSnapshot:{listingVersion:item.listingVersion,taxInclusive:item.taxInclusive}
     },select:{id:true}});
     await reserveStock(tx,created.id,item.listingId,supplier.supplierId,item.quantity,expiresAt);
    }
   }
   if(priced.promotionCode)
    await recordOrderPromotion(tx,{code:priced.promotionCode,customerId:userId,orderId:order.id});
   await tx.checkoutQuote.update({where:{id:quoteId},data:{status:'CONSUMED'}});
   const cart=await lockedCartSnapshot(tx,userId);
   await tx.cartLine.deleteMany({where:{cartId:cart.id}});
   await tx.cart.update({where:{id:cart.id},data:{version:{increment:1}}});
   await outbox(tx,order.id,userId,'ORDER_AWAITING_PAYMENT');
   return {result:order.id,resultRef:order.id,responseCode:201};
  }
 });
 return {order:await ensureOrder(db,userId,saved.resultRef),replayed:saved.kind==='replayed'};
}
// Cancellation and expiration are safe only before a payment integration owns
// the order. PR 09 must lock the same PurchaseOrder row for gateway transitions.
async function cancelUnpaid(tx:Tx,id:string,userId:string|null,expired:boolean){
 const ids=await tx.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT id FROM "PurchaseOrder" WHERE id=${id}::uuid
    ${userId?Prisma.sql`AND "customerId"=${userId}::uuid`:Prisma.empty}
   FOR UPDATE
 `);
 if(!ids.length)throw new ApiError(404,'NOT_FOUND','Order not found.');
 const order=await tx.purchaseOrder.findUniqueOrThrow({where:{id},select:{
  id:true,customerId:true,status:true,placedAt:true,
  payments:{select:{status:true}},
  supplierOrders:{select:{id:true,items:{select:{reservations:{
   where:{state:'HELD'},select:{id:true,expiresAt:true}
  }}}}}
 }});
 if(order.status==='CANCELLED')return {id,state:'CANCELLED',replayed:true};
 if(order.status!=='PLACED')throw new ApiError(409,'ORDER_NOT_CANCELLABLE','Order is no longer pending.');
 if(order.payments.some(p=>!['FAILED','CANCELLED'].includes(p.status)))
  throw new ApiError(409,'PAYMENT_IN_PROGRESS','Order has a payment attempt. Contact support.');
 const holds=order.supplierOrders.flatMap(s=>s.items.flatMap(i=>i.reservations));
 if(expired&&holds.some(h=>h.expiresAt&&h.expiresAt.getTime()>Date.now()))
  throw new ApiError(409,'ORDER_NOT_EXPIRED','Order has active stock reservations.');
 for(const hold of holds.sort((a,b)=>a.id.localeCompare(b.id)))
  await releaseOrderItemStock(tx,hold.id,expired?'EXPIRED':'RELEASED');
 await tx.supplierOrder.updateMany({where:{purchaseOrderId:id},
  data:{status:'CANCELLED',cancelledAt:new Date()}});
 await tx.purchaseOrder.update({where:{id},data:{status:'CANCELLED',cancelledAt:new Date()}});
 // This order never reached payment confirmation; release coupon capacity.
 await tx.promotionRedemption.deleteMany({where:{orderId:id}});
 await outbox(tx,id,order.customerId,expired?'ORDER_RESERVATION_EXPIRED':'ORDER_CANCELLED');
 return {id,state:'CANCELLED',replayed:false};
}
export async function cancelCustomerOrder(db:PrismaClient,userId:string,id:string){
 uuid(id,'orderId');
 const result=await serializable(db,tx=>cancelUnpaid(tx,id,userId,false));
 return result;
}
export async function recoverExpiredOrders(db:PrismaClient,limit=10){
 if(!Number.isInteger(limit)||limit<1||limit>25)throw new Error('INVALID_RECOVERY_LIMIT');
 const ids=await db.$queryRaw<{id:string}[]>(Prisma.sql`
  SELECT DISTINCT po.id FROM "PurchaseOrder" po
   JOIN "SupplierOrder" so ON so."purchaseOrderId"=po.id
   JOIN "SupplierOrderItem" item ON item."supplierOrderId"=so.id
   JOIN "InventoryReservation" res ON res."orderItemId"=item.id
  WHERE po.status='PLACED' AND res.state='HELD'
   AND res."expiresAt"<=NOW()
   AND NOT EXISTS (SELECT 1 FROM "PaymentAttempt" payment
      WHERE payment."purchaseOrderId"=po.id
       AND payment.status NOT IN ('FAILED','CANCELLED'))
  ORDER BY po.id LIMIT ${limit}
 `);
 let reclaimed=0,skipped=0;
 for(const candidate of ids){
  try{
   await serializable(db,tx=>cancelUnpaid(tx,candidate.id,null,true));
   reclaimed++;
  }catch(err){
   if(err instanceof ApiError&&['ORDER_NOT_EXPIRED','ORDER_NOT_CANCELLABLE','PAYMENT_IN_PROGRESS'].includes(err.code)){
    skipped++;continue;
   }
   throw err;
  }
 }
 return {reclaimed,skipped};
}
