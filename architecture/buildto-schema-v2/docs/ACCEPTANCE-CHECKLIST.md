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
