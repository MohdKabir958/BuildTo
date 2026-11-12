'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('../../generated/buildto-v21');
const {customerNotificationHandlers}=require('../dist/customer-notification-handlers.js');
const {processOutboxBatch}=require('../dist/outbox.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());
test('outbox creates precisely one owned customer notice on replay',async()=>{
 const customer=await db.user.create({data:{displayName:'Notification test'}});
 const order=await db.purchaseOrder.create({data:{customerId:customer.id,clientRequestId:'notify_'+randomUUID(),
 publicNumber:'TEST-'+randomUUID().replaceAll('-','').slice(0,26),addressSnapshot:{},subtotalPaise:100n,totalPaise:100n}});
 const key='order:'+randomUUID();
 await db.outboxEvent.create({data:{eventKey:key,eventType:'ORDER_AWAITING_PAYMENT',
 aggregateId:order.id,aggregateType:'PurchaseOrder',payload:{orderId:order.id}}});
 const handlers=customerNotificationHandlers(db);
 await processOutboxBatch(db,handlers,20);
 const notices=await db.notification.findMany({where:{userId:customer.id,deepLink:'/orders/'+order.id}});
 assert.equal(notices.length,1);
 assert.equal(notices[0].kind,'ORDER');
 const event=await db.outboxEvent.findUniqueOrThrow({where:{eventKey:key}});
 assert.equal(event.status,'DELIVERED');
 // Explicitly replay the same event after a delivery acknowledgment failure.
 await handlers.get('ORDER_AWAITING_PAYMENT')({...event,eventType:event.eventType,aggregateType:event.aggregateType,aggregateId:event.aggregateId,attempts:2,payload:event.payload});
 assert.equal(await db.notification.count({where:{userId:customer.id,deepLink:'/orders/'+order.id}}),1);
});
test('unknown events stay pending rather than being falsely delivered',async()=>{
 const key='unknown:'+randomUUID();
 await db.outboxEvent.create({data:{eventKey:key,eventType:'UNHANDLED_FUTURE_EVENT',
 aggregateId:randomUUID(),aggregateType:'Future',payload:{}}});
 await processOutboxBatch(db,customerNotificationHandlers(db),20);
 const e=await db.outboxEvent.findUniqueOrThrow({where:{eventKey:key}});
 assert.equal(e.status,'PENDING');
});
