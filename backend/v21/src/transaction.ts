import {Prisma,PrismaClient} from '../../generated/buildto-v21';

// Prisma P2034 is PostgreSQL's serialization failure or write conflict.
// Retry only the bounded database transaction, never an outbound API call.
// Domain callbacks in this codebase contain database writes and outbox inserts only.
export async function serializable<T>(
 db:PrismaClient,work:(tx:Prisma.TransactionClient)=>Promise<T>
):Promise<T> {
 for(let attempt=0;attempt<3;attempt++){
  try {
   return await db.$transaction(work,{
    isolationLevel:Prisma.TransactionIsolationLevel.Serializable,
    maxWait:5000,timeout:10000,
   });
  }catch(error){
   const code=(error as {code?:unknown})?.code;
   if(code!=='P2034'||attempt===2)throw error;
   // Short bounded backoff for transient conflicts. The caller's HTTP request
   // remains finite and all earlier transaction writes have rolled back.
   await new Promise(resolve=>setTimeout(resolve,5*(attempt+1)));
  }
 }
 throw new Error('UNREACHABLE_TRANSACTION_RETRY');
}
