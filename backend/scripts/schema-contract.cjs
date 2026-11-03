'use strict';

// PR 00: the active backend and its historical migrations are LEGACY ONLY.
// Buildto V2.1 is already installed on Neon; never run legacy code on those tables.
// This guard deliberately reads PostgreSQL metadata using a fixed query; it cannot change data.
const INSPECTION_SQL = "SELECT tablename AS name FROM pg_catalog.pg_tables WHERE schemaname = 'public'";
const LEGACY_SIGNATURE = Object.freeze(['Vendor', 'MenuItem', 'Order']);
const V21_SIGNATURE = Object.freeze(['Supplier', 'SupplierListing', 'PurchaseOrder', 'SupplierOrder', 'Shipment', 'OutboxEvent']);

class DatabaseContractError extends Error {
  constructor(code, detail) {
    super(code + ': ' + detail);
    this.name = 'DatabaseContractError';
    this.code = code;
  }
}

function classifyDatabaseTables(tables) {
  if (!Array.isArray(tables) || tables.some(name => typeof name !== 'string' || !name)) {
    throw new DatabaseContractError('DATABASE_SCHEMA_INSPECTION_FAILED', 'Unexpected PostgreSQL metadata response.');
  }
  const names = new Set(tables);
  const hasLegacy = LEGACY_SIGNATURE.some(name => names.has(name));
  const hasV21 = V21_SIGNATURE.some(name => names.has(name));

  // Any V2.1 marker wins: mixed/partial installations must not be operated by legacy code.
  if (hasV21) return hasLegacy ? 'mixed' : 'v2.1';
  if (LEGACY_SIGNATURE.every(name => names.has(name))) return 'legacy';
  if (names.size === 0) return 'empty';
  return 'unknown';
}

async function inspectDatabaseContract(prisma) {
  let rows;
  try {
    rows = await prisma.$queryRawUnsafe(INSPECTION_SQL);
  } catch {
    // Avoid echoing Prisma exception text: it may contain network details or credentials.
    throw new DatabaseContractError('DATABASE_SCHEMA_INSPECTION_FAILED', 'Could not inspect the public PostgreSQL schema.');
  }
  if (!Array.isArray(rows)) {
    throw new DatabaseContractError('DATABASE_SCHEMA_INSPECTION_FAILED', 'Invalid PostgreSQL schema metadata.');
  }
  return classifyDatabaseTables(rows.map(row => row?.name));
}

function assertContract(actual, operation) {
  if (!['migrate', 'runtime'].includes(operation)) {
    throw new DatabaseContractError('DATABASE_SCHEMA_GUARD_USAGE', 'Unsupported operation.');
  }
  const allowed = operation === 'migrate'
    ? actual === 'empty' || actual === 'legacy'
    : actual === 'legacy';
  if (!allowed) {
    throw new DatabaseContractError(
      'DATABASE_SCHEMA_CONTRACT_MISMATCH',
      'Refusing legacy backend ' + operation + ': detected ' + actual +
        ' database schema. Buildto V2.1 requires the V2.1 backend and migration baseline.'
    );
  }
  return actual;
}

async function assertLegacyMigrationContract(prisma) {
  return assertContract(await inspectDatabaseContract(prisma), 'migrate');
}

async function assertLegacyRuntimeContract(prisma) {
  return assertContract(await inspectDatabaseContract(prisma), 'runtime');
}

module.exports = {
  INSPECTION_SQL,
  LEGACY_SIGNATURE,
  V21_SIGNATURE,
  DatabaseContractError,
  classifyDatabaseTables,
  inspectDatabaseContract,
  assertContract,
  assertLegacyMigrationContract,
  assertLegacyRuntimeContract,
};
