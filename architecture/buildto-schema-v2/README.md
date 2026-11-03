# Buildto Schema V2 Deliverables

This folder contains an isolated design and validation kit for the production-target Buildto marketplace database. It is **not applied** to any existing Neon database or source application's active Prisma schema.

Start with `docs/README.md`, then `docs/MIGRATION-PLAN.md`. The V2 Prisma contract is `prisma/schema.prisma`, custom PostgreSQL checks are in `sql/integrity-guards.sql`, and safe seed and DB smoke tests are in `sql/`.

To turn this into a real deployment, first pass the disposable PostgreSQL CI checks, then complete the branch-specific migration and data-reconciliation gates.
