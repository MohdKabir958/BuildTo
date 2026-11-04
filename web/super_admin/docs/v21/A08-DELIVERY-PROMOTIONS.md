# Admin A08 — Delivery area and promotion control

**Existing tables only:** City, ServiceArea and Promotion. No Prisma schema change, no migration, no external service.

Operations/OWNER can see **active and inactive** cities and service zones through newly added `GET /api/v2/admin/delivery/cities` and `GET /api/v2/admin/delivery/areas?cityId=UUID`. The public equivalents still expose active data only.

The portal reuses server-authoritative create/patch for cities, PIN-based zones and promotion configurations. New records are inactive; every activation requires a confirmation; in-use/invalid state responses are displayed as errors. Exact promotion amounts use **string paise**, percentages use integer BPS, promotion start/end local time converts to UTC ISO strings.

**Explicit limits:** radius-based geospatial zone geometry is supported by backend but is intentionally not exposed by the initial console form, which only accepts validated PIN lists. Supplier-specific delivery pricing belongs to supplier member roles, not admin impersonation. The current promotion list is capped at 100, so do not label it as exhaustive. No fake data, no unconditional activation.

Run V2.1 disposable PostGIS backend tests, TypeScript build, Vitest and OpenAPI contract checks before merge.
