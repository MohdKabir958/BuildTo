# S05 — Supplier Material Catalog and Listing Management

## UI fidelity and product boundaries
BuildTo's approved 16-screen design adaptation: primary navy `#002B5B`, amber `#F59E0B` primary actions, Material cards, filter chips, status badges, quantity-price editor, mobile-first bottom navigation. Supplier **Catalog** replaces the S01 placeholder only inside an S02 verified supplier session. No restaurant/Grozo legacy APIs, shopping cart, imaginary product pictures or fabricated stock.

## Implemented within S05
- Real owner-scoped `GET /api/v2/suppliers/{supplierId}/listings` with status filters, SKU search, up to 100 latest listing rows, honest 100+ lower bound and refresh.
- Server-approved catalog masters: categories and units. Search/filter product master `GET /api/v2/catalog/products` (25/page, cursor pagination) with safe encoded query parameters; supplier **selects** a master product, cannot self-create or approve product taxonomy.
- Create a `DRAFT` supplier listing with a cryptographically generated, stable per-create-intent `Idempotency-Key`. No automatic replay of uncertain timed-out writes.
- Edit `DRAFT`, `REJECTED`, `APPROVED` listings using `expectedVersion` CAS. Immutable SKU, product and unit are identified and locked. Editing an approved listing causes it to become non-public until admin re-review; explicit confirmation in the UI.
- Create/replace up to 12 quantity discount tiers with strictly increasing minimum quantities, non-increasing prices, exact decimal strings and version precondition. Replacing approved tiers unpublishes the listing until the independent review; explicit confirmation.
- Submit a `DRAFT` or `REJECTED` listing for admin moderation with the latest version. `PENDING` is **not** `APPROVED`; suppliers cannot approve themselves.
- Price, quantity and MRP validation uses string/BigInt rather than IEEE-754 floats (4 decimal places for prices, 3 for quantities, integer paise for the API). Tax is stored as basis points; GST field is explicit.
- Read-only viewer/inventory/fulfillment/finance controls; catalog mutations are exposed only to OWNER, MANAGER and CATALOG roles, and every mutation is re-authorized by the backend.
- Clear 401/403 and 404 handling, no stale data on failure, 409 version conflict and unknown outcome handling, multi-supplier session separation and no durable business cache.

## UX acceptance
- Real BuildTo screens at 320/360/393/412 logical pixels with 1.5x text.
- Distinguishable empty, pending review, rejected, suspended, active, loading, error, locked and optimistic-conflict states. Buttons accessible by label.
- Dashboard/Home remains S04; Orders, Warehouse and More remain later PR scopes.
- No promise that `status=APPROVED` alone means visible to customers: also requires `active`, active product/category/unit and supplier approval.

## CI / release limits
- Dedicated S05 strict formatting, analyzer, all S01–S05 Flutter tests and staging bundle. Earlier supplier workflows remain active.
- V2.1 backend schema and routes unchanged; no migrations, new services, Redis, Kafka or S06 inventory changes.
- Requires real Android native Clerk, approved supplier account, backend staging sync and real-device visual acceptance for end-to-end UAT. No production publishing or live moderation UAT is claimed from mocked CI.
- **Manual conflict resolution**: 409 never discards user data silently and requires re-fetch before retry; unknown write outcome is not automatically repeated.
