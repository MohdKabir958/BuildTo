# BuildTo V2.1 — legacy removal inventory and safe deletion gates

## Verified state (4 Nov 2026)

The only live Render staging service (`buildto-v21-staging`) runs `cd backend && node v21/dist/server.js` from `backend/v21-16-release-security-integration`; it does not execute legacy `backend/src/index.ts`, legacy Dockerfile, or the old `render.yaml` Grozo blueprint. Staging Neon branch `backend/v21-staging` contains **72 V2.1 application tables**, three finished Prisma migrations, PostGIS and its normal `spatial_ref_sys` reference table, and no legacy Kraveo models. **Do not drop any database table or migration ledger** to clean source files.

### Keep — V2.1 application and critical data contract

- `backend/v21/src/`, `backend/v21/test/`, `backend/v21/scripts/release-preflight.cjs`, `backend/v21/openapi.json`.
- `backend/prisma/v21/schema.prisma`, **all three immutable** `backend/prisma/v21/migrations/**/migration.sql` files, `migration_lock.toml`.
- `backend/scripts/v21/` (schema parity, official Prisma baseline/target guards and model validation), `backend/test/v21SchemaContract.test.cjs`.
- `architecture/buildto-schema-v2.1/` canonical schema, full PostgreSQL DDL and reference seeds.
- `backend/package-lock.json` and the dependencies actually required by the new API until a full lockfile/dependency audit.

### Phase A — safe removal now

- Delete root `render.yaml`: it advertised a Grozo API with legacy migrations, outdated branch, paid disk and obsolete credentials. The live V2.1 Render service was created separately and does not use this blueprint.
- Delete `backend/Dockerfile`: it packaged `backend/src`, generated a default *legacy* Prisma client, ran the legacy migration job and started the legacy API; current Render uses a Node service with `npm run build:v21` and `node v21/dist/server.js`.
- Replace root `compose.yaml` (grocery `market_dev` PostgreSQL) with **disposable loopback-only PostGIS 16** `buildto_v21_test`. New volume intentionally leaves the old local volume untouched.
- Replace stale root readme and Prisma runbook to emphasize the sole approved V2.1 migration path.

### Phase B — legacy source deletion, after client cutover

These files are legacy but **not yet safe to delete from the repository** while existing clients/tests reference them:

| Legacy area | Files (tracked on main before cleanup) | Removal blocker |
|---|---:|---|
| `backend/src/` | 86 | `web/super_admin/src/services/api.ts` still calls `/api/v1/` and obsolete vendor, order, rider and grocery routes; old mobile apps also need V2.1 contract migration |
| `backend/test/` | 67 including **one active V2.1 contract test** | Retire old E2E/unit fixtures after replacing backend baseline CI; **preserve** `test/v21SchemaContract.test.cjs` |
| `backend/prisma/migrations/` | 23 | Old legacy CI and local QA scripts still use default Prisma schema and migration chain |
| `backend/prisma/schema.prisma` and `backend/prisma/baseline/` | legacy files | `npx prisma generate`, legacy test harness and old database scripts require the default client |
| `backend/scripts/` excluding `scripts/v21/` | 13 tracked | `package.json`, `scripts/qa/`, `.github/workflows/baseline.yml` and migration safety workflow reference old scripts |
| Old CI tasks | several workflows | V2.1 pipelines still intentionally run `npx prisma generate && npm run build` for legacy parity; removing those without replacing gates creates false-red CI |

**Required deletion gate:** migrate admin/mobile clients to `/api/v2` and Clerk; replace obsolete `backend/package.json` legacy `start/build/test/db:deploy` aliases with V2.1-only versions; update lockfile and import references; migrate QA scripts; delete or rewrite the obsolete legacy CI jobs; run the V2.1 PostGIS/Prisma parity, complete 158-case integration suite, financial preflight, client builds and live staging `/ready` smoke test. Only after those checks remove the legacy source/schema/migration files in a separate reviewed PR. Do not break the live Render branch as a side-effect of repo cleanup.

### Database rule

No database deletion is part of this source cleanup. `backend/v21-staging` has an immutable pre-migration backup at `backup/v21-staging-before-prisma-migration-2026-11-04`. The production branch is out of scope. Do not run `prisma migrate reset` or drop PostGIS, `_prisma_migrations`, V2.1 financial journals or history.
