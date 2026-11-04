# Buildto V2 — Production acceptance gate

## Database and migration
- [ ] Clean PostgreSQL 16 Prisma validation and SQL guards pass on GitHub Actions.
- [ ] Live Neon schema drift audited and restored on isolated branch; checksums verified.
- [ ] Backfill reconciliation reports match production reference counts, totals, snapshots and status history.
- [ ] Postgres CHECK, unique, FK, partial unique and cross-supplier triggers tested.
- [ ] No deletion of orders, payments, refunds or supplier settlements through cascades.
- [ ] `PENDING` is the default for new supplier verification; no unapproved listing visible.
- [ ] Explicit user and supplier roles authorization verified at API and SQL-query boundaries.

## Commerce safety
- [ ] Server quotes every order; client cannot select price, tax or available stock.
- [ ] Decimal quantity UOM conversion approved for bags, pieces, rods, bundles, kg, tonnes, cft, cum, sqm and regional units.
- [ ] Stock reservations are atomic with version/row locks and expiration recovery; no overselling under concurrency.
- [ ] Split supplier orders and shipments reconcile to one customer checkout.
- [ ] Returns and refunds never exceed eligible captured/fulfilled amounts; duplicates blocked under concurrency.
- [ ] Webhook verification and retries are idempotent; payment states cannot be forged by the client.
- [ ] Double-entry journal is balanced, sealed/immutable, and reconciled to settlements and bank/gateway statements.
- [ ] Order lifecycle is reconciled to the fixed 4-stage PDF customer UI; extended internal states do not change the visual design.
- [ ] GST invoices, HSN classifications, policy language and legal documents signed off by qualified advisors.

## Operations and security
- [ ] Live and synthetic datasets strictly separate; reference seeder cannot overwrite supplier prices or inventory.
- [ ] Admin/supplier/customer isolation IDOR tests pass; audit log includes actor and trace ID.
- [ ] Private document storage, encrypted credentials, access controls, retention and deletion procedures implemented.
- [ ] Dead-letter monitoring, outbox retry, slow-query alarms, payment/reconciliation alerts configured.
- [ ] Physical-device 16-screen visual snapshots match the user PDF; workflows tested end-to-end.
- [ ] CI baseline fully green; staging deploy, rollback plan and database recovery drill completed.

**Release decision:** This checklist requires human sign-off. Passing schema parsing alone is not production certification.


## V2.1 additional critical gates

- [ ] Product sign-off of OTP validity window, maximum attempts, offline site-supervisor exception/approval, and secure HMAC secret rotation; verify no plaintext OTP is logged or persisted.
- [ ] Cash accounting: actual supplier-held COD receipt, verified by authorized user, posted balanced journal, commission receivable, adjustments and payout-offset workflows; idempotent across retries.
- [ ] PostGIS installed on each Neon branch; verify index plans with representative geo workloads (no unconditional sub-millisecond promises), and test service-area polygon/radius semantics.
- [ ] Every API response containing BigInt or Decimal has explicit DTO serialization with paise represented as strings; mobile/web clients handle these types safely.
- [ ] Multi-truck dispatch concurrently allocates no more than ordered, and cancellation/return transitions release allocations without double release; use adverse concurrency tests.
- [ ] GST models and invoicing reviewed by an Indian GST professional, including composition dealers, intra/inter-state CGST+SGST/UTGST or IGST, tax point and supply type.
- [ ] Weight- and volume-sensitive freight tested against configured truck capacity and actual supplier tariffs; measure unit and load factors, never infer mass of unknown products.
- [ ] Mixed supplier child outcomes produce consistent parent order state, refunds and customer tracking; no sibling order is cancelled inadvertently.
- [ ] Full legacy-to-V2.1 migration rehearsal and backfill reconciled; all backups and restore rehearsals pass before cutover.
