#!/usr/bin/env node
// Explicit V2.1 database operations. No implicit connection to Neon production.
// This CLI is separate from the inherited Grozo migrator.
// Intentionally emits NO credentials and NO provider SQL errors.
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const require=createRequire(import.meta.url);
const { PrismaClient }=require('@prisma/client');
const {migrationName,verifyExistingSchema}=require('./schema-contract.cjs');

const root=fileURLToPath(new URL('../../',import.meta.url));
const cli=resolve(root,'node_modules/prisma/build/index.js');
const schema=resolve(root,'prisma/v21/schema.prisma');
const operation=process.argv[2]||'verify';
const stagingHostname='ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech';
const stagingBranch='br-noisy-water-b5gc1kgz';

function url() {
  const raw=process.env.MIGRATION_DATABASE_URL||process.env.DATABASE_URL;
  try {
    const result=new URL(raw||'');
    if(!['postgres:','postgresql:'].includes(result.protocol)||!result.hostname)
      throw new Error('Invalid URL');
    return result;
  }catch{throw new Error('DATABASE_URL_INVALID: provide a valid PostgreSQL connection string.');}
}
function approvedTarget(u,confirmation) {
  const local=(u.hostname==='localhost'||u.hostname==='127.0.0.1') &&
    process.env.NODE_ENV==='test' && u.pathname.endsWith('_test') &&
    confirmation==='ci-test';
  const staging=u.hostname===stagingHostname &&
    confirmation===('staging:'+stagingBranch);
  if(!local&&!staging)throw new Error('UNAPPROVED_DATABASE_TARGET: V2.1 writes are limited to approved disposable CI or Buildto staging.');
}
function runPrisma(args,u) {
  const r=spawnSync(process.execPath,[cli,...args,'--schema',schema],{
    cwd:root,env:{...process.env,DATABASE_URL:u.toString()},stdio:'inherit'
  });
  if(r.status!==0||r.error)throw new Error('V21_PRISMA_COMMAND_FAILED: see safe Prisma CLI status.');
}
const db=new PrismaClient({
  datasources:{db:{url:(process.env.MIGRATION_DATABASE_URL||process.env.DATABASE_URL)}}
});

try{
  if(!['verify','resolve-existing','deploy-empty','status'].includes(operation))
    throw new Error('USAGE: node scripts/v21/manage-baseline.mjs verify|resolve-existing|deploy-empty|status');
  const u=url();
  if(operation==='verify') {
    const result=await verifyExistingSchema(db);
    console.log('PASS: V2.1 PostgreSQL catalog verified.',JSON.stringify(result));
  }else if(operation==='status'){
    runPrisma(['migrate','status'],u);
  }else if(operation==='resolve-existing'){
    approvedTarget(u,process.env.BUILDTO_V21_BASELINE_CONFIRM);
    const result=await verifyExistingSchema(db,{baselineOnly:true});
    if(result.migrationHistoryExists)
      throw new Error('V21_ALREADY_HAS_MIGRATION_LEDGER: stop and inspect existing migration history.');
    // Official Prisma bookkeeping, NOT hand-writing _prisma_migrations rows.
    runPrisma(['migrate','resolve','--applied',migrationName],u);
    // Additional reviewed migrations are intentionally pending at this point.
    // Prisma `migrate status` exits nonzero until they are deployed, so verify
    // that the official resolve wrote one finished baseline entry instead.
    const rows=await db.$queryRawUnsafe(`SELECT migration_name, finished_at, rolled_back_at FROM \"_prisma_migrations\" WHERE migration_name = $1`,migrationName);
    if(rows.length!==1||!rows[0].finished_at||rows[0].rolled_back_at)
      throw new Error('V21_BASELINE_LEDGER_INVALID: official Prisma resolve did not finish.');
    console.log('PASS: existing V2.1 schema baselined through official Prisma resolve; deploy remaining reviewed migrations separately.');
  }else if(operation==='deploy-empty'){
    approvedTarget(u,process.env.BUILDTO_V21_BASELINE_CONFIRM);
    const rows=await db.$queryRawUnsafe(`SELECT tablename AS name FROM pg_catalog.pg_tables WHERE schemaname='public'`);
    if(rows.some(r=>r.name!=='spatial_ref_sys'))
      throw new Error('V21_DATABASE_NOT_EMPTY: refusing migration deploy; use resolve-existing after verification.');
    runPrisma(['migrate','deploy'],u);
    await verifyExistingSchema(db);
    console.log('PASS: V2.1 migration deployed to empty approved database.');
  }
}catch(e){
  const msg=e instanceof Error?e.message:'Unknown error';
  console.error(msg.startsWith('V21_')||msg.startsWith('UNAPPROVED_')||msg.startsWith('DATABASE_URL_')||msg.startsWith('USAGE:')
    ?msg:'V21_BASELINE_FAILED: stopped without reporting internal database credentials or SQL.');
  process.exitCode=1;
}finally{await db.$disconnect().catch(()=>{});}
