# Buildto PR 01 — Neon V2.1 staging verification

**Date:** 2026-11-03. **Operation:** read-only catalog verification, not a schema migration.

## Database target
- Neon project: Buildto (`long-cake-87118137`)
- Branch: `backend/v21-staging` (`br-noisy-water-b5gc1kgz`), NOT production.
- Database: `neondb`, PostgreSQL 18.
- Staging compute: `ep-sparkling-sun-b5imzmjj` (unpooled connection).
- Source: `backend/prisma/v21/migrations/20261103_buildto_v21_initial/migration.sql`.

## Read-only comparison against the committed baseline

| Object | From migration | On staging | Missing | Unexpected |
| --- | ---: | ---: | ---: | ---: |
| Application tables | 72 | 72 | 0 | 0 |
| Enum types | 35 | 35 | 0 | 0 |
| Columns on application tables | 683 | 683 | 0 | 0 |
| Buildto triggers | 30 | 30 | 0 | 0 |
| Explicit indexes from baseline | 135 | 209 total incl. PK/unique-backed | 0 | Other 74 from constraints |
| Named `ADD CONSTRAINT` guards/FKs | 161 | 749 total incl. PK/unique/FKs | 0 | Other 588 |

The PostGIS extension is present. Staging has 9 reference material categories.
**The `_prisma_migrations` table is not yet present on staging.**

This demonstrates the expected object names/columns exist; it does NOT, by itself,
prove equivalence of every type, expression or function body. CI separately passed
a clean install of the exact migration file and the negative SQL smoke suite on
PostGIS PostgreSQL 16.

## Baseline bookkeeping is deliberately pending

The Neon connector can inspect/run SQL but cannot execute the official
`prisma migrate resolve --applied` command. We have **not** hand-written
Prisma's internal metadata tables or marked the migration as applied.
The reviewed `db:v21:baseline:resolve` CLI checks the same contract,
restricts the destination to the exact staging endpoint, and invokes Prisma's
official `migrate resolve` on the already-installed schema.

When approved staging credentials are available to the backend toolchain,
run the documented command in
`backend/docs/SCHEMA-V21-PRISMA-BASELINE.md`.
Verify `migrate status` afterwards.

No production database or application runtime was changed by PR 01.
