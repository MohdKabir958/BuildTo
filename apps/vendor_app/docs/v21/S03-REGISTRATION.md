# Supplier S03 — registration, approval and private evidence review

**Design authority:** user-approved 16-page BuildTo customer PDF, translated into construction supplier forms (page 5 stepper), success/confirmation (page 6) and order-style status timelines (pages 7–10). Official BuildTo brand colors in branding/brand.json: navy #002B5B, amber #F59E0B.

## Implemented
- Four-step applicant registration: business name and unique slug, GST mode and GSTIN, verified Clerk email, optional E.164 phone, Indian billing address/PIN and review confirmation.
- The existing backend verifies contact against the active synchronized Clerk user and creates a **PENDING** supplier with **inactive** OWNER membership. Client cannot self-approve.
- Authenticated applicant list and private detail, reviewer feedback, evidence checklist, independent approval statuses and manual refresh.
- New read-only GET /api/v2/me/supplier-applications/{supplierId}: **only** a current applicant OWNER of that business may read the status of their own documents. Returns 404 for other accounts. Omits media IDs, storage keys, content hashes, internal review identity.
- Existing POST /api/v2/supplier-applications/{supplierId}/documents links **only previously provisioned** private, digest-verified assets owned by the same Clerk-synced user. The UI explicitly labels this as reference linking, **not** file upload.
- NoSupplier Clerk session opens the application wizard and reviews without acquiring active supplier business permissions; approved supplier users can reach their application history via More.
- Exact server-constrained GST/slug/phone/PIN validation and fail-closed unknown statuses. No automatic retry of uncertain registration POST; no fake approval or finance values.
- Professional BuildTo navy/amber cards, stepper, buttons, accessible states, pending/denied/approved timeline and mobile-width testing.

## Document upload limitation — not quietly bypassed
V2.1 currently has no secure raw KYC file-upload/read endpoint or connected private object store. The backend supports linking an existing account-owned MediaAsset (PDF/JPEG/PNG up to 10 MiB with digest) but **does not upload the bytes**. There is no public-bucket workaround. Self-service evidence upload remains **blocked pending a reviewed minimal private-media backend/storage integration**. Do not claim this PR ships fully self-service KYC or the UI uploads documents. Applicant document review notes are the actual notes returned by the service; application-level rejection reasons are not exposed by existing APIs.

## Live staging and security boundaries
- Native Clerk issuer/audience/authorized party validation and PostgreSQL membership checks remain mandatory; no token shortcuts.
- Render backend tracks a separate V2.1 staging release branch with auto deploy off. The new applicant-detail route added to main by S03 **will not be live on Render** until a separate controlled sync and redeploy; do not claim connected end-to-end staging UAT from mocked tests.
- No database schema migration, Redis/Kafka, rider service, production release, sample account/data or finance changes.
- S04 is not started until the user's explicit next-PR instruction.

## Verification
- Dedicated S03 GitHub workflow: locked Flutter packages, Dart formatting, V2.1 analyzer, UI/API tests, staging preview bundle.
- Backend: disposable PostGIS 16, V2.1 Prisma parity and validation, clean baseline, reference seed, strict TypeScript build and applicant RBAC integration test.
- Applicant RBAC assertions: signed-out 401, foreign application 404, pending application readable by its own inactive OWNER, real reviewer notes, and no private media keys/digests/IDs in response.
- UI testing: 320/360/393/412 logical pixels, large text and real-device sign-in/UAT when available. Low-resolution PDF alone does not prove pixel-perfect sign-off.

**Definition of done:** S03 code builds/tests and safely tracks applications. Fully self-service document upload and live Render E2E acceptance remain separately identified release blockers, not fake-completed features.
