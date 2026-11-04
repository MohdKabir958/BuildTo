# Buildto Schema V2.1 — independent validated target contract

This package extends Buildto V2 with supplier delivery OTPs, supplier-held COD accounting, PostGIS, lossless API JSON, shipment allocation protection, Indian GST decomposition, cargo-aware freight and partial supplier cancellations.

**Do not replace `backend/prisma/schema.prisma`, apply these SQL files to the live Neon database, or assume backend compatibility.** This is the greenfield target for migration engineering. GitHub CI creates a disposable PostGIS-enabled PostgreSQL 16 database and validates it there.

Read `docs/README.md` and `docs/V2.1-IMPLEMENTATION-CONTRACT.md`, then `docs/MIGRATION-PLAN.md` and `docs/ACCEPTANCE-CHECKLIST.md`.

Order of operations for a disposable empty database:
1. `CREATE EXTENSION postgis` (and `btree_gist` is installed by v2.1 guards).
2. `prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script`.
3. Run generated DDL, then `sql/integrity-guards.sql`, then `sql/v2_1-hardening.sql`.
4. Run `sql/reference-seed.sql`, `sql/schema-smoke-tests.sql`, `sql/v2_1-smoke-tests.sql` and repeat the seed.

For the current repo use `.github/workflows/buildto-schema-v2.1.yml` on branch `architecture/buildto-schema-v2.1`.
