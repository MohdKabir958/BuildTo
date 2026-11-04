# Buildto backend PR 05 — Locations, delivery coverage and practical freight

This is a small, production-minded increment. No new schema migrations, Kafka, Redis, microservices, maps SaaS, or background workers. PostgreSQL's existing PostGIS extension provides necessary geospatial checks.

## What works
- Admin `OPERATIONS`/`OWNER` can create inactive cities and PIN-code-defined delivery areas, then activate them after review. An area can be manually verified PIN-only or have a center + radius. Existing SQL also supports polygon areas if configured by a privileged operator; this PR does not expose arbitrary polygon editing.
- A supplier `OWNER`, `MANAGER` or `FULFILLMENT` member can opt into an active admin area, set its minimum order amount, and configure a **simple flat delivery fee** plus handling and an optional free-shipping threshold. All amounts are exact integer paise (JSON strings).
- A customer creates, lists, updates and soft-deletes their own delivery addresses with E.164 phone and validated Indian PIN codes. Only the signed-in owner can access those addresses. A transaction on the customer row serializes default-address changes, and PostgreSQL's existing partial unique index guarantees only one live default per account.
- Delivery eligibility preview accepts a customer-owned address ID and supplier ID only. PostgreSQL checks active city, approved supplier, active supplier-zone membership, matching PIN and (when configured) PostGIS containment or `ST_DWithin` radius. A rate must be active. Results never reveal another customer's address or private supplier data.
- Fees are previews, **not final checkout quotes**. The response includes standard flat + handling fee, minimum order amount and optional free-above threshold. Checkout PR 08 will compute order subtotal from authoritative DB listings and reconfirm all coverage, price and delivery restrictions before committing an order. We never accept client-supplied subtotals for free shipping.
- Existing dynamic `perKmPaise`, freight weight/volume and truck brackets are **not guessed**. Current preview intentionally refuses any unsupported active cargo/distance rule. Complex bulk loads should use an explicit RFQ or approved delivery quote once verified dimensions and routed distance are available.

## Scope constraints
- A manually approved PIN-only zone is a business-defined coverage area, not a claim that a ZIP/PIN implies a geometric radius. A radius/polygon rule requires valid coordinates **as well** as PIN.
- Customer-entered lat/lng are not independently geocoded in this PR. A positive preview is not authorization to dispatch; final address validation belongs to checkout and supplier confirmation. A mismatch between city/PIN/coordinates must be reviewed at the operational stage.
- Rate changes append a new rate record and deactivate previous active rates in one serializable DB transaction; old rates remain in history. No charge is collected during a preview.
- No supplier self-approval, driver application, freight routing engine, map-geocoding API, per-km estimation or inventory reservation. Keep the scope small rather than fabricating accuracy.

## Simplification implemented in this PR
- The inherited mandatory Redis rate limiter has been removed. A bounded in-process limiter applies to a **single deployed API process**. Public/user requests have a reasonable 300-per-minute per IP+method budget; provider webhooks use a separate 240-per-minute budget.
- Limiting is best-effort local abuse protection, not a distributed guarantee. Deployment must remain one API instance. If scaling to multiple instances is genuinely needed later, reassess rate-limiting storage.
- No Kafka or microservices were introduced. Existing PostgreSQL transaction rules and audit requirements remain.

## API routes
- Public: `GET /api/v2/delivery/cities`, `GET /api/v2/delivery/areas?cityId=<id>`
- Customer: `GET/POST /api/v2/me/addresses`, `PATCH/DELETE /api/v2/me/addresses/:addressId`
- Customer preview: `GET /api/v2/delivery/suppliers/:supplierId/eligibility?addressId=<id>`
- Admin: `POST /api/v2/admin/delivery/cities`, `PATCH /cities/:cityId`; `POST /areas`, `PATCH /areas/:areaId`
- Supplier: `GET /api/v2/suppliers/:supplierId/delivery`, `PUT /areas/:areaId`, `PUT /areas/:areaId/flat-rate`

## Release gates
The staging Prisma migration ledger (PR 01), live Clerk auth/webhooks and a delivery-policy acceptance test must still be completed before deployment. This PR remains stacked and draft. No Neon production writes or merges.
