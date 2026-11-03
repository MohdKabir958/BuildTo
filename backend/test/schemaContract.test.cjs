'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const guard = require('../scripts/schema-contract.cjs');

function prismaWith(tables) {
  return {
    $queryRawUnsafe: async sql => {
      assert.equal(sql, guard.INSPECTION_SQL);
      return tables.map(name => ({name}));
    },
  };
}

test('empty database may be bootstrapped by legacy migrator but must not run old backend', async () => {
  assert.equal(await guard.assertLegacyMigrationContract(prismaWith([])), 'empty');
  await assert.rejects(guard.assertLegacyRuntimeContract(prismaWith([])),
    e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
});

test('complete legacy contract is accepted for migration and runtime', async () => {
  const db = prismaWith(['User', 'Vendor', 'MenuItem', 'Order', '_prisma_migrations']);
  assert.equal(await guard.assertLegacyMigrationContract(db), 'legacy');
  assert.equal(await guard.assertLegacyRuntimeContract(db), 'legacy');
});

test('untracked legacy-looking tables are not trusted without Prisma migration history', async () => {
  const db = prismaWith(['Vendor', 'MenuItem', 'Order']);
  for (const operation of [guard.assertLegacyMigrationContract, guard.assertLegacyRuntimeContract]) {
    await assert.rejects(operation(db), e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
  }
});

test('the V2.1 Supplier table alone blocks legacy migration and runtime', async () => {
  const db = prismaWith(['Supplier', 'spatial_ref_sys']);
  for (const operation of [guard.assertLegacyMigrationContract, guard.assertLegacyRuntimeContract]) {
    await assert.rejects(operation(db), e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
  }
});

test('other V2.1 markers independently block legacy code', async () => {
  for (const table of guard.V21_SIGNATURE) {
    const db = prismaWith([table]);
    await assert.rejects(guard.assertLegacyMigrationContract(db),
      e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
  }
});

test('mixed legacy and V2.1 tables cannot be used by the legacy backend', async () => {
  const db = prismaWith(['Vendor', 'MenuItem', 'Order', 'PurchaseOrder']);
  assert.equal(await guard.inspectDatabaseContract(db), 'mixed');
  await assert.rejects(guard.assertLegacyMigrationContract(db),
    e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
});

test('partial legacy and foreign public schemas fail closed', async () => {
  for (const tables of [['Vendor'], ['User'], ['spatial_ref_sys'], ['_prisma_migrations']]) {
    await assert.rejects(guard.assertLegacyMigrationContract(prismaWith(tables)),
      e => e.code === 'DATABASE_SCHEMA_CONTRACT_MISMATCH');
  }
});

test('failed metadata queries fail closed without disclosing query errors', async () => {
  const db = {
    $queryRawUnsafe: async () => {throw new Error('a secret connection URL should never be logged');}
  };
  await assert.rejects(guard.assertLegacyRuntimeContract(db), e =>
    e.code === 'DATABASE_SCHEMA_INSPECTION_FAILED' && !e.message.includes('secret'));
});

test('malformed metadata responses never default to legacy', async () => {
  await assert.rejects(guard.assertLegacyMigrationContract({$queryRawUnsafe:async()=>[{noName:true}]}),
    e => e.code === 'DATABASE_SCHEMA_INSPECTION_FAILED');
  await assert.rejects(guard.assertLegacyRuntimeContract({$queryRawUnsafe:async()=>null}),
    e => e.code === 'DATABASE_SCHEMA_INSPECTION_FAILED');
});

test('guard operation values cannot disable schema checks', () => {
  assert.throws(() => guard.assertContract('v2.1', 'skip'),
    e => e.code === 'DATABASE_SCHEMA_GUARD_USAGE');
});
