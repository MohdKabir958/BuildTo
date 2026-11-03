# Buildto backend PR 04 — Construction catalog, supplier listings and price governance

This module extends the isolated V2.1 API. The active legacy backend, live production Neon schema, and migration history are **not modified**.

## Catalog ownership
- **Admin CATALOG/OWNER role** may create categories, brands and products, set product/category `active`, and define product unit conversions. Category parent is immutable after creation; deactivation is refused when active child categories or active products remain.
- Products belong to the global Buildto catalog and require an active category. New products default `active=false`, and only admins publish them.
- HSN is stored as an explicit digit string, and a bounded JSON specification object is accepted. Category-specific required specification fields are **not yet defined**. This must be finalized with stakeholder-approved policies before claiming full material-spec validation.
- Brands have no `active` column in Schema V2.1; public brands are limited to those referenced by active products and categories.
- Reference units and categories are available from the existing, idempotent V2.1 reference seed. No new migrations or dummy business data are introduced.

## Supplier listings
- Supplier managers/owners/catalog members can create and edit listings **only** where their exact `SupplierMember` is active and not revoked, and `Supplier` is approved and unsuspended.
- SKU/product/unit identity cannot be changed after creation. A single supplier can have multiple listings for a product but SKUs are unique per supplier.
- Listing quantities, INR unit prices and discount tiers are **exact decimal strings** (not floating point); MRP is a **paise decimal integer string**. Tax is whole basis points.
- New listings start `DRAFT` and hidden. Supplier must explicitly submit. Admin CATALOG/OWNER reviews a `PENDING` listing, approving or rejecting with optimistic version checks. Approved listings have `publishedAt` and become discoverable only while supplier, product, category and unit are active.
- Changing a published price/quantity hides the listing and moves it to `PENDING` for reapproval. This is a deliberate fail-closed marketplace policy. `SUSPENDED` and `ARCHIVED` cannot be edited via the supplier API.
- Quantity-tier replacement archives previously published tier periods (not deleting historical published prices), discards only unapproved staged tiers, and creates new staged tiers. The admin activates staged tiers on approval. Suppliers may revise their tiers while a listing is \`PENDING\`; each revision increments its version, so an administrator cannot accidentally approve a stale review. Tiers are ascending in minimum quantity and cannot rise in price as quantity increases.
- Listing `version` uses compare-and-swap for every supplier edit, tier replacement, submission and admin review; stale concurrent requests receive `409 LISTING_VERSION_CONFLICT`. The transaction also writes a restricted `AuditEvent` and an outbox intent.
- New listing creation requires an `Idempotency-Key` and uses the PR 02 transactional idempotency primitive; repeat requests return the original listing reference, while changed payloads conflict.

## API routes
Public:
- GET `/api/v2/catalog/categories`, `/brands`, `/units`
- GET `/api/v2/catalog/products?categoryId=&search=&cursor=`
- GET `/api/v2/catalog/listings?productId=<uuid>` (published/approved only, bounded to 100)

Admin (authenticated and DB-role checked):
- POST `/api/v2/admin/catalog/categories`, PATCH `/categories/:categoryId`
- POST `/api/v2/admin/catalog/brands`
- POST `/api/v2/admin/catalog/products`, PATCH `/products/:productId`
- POST `/api/v2/admin/catalog/products/:productId/conversions`
- GET `/api/v2/admin/catalog/listings/pending`, POST `/listings/:listingId/review`

Supplier (authenticated and supplier-scoped):
- GET/POST `/api/v2/suppliers/:supplierId/listings`
- PATCH `/api/v2/suppliers/:supplierId/listings/:listingId`
- POST `/api/v2/suppliers/:supplierId/listings/:listingId/submit`
- PUT `/api/v2/suppliers/:supplierId/listings/:listingId/price-tiers`

## Limits and next PR
- **No stock or availability promises:** warehouse stock, reservations and oversell prevention belong to inventory PR 06.
- Admin approval verifies that every current quantity tier stays below the new base price and satisfies the minimum-order quantity, even after repricing an approved listing. Otherwise it refuses publication until the supplier resubmits valid tiers.
- No freight or coverage promise: postcode/PostGIS serviceability and cargo freight come in PR 05.
- No supplier self-enrollment/approval flow: supplier onboarding and member provisioning remain separately audited work.
- No media upload, image hosting, checkout, payment, payout or tax-invoice API yet. All remain disabled.
- Public supplier listing responses exclude supplier private contact data, warehouse stock and admin audit details.
- The staging Prisma migration ledger and live Clerk staging configuration are still prerequisites to hosting this API. CI uses disposable PostgreSQL, not Neon production.

## CI

Dedicated `Buildto V2.1 catalog and pricing` GitHub Actions job runs migration validation, V2.1 reference seed, `build:v21`, all API/auth/catalog/transaction tests, and separate legacy build. No Neon writes, merges, or deployment.
