# BuildTo V2.1 admin screen → endpoint inventory

The 119 V2.1 OpenAPI paths include read and write endpoints but **not all admin-wide listing/administration operations**. `/api/v2/admin/access` validates own membership only. A supplier-scoped route is not an admin-global view.

| Admin module | Current backend endpoints | Gap scheduled | Permission |
| --- | --- | --- | --- |
| Sign-in and current role | `GET /api/v2/me`, `GET /api/v2/admin/access` | none; account/role bootstrap runbook | ADMIN_READ |
| Team & access | only admin access introspection | A04: list, grant, role change, revoke `AdminMembership`; never by email/JWT claim alone | TEAM_MANAGE |
| Supplier applications | `GET /api/v2/suppliers/{supplierId}/access` is **supplier-only** | A05: application/create/list/detail, document status, approve/reject/suspend | SUPPLIER_APPROVE |
| Global categories/brands/products | `POST /api/v2/admin/catalog/categories`, `PATCH .../categories/{id}`, `POST .../brands`, `POST .../products`, `PATCH .../products/{id}`, unit conversion | A07: admin read inactive metadata if required | CATALOG_APPROVE |
| Listing review | `GET /api/v2/admin/catalog/listings/pending`, `POST /api/v2/admin/catalog/listings/{listingId}/review` | A07: safe read/history if required | CATALOG_APPROVE |
| Cities & coverage | `POST /api/v2/admin/delivery/cities`, `PATCH .../cities/{id}`, `POST .../areas`, `PATCH .../areas/{id}` | A08: inactive/admin listings as needed; public GET shows active only | SERVICE_AREA_MANAGE |
| Promotions | `GET/POST /api/v2/admin/promotions`, `PATCH .../promotions/{id}` | none | PROMOTION_MANAGE |
| Operations dashboard | current system health/capability endpoint, no operational KPIs | A09: bounded role-scoped aggregate queue counts | ADMIN_READ + scoped view checks |
| All marketplace orders | customer `GET /api/v2/orders` and supplier `GET /api/v2/suppliers/{id}/orders` have ownership constraints | A10: bounded global read/detail/shipment DTO; admin cannot impersonate | least-privileged admin read |
| Delivery exceptions | `POST /api/v2/admin/shipments/{shipmentId}/exception-approve` | A10: global shipment read/detail | SUPPORT_MANAGE |
| Customer support | `GET /api/v2/admin/support/cases`, `GET/PATCH .../cases/{caseId}`, `POST .../messages` | only bounded reference lookup if necessary | SUPPORT_MANAGE |
| Returns | `GET /api/v2/admin/returns`, `POST /api/v2/admin/returns/{returnId}/review` | none | SUPPORT_MANAGE |
| Review moderation | `GET /api/v2/admin/reviews`, `POST /api/v2/admin/reviews/{reviewId}/moderate` | none | SUPPORT_MANAGE |
| COD finance | `POST /api/v2/admin/finance/cod/{receiptId}/review` | A12: bounded pending COD queue | FINANCE_MANAGE |
| Settlements and ledger | `GET /api/v2/admin/finance/suppliers/{id}`, `POST .../settlements/drafts`, `POST .../approve`, `POST .../cancel`, `GET .../journals/{id}` | A12: readable settlement listing when needed | FINANCE_MANAGE |
| Refunds | `GET /api/v2/admin/finance/refunds`, request/approve/reconcile | none | FINANCE_MANAGE |
| Beneficiaries & payouts | register/approve, `GET .../payouts`, reconcile, bank-attest, reconciliation report | none; approval roles independent | FINANCE_MANAGE |
| Audit history | `AuditEvent` table already present | A14: paginated redacted admin read API | AUDIT_READ |

### Server-side data contracts

- Use actual DTOs and exact string paise/Decimal amounts. Never compute financial values from floats, and never present payment capture as bank reconciliation.
- Never expose full customer addresses/bank numbers, private support notes in customer DTOs, raw OTP codes or provider secrets.
- Explicit sorting and maximum page sizes; distinguish missing 404 from role 403. Return request IDs for support.
- Backend permissions come from persisted `AdminMembership` and `ADMIN_PERMISSIONS`; UI can hide actions but does not authorize them.
- No spec-only endpoint counts as implemented.
