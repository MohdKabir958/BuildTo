# BuildTo V2.1 backend

One modular Express/TypeScript API backed by Prisma 5.22, PostgreSQL 16/PostGIS and Clerk. This is **the active backend** for construction materials.

## What is implemented

Customer and supplier identity, roles, construction catalog, inventory/warehouses, serviceability, RFQs/promotions, cart and checkout, Razorpay test payments, COD/GST invoices, supplier shipments and OTP proof, returns/reviews, settlements, refunds/credit notes and controlled supplier payout reconciliation.

**Safeguards:** signed provider webhooks, explicit scopes, idempotency, transactional outbox, migration SHA256 validation, guarded accounting, redacted logs and staging-only startup. No Redis/Kafka/microservices. Automated money movement remains disabled.

## Build and test

```sh
cd backend
npm ci
npm run db:v21:parity
npm run db:v21:validate
npm run build:v21
npm run test:v21:api     # requires a disposable PostGIS DB with migrations and seeds
npm run release:v21:preflight
```

For a disposable local database, `docker compose up -d postgres` from repository root provides PostGIS 16. Use `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/buildto_v21_test`, `BUILDTO_V21_ENV=local`, `NODE_ENV=test`, and `BUILDTO_V21_BASELINE_CONFIRM=ci-test`. On an empty test database, run `npm run db:v21:deploy-empty` and import `architecture/buildto-schema-v2.1/sql/reference-seed.sql` before the integration suite. Never run these disposable DB commands against Neon.

## Staging deployment

[Render staging](https://buildto-v21-staging.onrender.com) uses `cd backend && npm ci && npm run db:v21:parity && npm run db:v21:validate && npm run build:v21`, then `cd backend && node v21/dist/server.js`. Runtime requires `BUILDTO_V21_ENV=staging`, the exact allowlisted Neon staging URL with TLS, explicit HTTPS frontend CORS and Clerk authorized origins, a valid Clerk issuer/secret and signed webhook secret. Only configure Razorpay TEST credentials.

- `GET /health` — liveness
- `GET /ready` — actual V2.1 Prisma/migration readiness
- `GET /api/v2/system` — intentionally reports `productionReady=false`
- `POST /api/v2/webhooks/clerk` — signed Clerk identity synchronization
- `v21/openapi.json` — API contract

## Old backend is not the V2.1 runtime

`backend/src/`, default `backend/prisma/schema.prisma`, old `backend/prisma/migrations/`, legacy scripts and test harness are inherited Grozo/Kraveo code. Do not execute their old migration or startup commands on V2.1. Existing admin/mobile clients still rely on legacy API contracts. See [cleanup plan](docs/LEGACY-CLEANUP-PLAN.md) for dependencies and ordered retirement.

The staging database baseline and two additive migrations have been applied and verified. Production launch still requires real client/provider UAT, financial policy signoff, dependency audit and approval. See `docs/PR16-RELEASE-SECURITY-READINESS.md` for remaining gates.
