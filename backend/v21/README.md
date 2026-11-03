# Buildto V2.1 platform — PR 02 foundation

## Scope and deployment

This is a **separate, deliberately restricted Express API**, not the legacy Kraveo/Grozo API. It builds from `backend/v21/src` into `backend/v21/dist`, using the isolated `backend/generated/buildto-v21` Prisma client created in PR 01. No legacy route, migration, or rider worker is imported.

**Not yet production-ready.** The only public routes are `GET /health`, `GET /ready`, and `GET /api/v2/system`. OpenAPI describes those three routes. No customer, supplier, financial, or admin API is available before Clerk + database RBAC in PR 03.

## Enterprise safeguards

- `BUILDTO_V21_ENV` allows only `local` or `staging`. Production boot is prohibited; staging accepts only the approved Neon staging hostname, local only loopback.
- At startup, the PR 01 inspector checks tables, enum types, columns, indexes, constraints, PostGIS, triggers and the presence of the Prisma migration ledger. If the ledger is missing, **the HTTP port does not open**.
- Request IDs, request-body-free JSON logging, strict CORS origins, security headers, 64 KB JSON body limit and safe standardized errors.
- Decimal money values and paise are JSON decimal strings, never floats; all DTOs are explicitly allowlisted.
- Rate limiting is bounded and **in-process** for a single API instance, with a separate Clerk webhook budget. No Redis. Add shared limits only if deploying multiple API replicas.
- No private media uploads or Socket.IO rooms exist yet. These require authenticated storage and permissions first.

## Transactional infrastructure

- `executeIdempotently` creates the idempotency record, domain mutation and outbox record in one serializable PostgreSQL transaction. A transaction-scoped advisory lock serializes repeated request keys; duplicate calls replay a resource reference, and changed payloads return a conflict. Do not call external providers inside that transaction.
- `publishOutbox` saves domain events inside the domain transaction. `claimOutbox` uses `FOR UPDATE SKIP LOCKED`, leases and bounded claim sizes. `acknowledgeOutbox` and `rejectOutbox` compare claim attempt counters; stale workers cannot settle newer claims.
- Outbox semantics are **at-least-once**. External side-effect handlers must deduplicate using `eventKey`. A handler registry and worker dispatcher exist but there is **no autonomous background worker process** in this PR. Domain modules will register handlers in later PRs.
- No frontend or Android app has been migrated to this foundation.

## Commands

```bash
cd backend
npm ci
npm run db:v21:deploy-empty    # only on an authorized disposable local database
npm run build:v21
npm run test:v21:api
```

For a staging server, configure `BUILDTO_V21_ENV=staging`, the allowlisted staging `DATABASE_URL`, `BUILDTO_V21_CORS_ORIGINS` (HTTPS exact origin), then use `node v21/dist/server.js`.

### Staging migration history blocker

The Neon staging database has the correct V2.1 schema, but **official Prisma migration history is not yet recorded**. The documented `npm run db:v21:baseline:resolve` must be run with the approved direct staging connection. We will not hand-edit Prisma's internal tables. The API will refuse staging startup until the baseline history is present.

## Next PR

PR 03 will add Clerk authentication, identity sync, supplier and admin membership RBAC, tenant-scope enforcement and authorization tests before exposing private business endpoints.
