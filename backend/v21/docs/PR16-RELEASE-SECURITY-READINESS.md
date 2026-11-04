# Buildto V2.1 — PR16: Release security, integrated verification and staging handoff

**Status:** Implementation review candidate, **not** approval to release to production. PR16 stacks on PR15 (`backend/v21-15-payouts-bank-reconciliation`) in a single modular Express/TypeScript/Prisma/Postgres API. All stacked PRs remain draft and unmerged until separately reviewed.

## What PR16 actually changes

1. **Migration history is now a complete, mandatory three-migration manifest.** Startup and real `/ready` verify the finished, non-rolled-back Prisma migration entries against local SHA256 of exactly these reviewed files:
   - `20261103_buildto_v21_initial` (immutable schema baseline)
   - `20261104_return_refund_credit_note_link`
   - `20261104_payout_beneficiary_reconciliation`

   Unknown, missing, duplicated, pending, rolled-back or checksum-drifted migrations fail closed. Simply finding `_prisma_migrations` is not enough. The existing startup PostGIS/constraint/index/trigger verifier remains mandatory. This performs **read-only** checks and makes no silent migration/resolve attempt.

2. **Financial state integrity preflight** scans for posted unbalanced ledger journals, PAID settlements without matching provider-processed payout, processed payouts lacking PAID settlement or clearing journal, processed refunds lacking their journal, malformed linked GST credit notes, and beneficiary accounts active without distinct finance validation. It exposes **only aggregate counts**, not bank details, customer IDs or private documents. Any inconsistency **blocks startup and explicit staging preflight**; it must be investigated instead of silently auto-repaired.

3. **Startup/readiness:** `server.ts` refuses to bind after either schema/migration or finance preflight failure. The actual server wires `/ready` to migration history verification on each readiness check; `/health` remains a lightweight liveness endpoint. No additional health-check background service, queue or cache is introduced.

4. **Staging boundaries:** Exact single approved Neon hostname, explicit TLS database URL (one `sslmode=require|verify-ca|verify-full`), rejection of globally disabled TLS verification, exact configured CORS and Clerk authorized origins only (no credentials, extra path/query, wildcard, fragment, trailing slash). The current server **does not accept `production` as an environment** and continues to prohibit live Razorpay or RazorpayX credentials in staging.

5. **Access-log privacy:** Log only known Express **route templates**; unmatched and early-rejected requests log `UNMATCHED`, never user-supplied raw URL path, private order/customer UUID, query string, Authorization bearer token, bank details, request body, provider response or SQL exception.

6. **Honest public release metadata:** `/api/v2/system` exposes `releaseStage=unreleased-staging-candidate`, `productionReady=false`, `automaticRefundExecution=false`, `automaticPayoutExecution=false`, `bankStatementAPIReconciled=false`, and `partialGstCreditSupported=false`. OpenAPI **0.16.0** retains the **119 original V2.1 paths** with exact capability/status flags.

No Redis, Kafka, microservices, cron jobs, unaudited payment POST endpoints, automatic refunds, automatic supplier payouts or production database writes were added.

## Reproducible disposable CI verification

The dedicated `.github/workflows/buildto-v21-release-gates.yml` runs a disposable PostGIS 16 database, verifies canonical schema parity and Prisma validation, applies the approved **three migrations** on an empty `*_test` database, seeds reference units/catalog, compiles the V2.1 TypeScript application, runs the entire real HTTP/Prisma suite (customer/admin/supplier identity, order/payment, COD/GST, shipment/OTP, returns/reviews, finance, refunds, payouts and release hardening), executes the **read-only release preflight after test data exists**, then separately compiles the legacy API.

Run locally **only with a disposable test database**:
```sh
cd backend
npm ci
npm run db:v21:parity
npm run db:v21:validate
# Never deploy-empty against an existing or production database.
BUILDTO_V21_ENV=local NODE_ENV=test BUILDTO_V21_BASELINE_CONFIRM=ci-test npm run db:v21:deploy-empty
npm run build:v21
npm run test:v21:api
npm run release:v21:preflight
npx prisma generate
npm run build
```
The above assumes `DATABASE_URL` points to the disposable local PostGIS `*_test` DB and reference catalog seed has been run. `release:v21:preflight` never writes to the database.

## Staging promotion — explicit human operations, not automated here

**Do not deploy until all prior draft PRs are reviewed and merged in order.** Before staging, obtain a restorable backup, validate the exact database branch, compare committed migration SHA256s and indexes against actual staging, approve the data migration plan and rehearse rollback. Do not run the `db:v21:deploy-empty` script on an existing staging/production branch, do not force `migrate resolve` if its contents differ, and do not replace baseline SQL after it was marked applied.

After an authorized **separate** staging migration:
1. Set explicit staging `DATABASE_URL` with `sslmode=require` or stronger; configure exact HTTPS CORS/Clerk parties, signed webhooks, strong OTP secret and **test** payment providers only.
2. Run `npm run release:v21:preflight` against that approved staging DB with a read-only DB role, verify the three migration entries and exact catalogs, and obtain a finance-reviewed exception-free audit.
3. Start **one** modular API instance; confirm `/ready` reports ready, `/health` is live, `/api/v2/system` still says **not production-ready**, and direct unknown URLs and unauthenticated finance requests fail closed.
4. Exercise end-to-end supplier/warehouse/order, customer checkout, signed Razorpay capture, COD independent collection, GST invoice, OTP or independent delivery exception, return, credit note, reserved refund, settlement, beneficiary verification, payout intent and GET-only provider status (using **sandbox fixtures**). Confirm all `PENDING` and manual-review states remain non-disbursing.
5. Review audit/outbox, replay/idempotency, webhook ordering, secret-free access logs, irreversible finance events and accounting totals; separately conduct load smoke and security assessment in staging.
6. Roll back **application routing/traffic** and investigate on any discrepancy. Do not blindly reverse applied ledger migrations, replay provider money movements or delete posted financial records. Restoration/reconciliation must be separately reviewed by an authorized DBA and finance owner.

## Explicit prerequisites before claiming production readiness

- Formal sequential review/merge of the full PR stack; staging deploy rehearsed and fresh CI all green at **exact release commit**.
- Named operator sign-off on Clerk tenant/role provisioning, admin maker-checker policy, seed data, Razorpay/RazorpayX merchant configuration, key isolation, webhook retries/alerts, bank beneficiary validation, dashboard-controlled money movement and independent bank reconciliation operations.
- GST/Indian tax advisor review of statutory invoices and full tax credit notes, and a policy/implementation for unsupported partial returns, freight allocation, COD commission collection and payout reversals if required for launch.
- Real staging UAT with realistic concurrency and traffic; database backup/restore proof, logs/alerting, incident response, error budget and dependency security audit. Existing single-instance in-memory limiter is **intentional**; do not scale to multiple API replicas without a shared-limit plan.
- Production environment, network, deploy credentials and live money execution **remain explicitly disabled**. Production cutover requires a separate approved decision and deployment configuration, not an automatic consequence of PR16 or a green unit test.

**Decision rule:** A green PR16 CI means implementation meets the tested candidate contracts on disposable Postgres, not that legal, provider or production operational risks are closed.
