#!/usr/bin/env node
// Verifies the generated V2.1 client without affecting the old @prisma/client.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require=createRequire(import.meta.url);
const root=fileURLToPath(new URL('../../',import.meta.url));
const generated=require(root+'generated/buildto-v21');
const models=generated.Prisma.dmmf.datamodel.models.map(x=>x.name);
if(models.length!==72||!models.includes('SupplierOrder')||!models.includes('CodCollection')||!models.includes('OutboxEvent'))
  throw new Error('V2.1 generated Prisma client model contract mismatch.');
const enums=Object.keys(generated.Prisma.dmmf.datamodel.enums||{});
if(enums.length!==35)throw new Error('V2.1 enum contract mismatch: '+enums.length);
console.log('PASS: isolated generated V2.1 client exposes 72 models and 35 enums.');
