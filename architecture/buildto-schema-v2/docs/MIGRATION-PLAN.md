# Buildto Schema V2 — Existing Neon Migration & Cutover Plan

**No destructive change is authorized by this document.** Source of truth: current deployed Neon schema (`pg_catalog`, `_prisma_migrations`) inspected **read-only**. Never assume the GitHub schema equals the live database.

## 0. Freeze and assess

1. Snapshot current Neon branch, record PostgreSQL version, schema checksum, Prisma migration ledger, all custom constraints, indexes and triggers. Capture reference row counts and orphan checks for every major entity.
2. Back up Neon independently and run a **restore rehearsal** on a distinct branch. Confirm recovery objectives and database user privileges.
3. Compare fresh database created via `backend/scripts/migrate.mjs` with populated Neon; do not paper over migration checksums or mark migrations applied without the corresponding real SQL.
4. Lock deployment changes. Create a staging Neon branch from the latest source data, replacing all personal info with synthetic data if shared with vendors/testers.

## 1. Legacy-to-V2 mapping (no silent loss)

| Existing | V2 | Strategy |
| --- | --- | --- |
| `User` with `STUDENT`, `VENDOR`, `DRIVER`, `ADMIN` | `User`, `AdminMembership`, `SupplierMember`, `UserConsent` | Keep existing UUID identity; migrate verified users; roles become memberships. Archive role-only legacy data. |
| `Vendor` | `Supplier` + `SupplierMember` + `SupplierDocument` | Carry business ID where possible. Existing `APPROVED` requires verification; otherwise pending. Do not migrate sample phone/email as verified identities. |
| `MenuItem` | `Product` + `SupplierListing` + `UnitOfMeasure` + `SupplierPriceTier` | Separate canonical product from seller offering. Keep SKU/vendor mapping and unit basis. Backfill exact price using deterministic rounding, resolve stock unit mismatch. |
| `Category`, `VendorCategory` | `Category` parent tree + listing/category association through Product | Migrate 9 known category slugs. No old restaurant flags. Preserve external display mapping. |
| `InventoryReservation`, `StockMovement` | `InventoryBalance`, `InventoryReservation`, `StockMovement` | Reconcile stock movement sum with stored on-hand and held reservations; no negative stock. Introduce warehouse with supplier ownership. |
| `City`, `DeliveryZone`, `VendorCoverage`, `Address` | `City`, `ServiceArea`, `SupplierServiceArea`, `Address`, `ConstructionSite` | Migrate real city/PIN address only. Recalculate rather than assume old radius is valid. Preserve immutable address snapshots. |
| `OrderGroup`, `Order`, `OrderItem` | `PurchaseOrder`, `SupplierOrder`, `SupplierOrderItem` | Group by customer checkout, supplier-specific fulfilment. Preserve historic amount, tax, identity and status; map via explicit legacy-ID crosswalk. |
| `DriverPartner`, `DispatchOffer`, `DriverLocation` | `Shipment`, `ShipmentItem`, `ShipmentEvent`, `DeliveryProof` | No generic driver import; preserve historic proofs and references in an archive, migrate legitimate supplier-assigned shipment data only. |
| `Payment` + order refund fields | `PaymentAttempt`, `ProviderWebhookEvent`, `RefundRequest` | Keep immutable provider references. Reconcile amount to provider, never infer PAID from UI. |
| `PayoutAccount`, `Settlement`, `SettlementAdjustment`, `RiderPayout` | `SupplierPayoutAccount`, `Settlement`, `SettlementLine`, `PayoutTransfer`, `Ledger*` | Reconcile gross, fees, refunds and adjustments. Re-encrypt sensitive tokens. No payouts during transition. |
| `SupportCase`, `SupportNote` | `SupportCase`, `SupportMessage`, `ReturnRequest`, `ReturnItem` | Retain historic tickets; tag supporting order and supplier case. |
| `DeviceToken`, `PushLog`, `NotificationIntent` | `DeviceRegistration`, `Notification`, `OutboxEvent` | Reconfirm token ownership. No raw token logs. |
| `AdminAuditLog` | `AuditEvent` | Preserve original source identifiers and timestamps; mark provenance, avoid invented actor IDs. |

## 2. Expand, then backfill

Create an **additive migration series within the real existing Prisma migration history**, not a second independent set of untracked tables in the live DB:

1. `V2_expand_01`: new domains (supplier org, UOM, product/listing, site, warehouse, transaction reference tables). No drops or renames.
2. `V2_expand_02`: RFQ, purchase orders and supplier orders, shipment and proof, exact-money finance, inbox, outbox and audit.
3. Backfill using **versioned idempotent scripts** with old-to-new ID mapping, counts, conflict logs, dry-run mode and per-batch transaction limits. Generate a reconciliation report after each batch.
4. Turn on constraints as `NOT VALID` where PostgreSQL allows, fix violations, then `VALIDATE CONSTRAINT` in safe windows. Review indexes and locks.
5. Use application feature flags to write V2 first on pilot users; compare results. Never dual-write independent money or stock transactions without a defined atomic source of truth and retry reconciliation.

## 3. Contract and clean-up only after proof

1. Update backend APIs, admin portal, supplier app and customer app to V2 contract.
2. Verify supplier ownership, stock under concurrency, quote expiry, cancellation and refund retries.
3. Reconcile every payment and settlement at provider and ledger level; freeze payouts during financial cutover.
4. Ensure no legacy reader/writer remains. Only then plan removal of obsolete `isVeg`, `hostelBlock`, rider dispatch, `price Float` and other legacy structures.
5. Contract migrations must have a separate approved PR and a revert strategy. Do **not** delete original transaction history; archive to restricted retention storage.

## 4. Acceptance gate (minimum)

* `prisma validate` + migration SQL review + `prisma migrate diff` drift check on cloned Neon.
* Fresh PostgreSQL install, upgraded cloned DB, and backfill reconciliation all green.
* No duplicate public order numbers, unpaid duplicate captures, duplicate refund or payout events.
* DB-level negative tests: mismatched supplier/listing/stock/shipment, negative/oversold stock, negative financial totals, immutable audit and ledger.
* At least one concurrent stock reservation and duplicate webhook test against actual PostgreSQL.
* Manual supplier -> customer -> admin E2E order delivery, full and partial cancellation and returns.
* Security review including IDOR tests, access audit, PII/doc privacy, no raw card/UPI secrets.
* Restore rehearsal verified with documented RTO/RPO.

## 5. Explicit non-goals until later approval

No automatic switch of `DATABASE_URL`, no schema replacement, no live seeding, no production migration, no app code refactor, no publishing secrets, and no deletion of current Grozo/Buildto tables.
