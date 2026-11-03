# Buildto — Schema V2 (production-target architecture, **not production-certified**)

**Status:** a dedicated, standalone Prisma 5.22.0 target contract and SQL integrity kit. This is NOT a production migration and does NOT modify the current Neon database, the current `backend/prisma/schema.prisma`, or the customer/vendor/admin applications.

## Business model covered

India-focused, customer-to-supplier construction-material marketplace. Customer Flutter app: the 16-screen PDF is the immutable visual specification. Supplier app: onboarding, verified business, product listings/stock, quote handling, supplier-owned logistics. Admin web: approval, catalog moderation, payment/refund/settlement operations, delivery exceptions, support and audit. Backend controls all privileged decisions. No platform rider app.

* 69 Prisma models and 30 enums split across accounts, supplier organization/RBAC, identity consent, geography and construction sites, supplier catalogs and units, exact inventory, RFQ and tiered pricing, carts, reusable checkout quote, idempotent multi-supplier orders, supplier-owned shipments and delivery proofs, payment/refund/webhook/invoice/settlement/payout/ledger, returns and support, in-app notifications, outbox, audit and content.
* Exact money: **integer paise (`BigInt`)** for total amounts, and fixed-precision `Decimal` for prices and fractional quantities. No binary `Float` in financial fields. Default currency INR.
* No automatically approved new suppliers, products, bank accounts or service areas. No fake stock, ratings or reviews.
* Supplier authorization must check `SupplierMember`/`AdminMembership` on **every API request**. A valid FK alone does not provide authorization.
* Append-only audit and stock-movement rows, durable outbox, webhook uniqueness, order/idempotency keys, permissioned document storage references. API transactions with locks are mandatory for stock, payment, ledger and settlement transitions.

## Files

| File | Role |
| --- | --- |
| `prisma/schema.prisma` | **Target greenfield schema** (Prisma v5.22). Explicit relations/indexes and safe defaults. |
| `sql/integrity-guards.sql` | DB-level CHECK constraints, partial indexes, append-only, ledger and cross-supplier validation triggers, applied **after** generated Prisma SQL. |
| `sql/reference-seed.sql` | Repeatable reference-only (18 UOMs and 9 categories). **No** synthetic suppliers or live inventory. |
| `sql/schema-smoke-tests.sql` | Disposable-DB negative/positive integrity smoke tests; outer transaction rolls back. |
| `qa/check_model_links.py` | Fast local structural lint. Not a replacement for `prisma validate`. |
| `.github/workflows/buildto-schema-v2.yml` | PostgreSQL 16 CI job: `prisma validate` + schema generation + SQL guards + seed + smoke tests. |
| `MIGRATION-PLAN.md` | Legacy-to-v2 table mapping, rollout gates, backup/restore requirements. |
| `ACCEPTANCE-CHECKLIST.md` | Business/engineering/security release gates. |

## Validate with clean disposable PostgreSQL

The GitHub Action in this kit does the following without touching Neon:

1. Validate with the **repository's pinned Prisma 5.22**.
2. Generate SQL from the empty database to V2 (`prisma migrate diff --from-empty --to-schema-datamodel`).
3. Apply that SQL to PostgreSQL 16, followed by `integrity-guards.sql`.
4. Seed 9 categories and 18 unit types, test constraints including supplier isolation, rerun seed.

**Do not** pass the current Neon `DATABASE_URL` into this workflow. CI uses its ephemeral PostgreSQL service.

## Critical requirements not supplied by a schema alone

No database schema is automatically 100% production-ready. Before launch: verify GST invoice/country-law specifics with a qualified accountant/legal advisor; complete provider contracts; test refunds and double-entry posting under concurrency; implement secure APIs and RBAC; add observability, capacity tests, backup/restore exercises, database drift checks and actual mobile end-to-end tests.

## Configuration decisions requiring explicit product sign-off

* Whether cash-on-delivery and return policies are available for high-value bulk goods.
* Supplier marketplace fees/commission and when supplier payout becomes eligible.
* Inventory measured in sale units vs base units; conversion factors for local measures such as `BRASS` must be SKU/location-specific, never guessed.
* Whether one order can include split shipments, partial refunds, cancelled lines, and independently taxed delivery charges (the target supports these, but rules must be implemented and tested).
* Whether RFQ is part of v1 MVP or phase 2. Schema includes it so production can evolve without a risky retrofit.
* Payment provider, logistics partners, GST HSN classifications, personal data retention and company support contacts.

## Avoid old database hazards

Existing Buildto data has legacy `User.role=STUDENT`, `Vendor`, `MenuItem`, rider dispatch, restaurant-oriented delivery fees and monetary `Float`s. The historical `20261020_grocery_inventory` migration rejects `BAG`, `ROD`, `CUM` and other Buildto units if its SQL-only constraint is present; the historical baseline path may omit it. The old construction seeder marks synthetic sellers approved and overwrites prices/stock.

**Never run** the V2 generated greenfield SQL or SQL-only guards against the legacy DB. Follow the staged migration plan after an isolated Neon branch audit and restored backup test.
