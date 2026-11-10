import {Prisma,PrismaClient} from '../../generated/buildto-v21';

// Prisma P2034 marks a serialization/write conflict. Raw SQL can surface
// PostgreSQL 40001 or 40P01 as P2010 with meta.code. Retry only these.
// Retry only the bounded database transaction, never an outbound API call.
// Domain callbacks in this codebase contain database writes and outbox inserts only.
export async function serializable<T>(
 db:PrismaClient,work:(tx:Prisma.TransactionClient)=>Promise<T>
):Promise<T> {
 for(let attempt=0;attempt<5;attempt++){
  try {
   return await db.$transaction(work,{
    isolationLevel:Prisma.TransactionIsolationLevel.Serializable,
    maxWait:5000,timeout:10000,
   });
  }catch(error){
   const failure=error as {code?:unknown;meta?:{code?:unknown}};
   const retryable=failure?.code==='P2034'||
     (failure?.code==='P2010'&&
      (failure.meta?.code==='40001'||failure.meta?.code==='40P01'));
   if(!retryable||attempt===4)throw error;
   // Bounded exponential backoff. Only DB work is replayed, not provider calls.
   await new Promise(resolve=>setTimeout(resolve,10*(2**attempt)));
  }
 }
 throw new Error('UNREACHABLE_TRANSACTION_RETRY');
}
