# Admin A05 — Supplier application and independent verification contract

A05 adds backend endpoints using the **existing** Supplier, SupplierMember, SupplierDocument, MediaAsset, User and AuditEvent models. It changes no Prisma schema or migrations.

## Stages

- Signed-in customer with verified, synchronized Clerk email submits `POST /api/v2/supplier-applications`. This creates PENDING Supplier and an **inactive** OWNER membership.
- Applicant may link an existing private MediaAsset they own, with verified SHA256, supported PDF/JPEG/PNG MIME and <=10 MiB. `POST /api/v2/supplier-applications/:id/documents` is **not an upload/storage endpoint**.
- OPERATIONS or OWNER admin can list/read suppliers, verify/reject documents and move PENDING -> UNDER_REVIEW -> APPROVED/REJECTED. APPROVED requires current VERIFIED BUSINESS_REGISTRATION plus VERIFIED GST_CERTIFICATE for regular/composition registrants, valid legal/contact/address data and supplier owner.
- Approved supplier's OWNER membership becomes active. Approved -> SUSPENDED blocks supplier access via existing database-authoritative checks.
- All decisions are auditable. Admin reviewer cannot be any member of the reviewed supplier, even if the admin role otherwise allows supplier review.

## API

`POST /api/v2/supplier-applications`, `GET /api/v2/me/supplier-applications`, `POST /api/v2/supplier-applications/{supplierId}/documents`, `GET /api/v2/admin/suppliers`, `GET /api/v2/admin/suppliers/{supplierId}`, `POST /api/v2/admin/suppliers/{supplierId}/documents/{documentId}/review`, `POST /api/v2/admin/suppliers/{supplierId}/review`.

## Restrictions and follow-up

- A05 cannot provision actual private media files; it only validates references to already-created MediaAsset rows. **Document preview/download is deliberately unavailable**, to avoid exposing raw object keys or public KYC URLs. A06 must display metadata-only evidence until a proper private, time-limited media reader is implemented.
- Rejection and verification reasons are in existing AuditEvent records; no new mutable reason field is created in Supplier.
- No guessing that GST status or legal identity is third-party verified: the decision represents an authorized human review, not government API validation.
- All API tests run only against disposable PostGIS CI; never apply any migration to staging or production for this feature.
