#!/usr/bin/env node
'use strict';
// Read-only. Never runs migrate deploy/resolve, seed, payment or bank API calls.
const {PrismaClient}=require('../../generated/buildto-v21');
const {readConfig}=require('../dist/config.js');
const {verifyExistingSchema}=require('../../scripts/v21/schema-contract.cjs');
const {assertV21ReleaseIntegrity,REVIEWED_V21_MIGRATIONS}
 =require('../dist/release-integrity.js');

async function main(){
 const config=readConfig(process.env);
 const db=new PrismaClient({datasources:{db:{url:config.databaseUrl}}});
 try{
  const catalog=await verifyExistingSchema(db);
  if(!catalog.migrationHistoryExists)
   throw new Error('V21_MIGRATION_LEDGER_REQUIRED');
  await assertV21ReleaseIntegrity(db);
  process.stdout.write('PASS: V2.1 read-only release preflight; '+
   REVIEWED_V21_MIGRATIONS.length+' approved migrations, exact PostGIS catalog and '+
   'balanced financial obligations. No funds moved.\n');
 }finally{await db.$disconnect();}
}
main().catch(error=>{
 const name=error instanceof Error&&/^V21_[A-Z_]+/.test(error.message)
  ?error.message.split(':')[0]:'V21_RELEASE_PREFLIGHT_FAILED';
 process.stderr.write(name+'; staging remains blocked.\n');
 process.exitCode=1;
});
