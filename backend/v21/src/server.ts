import http from 'node:http';
import {readConfig} from './config';
import {createV21App} from './app';
import {createClerkIdentityVerifier} from './identity';
import {SingleInstanceRateLimiter} from './rateLimit';
import {RazorpayGateway} from './payment-gateway';
import {RazorpayXPayoutEvidence} from './payout-gateway';
import {jsonLogger} from './logging';
import {assertV21ReleaseIntegrity,assertV21AllMigrationsApplied} from './release-integrity';

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
    // ONE-TIME STAGING OPERATIONS ONLY. Remove this block immediately after
    // successful migration verification; never run against a production branch.
    if(process.env.BUILDTO_V21_STAGING_MIGRATION_ONCE){
      const expected='staging:br-noisy-water-b5gc1kgz';
      if(config.environment!=='staging' ||
        process.env.BUILDTO_V21_STAGING_MIGRATION_ONCE!==expected ||
        process.env.BUILDTO_V21_BASELINE_CONFIRM!==expected ||
        new URL(config.databaseUrl).hostname!=='ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech')
        throw new Error('V21_STAGING_MIGRATION_TARGET_DENIED');
      const {spawnSync}=require('node:child_process') as typeof import('node:child_process');
      const path=require('node:path') as typeof import('node:path');
      const backendRoot=path.resolve(__dirname,'../..');
      const execute=(args:string[])=>{
        const result=spawnSync(process.execPath,args,{cwd:backendRoot,env:process.env,stdio:'inherit'});
        if(result.error || result.status!==0)
          throw new Error('V21_STAGING_MIGRATION_COMMAND_FAILED');
      };
      const ledger=await db.$queryRawUnsafe<Array<{present:boolean}>>(
        `SELECT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='_prisma_migrations') AS present`);
      if(!ledger[0]?.present){
        process.stdout.write('V21_STAGING_MIGRATION: official baseline resolve starting (verified existing schema).\\n');
        execute(['scripts/v21/manage-baseline.mjs','resolve-existing']);
      }
      process.stdout.write('V21_STAGING_MIGRATION: deploying only reviewed pending Prisma migrations.\\n');
      execute(['node_modules/prisma/build/index.js','migrate','deploy','--schema','prisma/v21/schema.prisma']);
      process.stdout.write('V21_STAGING_MIGRATION: migration CLI completed, verifying full contract.\\n');
    }
    const schema=await verifyExistingSchema(db);
    if(!schema.migrationHistoryExists)
      throw new Error('V21_MIGRATION_LEDGER_REQUIRED: complete staging Prisma baseline before API startup.');
    await assertV21ReleaseIntegrity(db);
    // One API instance by design. No additional Redis service or network hop.
    const limiter=new SingleInstanceRateLimiter();
    if(!config.clerkIssuer||!config.clerkSecretKey||!config.clerkAuthorizedParties.length||!config.clerkWebhookSecret)
      throw new Error('V21_CLERK_CONFIG_REQUIRED: verified authentication and signed webhook config required.');
    const identityVerifier=createClerkIdentityVerifier({
      issuer:config.clerkIssuer,secretKey:config.clerkSecretKey,
      jwtKey:config.clerkJwtKey||undefined,audience:config.clerkAudience||undefined,
      authorizedParties:config.clerkAuthorizedParties,
      allowNativeWithoutAzp:config.clerkAllowNativeWithoutAzp,
    });
    const paymentGateway=config.razorpayKeyId&&config.razorpayKeySecret?
      new RazorpayGateway(config.razorpayKeyId,config.razorpayKeySecret):undefined;
    const payoutEvidenceGateway=config.razorpayXKeyId&&config.razorpayXKeySecret?
      new RazorpayXPayoutEvidence(config.razorpayXKeyId,config.razorpayXKeySecret):undefined;
    const app=createV21App({db,limiter,log:jsonLogger,allowedOrigins:config.corsOrigins,
      proxyHops:config.proxyHops,identityVerifier,clerkWebhookSecret:config.clerkWebhookSecret,
      razorpayWebhookSecret:config.razorpayWebhookSecret??undefined,paymentGateway,
      payoutEvidenceGateway,
      readinessCheck:()=>assertV21AllMigrationsApplied(db),
      deliveryOtpSecret:config.deliveryOtpHmacSecret??undefined});
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
