#!/usr/bin/env node
// A00: read-only OpenAPI contract check, independent of cwd and live databases.
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const source=fileURLToPath(new URL('../../../backend/v21/openapi.json',import.meta.url));
const contract=JSON.parse(readFileSync(source,'utf8'));

if (!contract.info?.version || !contract.paths || typeof contract.paths !== 'object') {
  throw new Error('Invalid V2.1 OpenAPI contract.');
}
const required=[
 ['get','/health'],
 ['get','/ready'],
 ['get','/api/v2/system'],
 ['get','/api/v2/me'],
 ['get','/api/v2/admin/access'],
 ['get','/api/v2/admin/catalog/listings/pending'],
 ['post','/api/v2/admin/catalog/listings/{listingId}/review'],
 ['post','/api/v2/admin/delivery/cities'],
 ['get','/api/v2/admin/promotions'],
 ['get','/api/v2/admin/support/cases'],
 ['get','/api/v2/admin/returns'],
 ['get','/api/v2/admin/finance/refunds'],
 ['get','/api/v2/admin/finance/payouts'],
];
const missing=required.filter(([method,path])=>!contract.paths[path]?.[method]);
if (missing.length) {
  throw new Error('Required V2.1 route missing: '+missing.map(([method,path])=>method.toUpperCase()+' '+path).join(', '));
}
const admin=Object.keys(contract.paths).filter(path=>path.startsWith('/api/v2/admin/'));
const planned=[
 'team management', 'supplier verification', 'dashboard metrics',
 'global read-only orders', 'permission-scoped audit reports'
];
console.log('PASS: BuildTo V2.1 OpenAPI '+contract.info.version+
  ' includes '+Object.keys(contract.paths).length+' paths and '+admin.length+' admin paths.');
console.log('Planned administrative additions (see A00 matrix): '+planned.join(', ')+'.');
console.log('PASS: contract audit is read-only; no Prisma/database changes.');
