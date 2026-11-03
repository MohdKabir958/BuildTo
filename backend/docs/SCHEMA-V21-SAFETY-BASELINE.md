# PR 00 — Buildto V2.1 backend safety baseline

**Scope:** prevent the inherited Kraveo/Grozo backend from damaging the deployed Buildto V2.1 database.

## Current deployment context

- Buildto Neon project `long-cake-87118137`.
- Production branch `br-sweet-cake-b5lw07mn`, database `neondb`.
- V2.1 is deployed as 72 application models and 35 enums. A reviewed V2.1 Prisma migration baseline is **not** yet recorded in `_prisma_migrations`.
- The active backend Prisma schema and `backend/prisma/migrations` still target legacy Kraveo tables (`Vendor`, `MenuItem`, `Order`).
- Staging Neon branch `backend/v21-staging` (`br-noisy-water-b5gc1kgz`) was created from production for upcoming backend work, with no compute initially. **Do not use production as a development database.**

## Fail-closed protection

`scripts/schema-contract.cjs` checks the real PostgreSQL catalog before legacy migration or runtime startup. Its check is intentionally conservative:

| Detected schema | Legacy migration | Legacy API startup |
| --- | --- | --- |
| Empty public schema | Allowed to bootstrap legacy schema | Blocked |
| Complete legacy signature **with `_prisma_migrations`** | Allowed | Allowed |
| Any V2.1 model marker | **Blocked** | **Blocked** |
| Mixed/partial/unknown schema | **Blocked** | **Blocked** |
| Metadata inspection error | **Blocked** | **Blocked** |

The shared guard is called before `scripts/migrate.mjs` executes any SQL and before `src/index.ts` binds its HTTP port or starts order maintenance. Hosted `start:render` inherits the migration guard.

### Limits

- This guard protects the checked-in entrypoints. It cannot protect a manually executed `npx prisma migrate deploy`, direct SQL or deployment of **old unpatched builds**. Revoke legacy write credentials and enforce deployment approval/branch protection separately.
- It does not switch the backend to V2.1; doing so is **PR 01**.
- It does not migrate or seed Neon; no live database writes are part of this PR.

## Reproducible checks

Run `npm ci`, then `npm run test:schema-contract` from `backend/`.

With a disposable PostgreSQL instance:
1. Create only `"Supplier"`. Run `npm run db:deploy`: must exit nonzero without creating any legacy tables.
2. Run `npm run db:contract:check`: must exit nonzero.
3. Remove the marker, then run `npm run db:deploy`: legacy bootstrap should work on an empty test database.
4. Run `npm run db:contract:check`: should accept a complete legacy schema.

The dedicated workflow `buildto-v21-safety.yml` exercises the above on PostgreSQL 16. The pre-existing broad baseline workflow may still fail for unrelated inherited terminology, lint or app tests.

## PR 01 prerequisites

- Promote the approved `architecture/buildto-schema-v2.1/prisma/schema.prisma` to the active schema in a carefully reviewed branch.
- Create a baseline migration including generated PostgreSQL DDL, PostGIS, integrity guards and V2.1 hardening. Match the deployed schema exactly.
- Reconcile against a disposable clone of Neon. Only then record a baseline as applied using the **approved** migration plan. Do not apply legacy history to V2.1.
- New backend modules must consume V2.1 DTOs, exact paise strings, Clerk membership RBAC and transactional workflows.

**Operational warning:** Existing deployed backend instances using legacy migration startup will fail on V2.1. This is intended until the new backend is ready; do not configure the old server to bypass this guard.
