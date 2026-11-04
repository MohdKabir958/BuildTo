# Admin A07 — Construction catalog control

This PR adds explicit CATALOG_APPROVE-only readers for inactive categories, brands and master products, using bounded `id` pagination, **without** touching Prisma schema or migrations.

React catalog workspace offers:
- Category and brand create/view; category activation/deactivation (backend protects active children/products).
- Master product creation, activation and HSN reference; a new product starts inactive.
- Product-specific unit conversion with a **decimal string**, never a floating number.
- Pending supplier-listing moderation with backend `expectedVersion` optimistic check and exact unit-price display.
- Error, conflict, loading and empty states; backend is authoritative for every action.

Important scope: no bulk import, product image storage, supplier impersonation, stock editing or arbitrary catalog deletion. The supplier must create and submit listings from its scoped API. The existing `GET /admin/catalog/listings/pending` is capped at 100 in V2.1, so the dashboard must not present its visible count as a global total. Audit is recorded by existing V2.1 catalog services.

Run: admin Vitest/build and V2.1 PostGIS HTTP tests, including new `admin-catalog-read.test.cjs`. No database migration.
