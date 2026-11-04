'use strict';

// V2.1 read-only PostgreSQL schema verifier. Built from the ACTUAL reviewed
// migration SQL, not a loose table-count check or optional product descriptions.
const fs = require('node:fs');
const path = require('node:path');
const migrationName = '20261103_buildto_v21_initial';
const migrationPath = path.resolve(__dirname, '../../prisma/v21/migrations', migrationName, 'migration.sql');
const EXPECTED_MODELS = 72;
const EXPECTED_ENUMS = 35;
const REQUIRED_SPATIAL_INDEXES = [
  'service_area_geocenter_gist',
  'service_area_boundary_gist',
  'address_geopoint_gist'
];
const sql = fs.readFileSync(migrationPath,'utf8');
function all(pattern,text) {return [...text.matchAll(pattern)].map(m=>m[1]);}
function expectSetEqual(actual,expected,label) {
  const a = new Set(actual), e = new Set(expected);
  const missing = [...e].filter(x=>!a.has(x)), extra=[...a].filter(x=>!e.has(x));
  if(missing.length||extra.length)throw new Error('V21_SCHEMA_MISMATCH: '+label+' missing='+
    missing.slice(0,8).join(',')+' extra='+extra.slice(0,8).join(','));
}
function expectedCatalog() {
  const tables=all(/^CREATE TABLE "([^"]+)"\s*\(/gm,sql);
  const enums=all(/^CREATE TYPE "([^"]+)" AS ENUM\s*\(/gm,sql);
  const columns=[];
  for(const m of sql.matchAll(/^CREATE TABLE "([^"]+)"\s*\(([\s\S]*?)^\);/gm)) {
    for(const c of m[2].matchAll(/^\s+"([^"]+)"\s+/gm))columns.push(m[1]+'.'+c[1]);
  }
  const constraints = all(/^ALTER TABLE "[^"]+" ADD CONSTRAINT "([^"]+)"/gm,sql);
  const indexes = all(/^CREATE (?:UNIQUE )?INDEX "?([A-Za-z0-9_]+)"?\s+ON\s+/gm,sql);
  const triggers = all(/^CREATE TRIGGER "?([A-Za-z0-9_]+)"?\s+/gm,sql);
  if(tables.length!==EXPECTED_MODELS||enums.length!==EXPECTED_ENUMS
    ||columns.length<400||constraints.length<60||indexes.length<80||triggers.length<15)
    throw new Error('Invalid approved V2.1 baseline SQL contents.');
  for(const name of REQUIRED_SPATIAL_INDEXES)if(!indexes.includes(name))
    throw new Error('Missing critical spatial migration index '+name);
  return {tables,enums,columns,constraints,indexes,triggers};
}
const BASELINE=expectedCatalog();
const ADDITIONS={
 columns:['RefundRequest.returnRequestId','TaxInvoice.sourceInvoiceId','TaxInvoice.returnRequestId'],
 constraints:['RefundRequest_returnRequestId_fkey','TaxInvoice_sourceInvoiceId_fkey',
 'TaxInvoice_returnRequestId_fkey','refund_proof_required'],
 indexes:['RefundRequest_returnRequestId_key','TaxInvoice_returnRequestId_key',
 'TaxInvoice_sourceInvoiceId_idx'],
 triggers:['buildto_return_refund_guard','buildto_return_credit_note_guard']
};
const CATALOG={
 ...BASELINE,
 columns:BASELINE.columns.concat(ADDITIONS.columns),
 constraints:BASELINE.constraints.concat(ADDITIONS.constraints),
 indexes:BASELINE.indexes.concat(ADDITIONS.indexes),
 triggers:BASELINE.triggers.concat(ADDITIONS.triggers)
};

async function verifyExistingSchema(prisma) {
  const query=async sql => {
    try{return await prisma.$queryRawUnsafe(sql);}catch {
      throw new Error('V21_SCHEMA_INSPECTION_FAILED: read-only PostgreSQL metadata query failed.');
    }
  };
  const tables=(await query(`SELECT tablename AS name FROM pg_catalog.pg_tables WHERE schemaname='public'`))
    .map(x=>x.name).filter(x=>x!=='spatial_ref_sys'&&x!=='_prisma_migrations');
  expectSetEqual(tables,CATALOG.tables,'application tables');
  const enums=(await query(`SELECT t.typname AS name FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='public' AND t.typtype='e'`)).map(x=>x.name);
  expectSetEqual(enums,CATALOG.enums,'enum types');
  const cols=(await query(`SELECT table_name AS table, column_name AS col FROM information_schema.columns
    WHERE table_schema='public'`)).filter(x=>CATALOG.tables.includes(x.table)).map(x=>x.table+'.'+x.col);
  expectSetEqual(cols,CATALOG.columns,'table columns');
  const constraints=(await query(`SELECT conname AS name FROM pg_constraint WHERE connamespace='public'::regnamespace`)).map(x=>x.name);
  for(const name of CATALOG.constraints)if(!constraints.includes(name))
    throw new Error('V21_SCHEMA_MISMATCH: missing SQL constraint '+name);
  const indexes=(await query(`SELECT indexname AS name FROM pg_indexes WHERE schemaname='public'`)).map(x=>x.name);
  for(const name of CATALOG.indexes)if(!indexes.includes(name))
    throw new Error('V21_SCHEMA_MISMATCH: missing SQL index '+name);
  const triggers=(await query(`SELECT tg.tgname AS name FROM pg_trigger tg
    JOIN pg_class c ON c.oid=tg.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND NOT tg.tgisinternal AND tg.tgname LIKE 'buildto_%'`)).map(x=>x.name);
  expectSetEqual(triggers,CATALOG.triggers.filter(x=>x.startsWith('buildto_')),'Buildto triggers');
  const exts=(await query(`SELECT extname AS name FROM pg_extension WHERE extname='postgis'`)).map(x=>x.name);
  if(!exts.includes('postgis'))throw new Error('V21_SCHEMA_MISMATCH: PostGIS extension missing');
  const legacy=(await query(`SELECT tablename AS name FROM pg_tables WHERE schemaname='public'
    AND tablename IN ('MenuItem','Vendor','DriverPartner','OrderGroup','Order')`));
  if(legacy.length)throw new Error('V21_SCHEMA_MISMATCH: legacy Kraveo model tables detected');
  const ledger=(await query(`SELECT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='public'
    AND tablename='_prisma_migrations') AS present`));
  return {applicationTables:tables.length,enums:enums.length,columns:cols.length,
    guardConstraints:CATALOG.constraints.length,modelIndexes:CATALOG.indexes.length,
    triggers:triggers.length,postgis:true,migrationHistoryExists:ledger[0]?.present===true};
}
module.exports={migrationName,migrationPath,expectedCatalog,verifyExistingSchema,expectSetEqual};
