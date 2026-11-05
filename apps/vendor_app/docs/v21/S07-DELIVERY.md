# S07 — Supplier coverage, active delivery PIN areas and flat freight

The supplier More tab now uses the verified BuildTo V2.1 coverage API rather than restaurant delivery radius, driver tracking, or local estimates.

## Supported scope

- Read active admin-managed Indian cities and service areas using `GET /api/v2/delivery/cities` and `GET /api/v2/delivery/areas?cityId=...`. Suppliers cannot invent or approve cities or PIN codes.
- Read supplier-owned coverage using `GET /api/v2/suppliers/{supplierId}/delivery`. Display exact minimum order and rate paise, not illustrative numbers.
- OWNER / MANAGER / FULFILLMENT may `PUT .../areas/{areaId}` to enable/pause coverage or update minimum order.
- Only active service areas may `PUT .../areas/{areaId}/flat-rate` with exact base and handling paise, optional free-above threshold and consistent rate confirmation.
- Eligibility, actual fees, stock, freight limitations and tax remain server-verified during checkout. Unsupported per-kilometre and weight-based freight is never invented. A PUT network failure remains an uncertain state requiring refresh.
- No backend migration, new workflow service, rider application, or unverified map location.

## Acceptance

Supplier role/isolation, active-admin-area selection, exact INR-to-paise, empty/pending/error states, signed-in view, 320px phone and physical-device comparison to the supplied navy/amber PDF. Mocked CI is not production launch signoff.
