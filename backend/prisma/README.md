# BuildTo V2.1 database — current migration source

**Active schema:** `prisma/v21/schema.prisma`

**Approved immutable migration history:**
1. `20261103_buildto_v21_initial`
2. `20261104_return_refund_credit_note_link`
3. `20261104_payout_beneficiary_reconciliation`

The old `prisma/schema.prisma`, `prisma/migrations/`, and `prisma/baseline/` belong to the inherited Grozo/Kraveo backend. They are **not** the BuildTo V2.1 schema. They remain temporarily because older web/mobile clients and regression jobs still reference the legacy API. Do not apply their migrations to a BuildTo/Neon V2.1 branch.

From `backend/`, using an **approved disposable local** PostGIS test database:

```sh
npm ci
npm run db:v21:parity
npm run db:v21:validate
npm run db:v21:generate
BUILDTO_V21_BASELINE_CONFIRM=ci-test NODE_ENV=test npm run db:v21:deploy-empty
npm run build:v21
npm run test:v21:api
npm run release:v21:preflight
```

`db:v21:deploy-empty` is only for an empty, explicitly authorized local `*_test` database. Staging's existing baseline was officially resolved and the two additive migrations deployed on **4 November 2026**, with a separate Neon staging backup. Production must remain untouched.

For the live staging branch, verify the three completed Prisma ledger entries, immutable SHA256 checksums, PostGIS catalog, financial integrity and `/ready` using the read-only preflight. Never run `prisma migrate reset`, `db:deploy` (legacy), or apply any migration from `prisma/migrations/` to the BuildTo V2.1 database.

See `v21/docs/PR16-RELEASE-SECURITY-READINESS.md` for release boundaries. The API remains a **staging candidate**, not production-approved.
