import {Prisma,PrismaClient} from '../../generated/buildto-v21';

export interface OutboxMessage {
  id:string;eventKey:string;eventType:string;aggregateId:string;aggregateType:string;
  payload:Prisma.JsonValue;attempts:number;
}
export interface OutboxIntent {
  eventKey:string;eventType:string;aggregateId:string;aggregateType:string;
  payload:Prisma.InputJsonValue;
}
export async function publishOutbox(tx:Prisma.TransactionClient,intent:OutboxIntent):Promise<void> {
  if(!intent.eventKey||intent.eventKey.length>180)throw new Error('INVALID_OUTBOX_EVENT_KEY');
  await tx.outboxEvent.create({data:intent});
}
// SKIP LOCKED prevents workers on two replicas from taking the same event concurrently.
// Expired leases are eligible for re-claim. At-least-once delivery: external handlers MUST deduplicate on eventKey.
export async function claimOutbox(db:PrismaClient,limit=20,leaseSeconds=45):Promise<OutboxMessage[]> {
  if(!Number.isInteger(limit)||limit<1||limit>50||!Number.isInteger(leaseSeconds)||leaseSeconds<10||leaseSeconds>300)
    throw new Error('INVALID_OUTBOX_CLAIM');
  return db.$queryRaw<OutboxMessage[]>(Prisma.sql`
    WITH candidates AS (
      SELECT id FROM "OutboxEvent"
      WHERE (
        ("status" IN ('PENDING','FAILED') AND ("nextAttemptAt" IS NULL OR "nextAttemptAt" <= NOW()))
        OR ("status" = 'PROCESSING' AND "leaseUntil" <= NOW())
      )
      ORDER BY "createdAt","id"
      FOR UPDATE SKIP LOCKED
      LIMIT ${limit}
    )
    UPDATE "OutboxEvent" AS e SET
      "status"='PROCESSING',
      "attempts"=e."attempts"+1,
      "leaseUntil"=NOW()+ (${leaseSeconds}::integer * interval '1 second'),
      "nextAttemptAt"=NULL
    FROM candidates WHERE e.id=candidates.id
    RETURNING e.id,e."eventKey",e."eventType",e."aggregateId",e."aggregateType",e.payload,e.attempts
  `);
}
export async function acknowledgeOutbox(db:PrismaClient,message:Pick<OutboxMessage,'id'|'attempts'>):Promise<boolean> {
  const result=await db.outboxEvent.updateMany({where:{id:message.id,status:'PROCESSING',attempts:message.attempts},data:{
    status:'DELIVERED',deliveredAt:new Date(),leaseUntil:null,lastErrorCode:null,nextAttemptAt:null
  }});
  return result.count===1;
}
export async function rejectOutbox(db:PrismaClient,message:Pick<OutboxMessage,'id'|'attempts'>,reasonCode:string,maxAttempts=8):Promise<boolean> {
  if(!/^[A-Z0-9_]{1,60}$/.test(reasonCode)||!Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>50)
    throw new Error('INVALID_OUTBOX_RETRY_POLICY');
  const dead=message.attempts>=maxAttempts;
  const seconds=Math.min(3600,Math.pow(2,Math.min(message.attempts,11))*5);
  const result=await db.outboxEvent.updateMany({where:{id:message.id,status:'PROCESSING',attempts:message.attempts},data:{
    status:dead?'DEAD':'FAILED',leaseUntil:null,lastErrorCode:reasonCode,
    nextAttemptAt:dead?null:new Date(Date.now()+seconds*1000)
  }});
  return result.count===1;
}
export type OutboxHandler=(message:OutboxMessage)=>Promise<void>;
export async function processOutboxBatch(db:PrismaClient,handlers:ReadonlyMap<string,OutboxHandler>,limit=20) {
  const events=await claimOutbox(db,limit);
  let completed=0,failed=0,unclaimed=0;
  for(const event of events) {
    const handler=handlers.get(event.eventType);
    try {
      if(!handler)throw new Error('HANDLER_MISSING');
      await handler(event);
      if(await acknowledgeOutbox(db,event))completed++;else unclaimed++;
    }catch {
      // Do not log or persist exception messages; they can include PII or provider secrets.
      if(await rejectOutbox(db,event,handler?'DELIVERY_FAILED':'HANDLER_MISSING'))failed++;else unclaimed++;
    }
  }
  return {claimed:events.length,completed,failed,unclaimed};
}
