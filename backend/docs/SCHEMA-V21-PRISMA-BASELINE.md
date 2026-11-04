# Buildto backend PR 01 — Isolated V2.1 Prisma client and baseline

## Scope and what stays unchanged
- Existing Neon production is V2.1. **No production SQL or Prisma migration ledger is altered by this PR.**
- Existing Express API, `backend/prisma/schema.prisma`, legacy migration runner and `@prisma/client` remain isolated for TypeScript compatibility. PR 00 prevents their use on the V2.1 database.
- V2.1 ORM contract is now available at `backend/prisma/v21/schema.prisma` with a **separate generated client** in `backend/generated/buildto-v21`.
- PR 02+ should import that generated client in new services. **Never import legacy `@prisma/client` for new V2.1 domain services.**
- Generated files must NOT be committed. Run `npm run db:v21:generate` after `npm ci`.

## Schema and migration integrity
- The 72-model/35-enum V2.1 schema is copied exactly from the architecture version except the isolated generator output.
- `backend/prisma/v21/migrations/20261103_buildto_v21_initial/migration.sql` is generated composition of the **exact** reviewed greenfield DDL + PostGIS extension + V2 SQL integrity guards + V2.1 hardening. All in one transaction.
- `npm run db:v21:parity` fails if any component or the V2.1 Prisma schema drifts from the pinned architecture source. Editing the initial migration after any environment has baselined it is forbidden.
- `npm run db:v21:verify` reads live pg_catalog metadata and verifies all 72 tables, all 35 enums, all expected columns, named constraints, indexes, triggers and PostGIS.
- Reference catalog seed is **not** bundled in the migration: seed only with the separately reviewed idempotent `architecture/buildto-schema-v2.1/sql/reference-seed.sql`.
- Future model changes must use **new** versioned V2.1 migrations. Never regenerate or overwrite this baseline once applied.

## Existing staging Neon schema
- Project: Buildto `long-cake-87118137`
- Staging branch: `backend/v21-staging` `br-noisy-water-b5gc1kgz`
- Dedicated staging endpoint: `ep-sparkling-sun-b5imzmjj.c-7.us-east-2.aws.neon.tech`
- Production branch: `br-sweet-cake-b5lw07mn` — **never baseline it without a separate production cutover approval and read-only audit**
- Staging was cloned **after** the approved V2.1 greenfield deployment, so its SQL tables already exist but `_prisma_migrations` did not.

### Approved staging baseline command
Use a **direct unpooled** staging connection string in the environment, not a URL in the command line and never commit it:

```bash
cd backend
npm ci
npm run db:v21:parity
npm run db:v21:validate
npm run db:v21:generate
export MIGRATION_DATABASE_URL="<STAGING_DIRECT_POSTGRESQL_URL>"
npm run db:v21:verify
BUILDTO_V21_BASELINE_CONFIRM=staging:br-noisy-water-b5gc1kgz npm run db:v21:baseline:resolve
npm run db:v21:status
```

The `baseline:resolve` script compares the existing schema to source-controlled DDL **before** executing official Prisma `migrate resolve --applied`, and refuses any non-staging/CI PostgreSQL hostname. It does **not** run CREATE TABLE on existing Neon.

### Fresh disposable test database
```bash
cd backend
NODE_ENV=test \
  DATABASE_URL=postgresql://postgres:postgres@localhost:5432/buildto_v21_test \
  BUILDTO_V21_BASELINE_CONFIRM=ci-test npm run db:v21:deploy-empty
```

The action refuses any nonempty application schema, and the baseline itself installs PostGIS before creating tables.

## CI and release criteria
- Dedicated PostGIS PostgreSQL 16 GitHub Actions job performs canonical parity, `prisma validate`, independent V2.1 client generation, initial SQL migration, schema catalog checks, source V2/V2.1 SQL smoke tests, and a separate **existing-schema resolve** rehearsal.
- Test migration state using `prisma migrate status` and an SQL check that the baseline is applied exactly once.
- No automatic deploy to Neon or API deployment in this PR.
- Existing general backend CI is still tied to Kraveo/Grozo and fails in unrelated checks: those apps are not considered V2.1-ready.
- Only after the V2.1 modules are ready will `backend/prisma/schema.prisma` and the default client be switched to V2.1. This staged transition avoids shipping a broken legacy build.
