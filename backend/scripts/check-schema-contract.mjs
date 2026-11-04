#!/usr/bin/env node
// Read-only CLI: allows operators/CI to prove a legacy backend must not access V2.1.
import { PrismaClient } from '@prisma/client';
import contract from './schema-contract.cjs';

const operation = process.argv[2] || 'runtime';
if (!['migrate', 'runtime'].includes(operation)) {
  console.error('Usage: node scripts/check-schema-contract.mjs [runtime|migrate]');
  process.exitCode = 2;
} else {
  const prisma = new PrismaClient();
  try {
    const state = operation === 'migrate'
      ? await contract.assertLegacyMigrationContract(prisma)
      : await contract.assertLegacyRuntimeContract(prisma);
    console.log('SCHEMA CONTRACT OK: legacy ' + operation + ' on ' + state + ' schema.');
  } catch (error) {
    // Contract errors contain no SQL input or secrets; other errors are intentionally redacted.
    console.error(error instanceof contract.DatabaseContractError
      ? error.message
      : 'DATABASE_SCHEMA_INSPECTION_FAILED: database contract check failed.');
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}
