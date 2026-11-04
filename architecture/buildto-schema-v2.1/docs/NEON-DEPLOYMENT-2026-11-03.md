# Buildto Neon V2.1 — Greenfield replacement receipt

**Applied:** 2026-11-03 (UTC date)  
**Source branch:** `architecture/buildto-schema-v2.1`  
**Source commit:** `8ae31b9b15e7460b93556c75b2913b837168bb16`  
**Neon project:** `Buildto` (`long-cake-87118137`)  
**Neon branch:** `production` (`br-sweet-cake-b5lw07mn`)  
**Database:** `neondb`, PostgreSQL 18.6

## Explicitly authorized reset

The Buildto user authorized deleting the legacy database records and replacing the current schema with Buildto V2.1.

Before replacement, we confirmed 33 legacy application tables, and created a no-compute point-in-time branch:
`backup/pre-buildto-v2.1-2026-11-03` (`br-summer-sound-b5iaqcb2`).

## Pre-production rehearsal

`validation/buildto-v2.1-pg18` (`br-misty-cherry-b5kwzgre`) was created from Buildto production.

On the validation branch:
- Dropped old public schema and applied generated greenfield PostgreSQL DDL.
- Installed the PostGIS extension, V2 integrity guards, and V2.1 hardening SQL.
- Applied reference-only seeding.
- Ran V2 and V2.1 SQL smoke tests in transactions with rolled-back test fixtures.
- All steps passed on Neon PostgreSQL 18.

## Production transaction

The following ran atomically via the Neon connector:
1. `DROP SCHEMA public CASCADE`, then recreate `public` for `neondb_owner`.
2. Install PostGIS.
3. Apply `architecture/buildto-schema-v2.1/sql/greenfield-ddl.sql`.
4. Apply `architecture/buildto-schema-v2.1/sql/integrity-guards.sql`.
5. Apply `architecture/buildto-schema-v2.1/sql/v2_1-hardening.sql`.
6. Apply `architecture/buildto-schema-v2.1/sql/reference-seed.sql`.

The transaction executed 465 SQL statements successfully.

## Read-only production verification

- 72 Prisma application tables and PostGIS's `spatial_ref_sys` table (73 public tables total)
- 35 application enum types
- PostGIS 3.6.4 installed
- 749 PostgreSQL constraints
- 209 indexes
- 51 information-schema trigger rows matching `buildto_%`
- 9 categories, 18 units of measure
- 0 suppliers, 0 customers, 0 listings, 0 purchase orders
- 0 legacy tables from `MenuItem`, `Vendor`, `DriverPartner`, `OrderGroup`, `Order`

## Mandatory next phase / cautions

**The database is deployed; the applications are NOT migrated.**

- `backend/prisma/schema.prisma` and backend migrations still describe legacy Kraveo/Grozo models.
- Do not run the existing backend migration scripts (`db:deploy` / `start:render`) against the new database.
- `_prisma_migrations` is not yet present. When the active Prisma schema is switched, establish a reviewed V2.1 baseline migration and resolve it correctly. Do not execute legacy migrations.
- Backend API, admin portal, supplier app and customer app must be migrated/tested before production use.
- Do not insert synthetic suppliers, customers, approvals, stock or transactions into the live production database as part of initial reference seeding.
- The backup and validation Neon branches can be removed after release engineering and recovery verification; do not remove them before then.

No database password, connection string, or other secret is documented here.
