#!/usr/bin/env node
// Reproducibility gate: V2.1 migration and scoped generated client MUST correspond
// exactly to the approved source schema + SQL guards. No live database access.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const source = fileURLToPath(new URL('../../../architecture/buildto-schema-v2.1/', import.meta.url));
const norm = s => s.replace(/\r\n/g, '\n');
const read = rel => norm(readFileSync(resolve(root, rel), 'utf8'));
const canonical = norm(readFileSync(resolve(source, 'prisma/schema.prisma'), 'utf8'));
const active = read('prisma/v21/schema.prisma');
const generatorLine = '  output   = "../../generated/buildto-v21"\n';
if (!active.includes(generatorLine) || active.replace(generatorLine,'') !== canonical) {
  throw new Error('V2.1 backend Prisma schema drifted from approved architecture schema.');
}
const DDL = norm(readFileSync(resolve(source,'sql/greenfield-ddl.sql'),'utf8'));
const guards = norm(readFileSync(resolve(source,'sql/integrity-guards.sql'),'utf8'));
const hardening = norm(readFileSync(resolve(source,'sql/v2_1-hardening.sql'),'utf8'));
const strip = x=>x.replace(/^BEGIN;\s*\r?\n/m,'').replace(/^\s*COMMIT;\s*$/m,'').trim();
const migration = `-- Buildto V2.1 GREENFIELD baseline. Source: architecture/buildto-schema-v2.1/sql/*
-- Never run this migration against an already populated V2.1 branch.
-- Existing V2.1 databases must first pass the read-only contract check and be
-- marked applied with prisma migrate resolve (never recreate their tables).
-- The entire operation is transactional, including PostGIS, DDL and custom guards.
BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

-- Generated Prisma V2.1 DDL. No rewriting of names or money/geometry types.
${DDL.trim()}

-- SQL-only integrity guards (Prisma 5.22 cannot represent these in schema.prisma).
${strip(guards)}

-- PostGIS indexes, delivery/COD/GST/shipments hardening.
${strip(hardening)}

COMMIT;
`;
const applied = read('prisma/v21/migrations/20261103_buildto_v21_initial/migration.sql');
if (migration!==applied) throw new Error('V2.1 migration SQL differs from reviewed source contract.');
const models=[...canonical.matchAll(/^model\s+\w+\s*\{/gm)].length;
const enums=[...canonical.matchAll(/^enum\s+\w+\s*\{/gm)].length;
if(models!==73 || enums!==35)throw new Error('V2.1 model/enum count has unexpectedly changed.');
console.log('PASS: canonical V2.1 schema, immutable migration composition, 73 models, 35 enums.');
