import {Prisma,PrismaClient} from '../../generated/buildto-v21';
import {ApiError} from './errors';
import {stableRequestHash} from './contracts';

export interface IdempotentCommand<T> {
  actorId:string;
  scope:string;
  requestKey:string;
  requestPayload:unknown;
  expiresAt:Date;
  execute:(tx:Prisma.TransactionClient)=>Promise<{result:T,resultRef:string,responseCode:number}>;
}
export type IdempotentResult<T> =
  | {kind:'created',value:T,resultRef:string,responseCode:number}
  | {kind:'replayed',resultRef:string,responseCode:number};

// The unique reservation AND business mutation happen in ONE SERIALIZABLE transaction.
// Never make outbound payment/gateway/network calls within execute(); write an outbox intent instead.
export async function executeIdempotently<T>(db:PrismaClient,command:IdempotentCommand<T>):Promise<IdempotentResult<T>> {
  if(!/^[A-Za-z0-9:_-]{1,100}$/.test(command.scope)||
     !/^[A-Za-z0-9:_-]{8,180}$/.test(command.requestKey)||
     !/^[0-9a-f-]{36}$/.test(command.actorId)) throw new ApiError(400,'BAD_IDEMPOTENCY_KEY','Invalid idempotency information.');
  if(!(command.expiresAt instanceof Date)||command.expiresAt.getTime()<=Date.now())
    throw new ApiError(400,'BAD_IDEMPOTENCY_EXPIRY','An unexpired idempotency window is required.');
  const requestHash=stableRequestHash(command.requestPayload);
  const lockKey=command.actorId+':'+command.scope+':'+command.requestKey;
  return db.$transaction(async tx=>{
    // Advisory *transaction* lock makes repeated requests serialize even before the row exists.
    await tx.$queryRaw(Prisma.sql`SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))`);
    const where={actorId_scope_requestKey:{actorId:command.actorId,scope:command.scope,requestKey:command.requestKey}};
    const existing=await tx.idempotencyRecord.findUnique({where});
    if(existing && existing.expiresAt.getTime()>Date.now()) {
      if(existing.requestHash!==requestHash)throw new ApiError(409,'IDEMPOTENCY_KEY_REUSED','Request key was used with a different payload.');
      if(existing.resultRef&&existing.responseCode) return {kind:'replayed',resultRef:existing.resultRef,responseCode:existing.responseCode} as const;
      throw new ApiError(409,'IDEMPOTENCY_IN_PROGRESS','Request is already in progress.');
    }
    if(existing)await tx.idempotencyRecord.delete({where});
    const record=await tx.idempotencyRecord.create({data:{
      actorId:command.actorId,scope:command.scope,requestKey:command.requestKey,
      requestHash,expiresAt:command.expiresAt
    }});
    const created=await command.execute(tx);
    if(!created.resultRef||created.resultRef.length>180||!Number.isInteger(created.responseCode)||created.responseCode<200||created.responseCode>299)
      throw new Error('INVALID_IDEMPOTENCY_RESULT');
    await tx.idempotencyRecord.update({where:{id:record.id},data:{
      resultRef:created.resultRef,responseCode:created.responseCode,
      responseHash:stableRequestHash({ref:created.resultRef,status:created.responseCode})
    }});
    return {kind:'created',value:created.result,resultRef:created.resultRef,responseCode:created.responseCode} as const;
  },{isolationLevel:Prisma.TransactionIsolationLevel.Serializable,maxWait:5000,timeout:10000});
}
