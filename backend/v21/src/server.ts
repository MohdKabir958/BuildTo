import http from 'node:http';
import {readConfig} from './config';
import {createV21App} from './app';
import {RedisRestRateLimiter,InMemoryTestLimiter} from './rateLimit';
import {jsonLogger} from './logging';
import {PrismaClient} from '../../generated/buildto-v21';

// Shared baseline schema inspector (PR 01), which includes PostGIS, tables,
// columns and triggers. Relative path works from both src and compiled dist.
const {verifyExistingSchema}=require('../../scripts/v21/schema-contract.cjs') as {
  verifyExistingSchema:(db:PrismaClient)=>Promise<{migrationHistoryExists:boolean}>
};
async function main() {
  const config=readConfig(process.env);
  const db=new PrismaClient({datasources:{db:{url:config.databaseUrl}}});
  let server:http.Server|undefined;
  try {
    const schema=await verifyExistingSchema(db);
    if(!schema.migrationHistoryExists)
      throw new Error('V21_MIGRATION_LEDGER_REQUIRED: complete staging Prisma baseline before API startup.');
    const limiter=config.redisRestUrl&&config.redisRestToken&&config.rateLimitHashKey
      ? new RedisRestRateLimiter(config.redisRestUrl,config.redisRestToken,config.rateLimitHashKey)
      : config.environment==='local' ? new InMemoryTestLimiter()
      : (()=>{throw new Error('V21_CENTRAL_RATE_LIMIT_REQUIRED');})();
    const app=createV21App({db,limiter,log:jsonLogger,allowedOrigins:config.corsOrigins,proxyHops:config.proxyHops});
    server=http.createServer(app);
    await new Promise<void>((resolve,reject)=>{
      server!.once('error',reject);
      server!.listen(config.port,'0.0.0.0',()=>{server!.off('error',reject);resolve();});
    });
    jsonLogger({event:'v21_api_started',requestId:'startup'});
    let stopping=false;
    const shutdown=async()=>{
      if(stopping)return;
      stopping=true;
      const close=server?new Promise<void>(resolve=>server!.close(()=>resolve())):Promise.resolve();
      await Promise.race([close,new Promise<void>(resolve=>setTimeout(resolve,5000))]);
      await db.$disconnect();
      process.exit(0);
    };
    process.on('SIGINT',()=>{void shutdown();});
    process.on('SIGTERM',()=>{void shutdown();});
  }catch(error){
    jsonLogger({event:'v21_api_startup_failed',requestId:'startup'});
    if(server)server.close();
    await db.$disconnect().catch(()=>undefined);
    // Avoid including Prisma/provider exception strings in logs.
    const message=error instanceof Error && /^V21_[A-Z_]+/.test(error.message)
      ? error.message : 'V21_STARTUP_FAILED: see secured deployment diagnostics.';
    process.stderr.write(message+'\n');
    process.exitCode=1;
  }
}
void main();
