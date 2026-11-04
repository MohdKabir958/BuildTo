'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('../../generated/buildto-v21');
const {executeIdempotently}=require('../dist/idempotency.js');
const {publishOutbox,claimOutbox,acknowledgeOutbox,rejectOutbox,processOutboxBatch}=require('../dist/outbox.js');
const db=new PrismaClient();
test.after(async()=>db.$disconnect());

test('idempotency key and business outbox event commit atomically, duplicate replays',async()=>{
 const actorId=randomUUID(),key='order_'+randomUUID().replaceAll('-',''),eventKey='ci:'+randomUUID();
 let businessCalls=0;
 const command={
   actorId,scope:'test-order',requestKey:key,
   requestPayload:{itemId:'cement',qty:2},expiresAt:new Date(Date.now()+3600_000),
   execute:async tx=>{
     businessCalls++;
     await publishOutbox(tx,{eventKey,eventType:'ci.test-event',aggregateType:'ci',
       aggregateId:actorId,payload:{qty:2}});
     return {result:{ok:true},resultRef:eventKey,responseCode:201};
   }
 };
 const a=await executeIdempotently(db,command);
 assert.equal(a.kind,'created');
 const b=await executeIdempotently(db,command);
 assert.equal(b.kind,'replayed');
 assert.equal(b.resultRef,eventKey);
 assert.equal(businessCalls,1);
 assert.equal(await db.outboxEvent.count({where:{eventKey}}),1);
 await assert.rejects(
  executeIdempotently(db,{...command,requestPayload:{itemId:'cement',qty:3}}),
  e=>e.code==='IDEMPOTENCY_KEY_REUSED'
 );
});
test('failed business mutation rolls back idempotency record and outbox write',async()=>{
 const actorId=randomUUID(),key='test_'+randomUUID().replaceAll('-',''),eventKey='ci:'+randomUUID();
 await assert.rejects(executeIdempotently(db,{
   actorId,scope:'test-rollback',requestKey:key,requestPayload:{qty:1},
   expiresAt:new Date(Date.now()+3600_000),
   execute:async tx=>{
      await publishOutbox(tx,{eventKey,eventType:'ci.test',aggregateType:'ci',
        aggregateId:actorId,payload:{}});
      throw new Error('expected rollback');
   }
 }),/expected rollback/);
 assert.equal(await db.idempotencyRecord.count({where:{actorId,scope:'test-rollback',requestKey:key}}),0);
 assert.equal(await db.outboxEvent.count({where:{eventKey}}),0);
});
test('two concurrent workers SKIP LOCKED and cannot claim identical events',async()=>{
 // Prevent older fixtures from consuming our limited claim budget.
 await db.outboxEvent.deleteMany({where:{eventKey:{startsWith:'ci:'}}});
 const keys=Array.from({length:4},()=>('ci:'+randomUUID()));
 for(const eventKey of keys){
   await db.outboxEvent.create({data:{eventKey,eventType:'ci.claim',
     aggregateType:'ci',aggregateId:randomUUID(),payload:{key:eventKey},
     createdAt:new Date('2000-01-02T00:00:00Z')}});
 }
 const [left,right]=await Promise.all([claimOutbox(db,2,10),claimOutbox(db,2,10)]);
 const claimed=[...left,...right];
 assert.equal(claimed.length,4);
 assert.equal(new Set(claimed.map(x=>x.id)).size,4);
 assert.deepEqual(new Set(claimed.map(x=>x.eventKey)),new Set(keys));
 for(const msg of claimed){
    assert.equal(await acknowledgeOutbox(db,msg),true);
    assert.equal(await acknowledgeOutbox(db,msg),false);
 }
});
test('failed delivery can terminally DEAD-letter and stale worker cannot rewrite it',async()=>{
 const eventKey='ci:'+randomUUID();
 const record=await db.outboxEvent.create({data:{eventKey,eventType:'ci.dead',
    aggregateType:'ci',aggregateId:randomUUID(),payload:{},
    createdAt:new Date('2000-01-01T00:00:00Z')}});
 const events=await claimOutbox(db,20,10);
 const event=events.find(x=>x.id===record.id);
 assert(event);
 assert.equal(await rejectOutbox(db,event,'DELIVERY_FAILED',1),true);
 const after=await db.outboxEvent.findUniqueOrThrow({where:{id:record.id}});
 assert.equal(after.status,'DEAD');
 assert.equal(after.nextAttemptAt,null);
 assert.equal(await rejectOutbox(db,event,'DELIVERY_FAILED',1),false);
});
test('dispatcher processes registered handlers and persists success',async()=>{
 const eventKey='ci:'+randomUUID(),aggregateId=randomUUID();
 await db.outboxEvent.create({data:{eventKey,eventType:'ci.handler',
    aggregateType:'ci',aggregateId,payload:{ok:true},
    createdAt:new Date('2000-01-01T00:00:00Z')}});
 let count=0;
 const handlers=new Map([['ci.handler',async msg=>{
   if(msg.eventKey===eventKey)count++;
 }]]);
 await processOutboxBatch(db,handlers,20);
 assert.equal(count,1);
 const updated=await db.outboxEvent.findUniqueOrThrow({where:{eventKey}});
 assert.equal(updated.status,'DELIVERED');
});
