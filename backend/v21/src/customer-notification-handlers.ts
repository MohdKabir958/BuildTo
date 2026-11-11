import {PrismaClient} from '../../generated/buildto-v21';
import {executeIdempotently} from './idempotency';
import type {OutboxHandler,OutboxMessage} from './outbox';

// Only customer-safe, order-scoped events are routed here. Unknown event types remain
// PENDING for future explicitly registered integrations, not marked delivered.
const orderEvents={
 ORDER_AWAITING_PAYMENT:{kind:'ORDER',title:'Order awaiting payment',body:'Complete payment to confirm your material order.'},
 ORDER_CANCELLED:{kind:'ORDER',title:'Order cancelled',body:'Your materials order has been cancelled.'},
 ORDER_RESERVATION_EXPIRED:{kind:'ORDER',title:'Order expired',body:'Your pending order expired and its stock hold was released.'},
 PAYMENT_CAPTURED_ORDER_CONFIRMED:{kind:'PAYMENT',title:'Payment confirmed',body:'Your payment was verified and the materials order is confirmed.'},
 ORDER_COD_SELECTED:{kind:'ORDER',title:'Cash on delivery selected',body:'Your supplier order is confirmed for cash on delivery.'},
} as const;
export function customerNotificationHandlers(db:PrismaClient):ReadonlyMap<string,OutboxHandler>{
 const handlers=new Map<string,OutboxHandler>();
 for(const [eventType,copy] of Object.entries(orderEvents)){
  handlers.set(eventType,async(event:OutboxMessage)=>{
   if(event.aggregateType!=='PurchaseOrder')throw new Error('OUTBOX_AGGREGATE_MISMATCH');
   const order=await db.purchaseOrder.findUnique({
    where:{id:event.aggregateId},select:{customerId:true}
   });
   if(!order)throw new Error('OUTBOX_ORDER_NOT_FOUND');
   await executeIdempotently(db,{
    actorId:order.customerId,scope:'outbox-notification',requestKey:event.eventKey,
    requestPayload:{eventType,eventId:event.id,orderId:event.aggregateId},
    expiresAt:new Date(Date.now()+365*86400000),
    execute:async tx=>{
     const notice=await tx.notification.create({data:{
      userId:order.customerId,kind:copy.kind,title:copy.title,body:copy.body,
      deepLink:'/orders/'+event.aggregateId,
      payload:{orderId:event.aggregateId,eventType}
     },select:{id:true}});
     return {result:notice.id,resultRef:notice.id,responseCode:201};
    }
   });
  });
 }
 return handlers;
}
