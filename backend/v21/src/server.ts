import http from 'node:http';
import {readConfig} from './config';
import {createV21App} from './app';
import {createClerkIdentityVerifier} from './identity';
import {SingleInstanceRateLimiter} from './rateLimit';
import {RazorpayGateway} from './payment-gateway';
import {recoverExpiredPaymentSessions} from './payment-service';
import {recoverExpiredOrders} from './order-service';
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
  let recoveryTimer:ReturnType<typeof setInterval>|undefined;
  try {
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
    // One small per-instance recovery loop; no external queue or new service.
    // Provider-verified cancellation ALWAYS precedes reservation cleanup.
    let recovering=false;
    const recover=async()=>{
      if(recovering)return;
      recovering=true;
      try{
        if(paymentGateway)await recoverExpiredPaymentSessions(db,paymentGateway,10);
        await recoverExpiredOrders(db,10);
      }catch{
        jsonLogger({event:'v21_payment_recovery_failed',requestId:'recovery'});
      }finally{recovering=false;}
    };
    recoveryTimer=setInterval(()=>{void recover();},60_000);
    recoveryTimer.unref();
    void recover();

    let stopping=false;
    const shutdown=async()=>{
      if(stopping)return;
      stopping=true;
      if(recoveryTimer)clearInterval(recoveryTimer);
      const close=server?new Promise<void>(resolve=>server!.close(()=>resolve())):Promise.resolve();
      await Promise.race([close,new Promise<void>(resolve=>setTimeout(resolve,5000))]);
      await db.$disconnect();
      process.exit(0);
    };
    process.on('SIGINT',()=>{void shutdown();});
    process.on('SIGTERM',()=>{void shutdown();});
  }catch(error){
    jsonLogger({event:'v21_api_startup_failed',requestId:'startup'});
    if(recoveryTimer)clearInterval(recoveryTimer);
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
