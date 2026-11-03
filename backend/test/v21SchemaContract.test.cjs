'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {expectedCatalog,verifyExistingSchema,expectSetEqual,migrationName}=require('../scripts/v21/schema-contract.cjs');
const e=expectedCatalog();
test('V2.1 baseline includes every expected model, enum and geospatial index',()=>{
  assert.equal(e.tables.length,72);
  assert.equal(e.enums.length,35);
  assert(e.columns.length>400);
  assert(e.triggers.length>=15);
  assert(e.indexes.includes('address_geopoint_gist'));
  assert.equal(migrationName,'20261103_buildto_v21_initial');
});
test('missing V2.1 table or column fails verification',async()=>{
  const catalog=e;
  const db={$queryRawUnsafe:async (sql)=>{
    if(sql.includes('pg_catalog.pg_tables WHERE'))return catalog.tables.filter(x=>x!=='Shipment').map(name=>({name}));
    return [];
  }};
  await assert.rejects(verifyExistingSchema(db),/V21_SCHEMA_MISMATCH/);
});
test('drift checker rejects both missing and unexpected objects',()=>{
  assert.throws(()=>expectSetEqual(['User','Supplier','UNKNOWN'],['User','Supplier'],'test'),/V21_SCHEMA_MISMATCH/);
  assert.throws(()=>expectSetEqual(['User'],['User','Supplier'],'test'),/V21_SCHEMA_MISMATCH/);
});
test('schema catalog failures redact provider error bodies',async()=>{
  const db={$queryRawUnsafe:async()=>{throw new Error('postgresql://user:secret@private');}};
  await assert.rejects(verifyExistingSchema(db),e=>e.message.startsWith('V21_SCHEMA_INSPECTION_FAILED')&&!e.message.includes('secret'));
});
