# Buildto V2.1 — PR 12: Customer Returns, Support and Moderated Reviews

## Scope and dependency

Stacked on implementation PR 11 (`backend/v21-11-fulfillment-shipments-otp`) in the existing modular Express/TypeScript/Prisma API. Reuses the V2.1 `ReturnRequest`, `ReturnItem`, `ReturnEvidence`, `SupportCase`, `SupportMessage` and `Review` models. No extra tables, migrations, Redis, Kafka, microservices, workers or new provider calls. **All operations remain staging-only review code, not production deployment.**

## Returns: verified goods claim, never payment evidence

- **Customer POST** `/api/v2/orders/:orderId/returns` requires Clerk identity, owner order, `Idempotency-Key`, body `{supplierOrderId,reason,items:[{orderItemId,quantity}],evidenceMediaIds?}`. Only quantities already delivered by a supplier (confirmed shipment line with `DELIVERED` state) may be claimed, using positive exact Decimal strings.
- The transaction locks the parent order before calculating aggregate open/nonrejected return claims for each line; a customer's concurrent requests cannot reserve more returned goods than the delivered, unclaimed amount. Rejected and customer-cancelled claims stop reserving quantity; received and approved claims continue reserving, so duplicate money/returns are not enabled. Foreign supplier order, foreign line, unsupported quantity, non-owner media IDs and tampered amounts fail closed.
- A matching idempotency key and payload replays the same request; a changed payload is rejected. Create writes immutable audit/outbox events inside the database transaction.
- **Customer GET** `/api/v2/orders/:orderId/returns` and **POST** `/api/v2/returns/:returnId/cancel` are owner-only. Only an unreviewed REQUESTED return may be cancelled.
- **Supplier GET** `/api/v2/suppliers/:supplierId/orders/:supplierOrderId/returns` is supplier-scoped; **POST** `/api/v2/suppliers/:supplierId/returns/:returnId/receive` requires `ORDERS_FULFILL` and prior independent approval. Receipt means *goods physically claimed received*, not quality inspection, refund, or restocking.
- **Admin GET** `/api/v2/admin/returns`, **POST** `/api/v2/admin/returns/:returnId/review` require `SUPPORT_MANAGE` and an independently staffed admin: active members of the seller cannot approve/reject their own seller's returns. `REVIEW` → UNDER_REVIEW; `APPROVE` → APPROVED; `REJECT` → REJECTED, with a mandatory audit note.
- DTOs include `financialStatus: NOT_REFUNDED`; **no refund request, transfer, credit note, ledger payout, stock increment, or automatic commission adjustment happens in this PR.** This prevents customer-visible false refund confirmation and financial reconciliation gaps. Refund gateway integration and tax adjustments require later PR work and finance signoff.

## Support: confidential, customer-scoped conversations

- `POST /api/v2/support/cases` requires idempotency key; optional order link is checked against owning customer. `GET /api/v2/support/cases`, `GET /api/v2/support/cases/:caseId` and `POST /api/v2/support/cases/:caseId/messages` are owner-only.
- Support messages cannot be marked `internal` by customers. A customer's read projection excludes all internal notes, not just their content; there is no exposure through list endpoints.
- `GET /api/v2/admin/support/cases`, `GET /api/v2/admin/support/cases/:caseId`, `POST /api/v2/admin/support/cases/:caseId/messages`, `PATCH /api/v2/admin/support/cases/:caseId` require `SUPPORT_MANAGE`. Internal notes are explicitly opt-in from the administrator, not copied to customer channels.
- State transitions are checked under a support-case row lock. RESOLVED requires a customer-visible explanation; customer replies can reopen resolved cases; CLOSED cases are terminal and cannot accept replies. Messages, state changes, audit and outbox are transactionally consistent.
- The case-assignee is the acting support administrator, not an arbitrary client-supplied staff ID. No email/SMS or background job is claimed.

## Reviews: fulfilled-purchase-only and independent publication

- `POST /api/v2/orders/:orderId/reviews` requires the owning customer and a delivered supplier child order. The supplier is taken from the persisted supplier order, **never** selected by the review author. Rating is an integer 1–5. The DB uniqueness constraint prevents multiple reviews of the same supplier order.
- Customer's `GET /api/v2/orders/:orderId/reviews` shows their review including moderation state. Supplier `GET /api/v2/suppliers/:supplierId/reviews/manage` is scoped by supplier membership; unapproved reviews are **never** shown to public catalog clients.
- Public `GET /api/v2/suppliers/:supplierId/reviews` exposes only PUBLISHED reviews for an active approved supplier and omits customer identifiers.
- Admin `GET /api/v2/admin/reviews` and `POST /api/v2/admin/reviews/:reviewId/moderate` require `SUPPORT_MANAGE`, forbid the approver from being an active member of that supplier, and enforce PENDING → PUBLISHED/REJECTED, PUBLISHED → HIDDEN and HIDDEN → PUBLISHED transitions. Moderation never rewrites the original customer rating/comment.

## Verification

Dedicated `.github/workflows/buildto-v21-customer-care.yml` uses a disposable PostgreSQL 16/PostGIS database, baseline parity and reference data, strict TypeScript compile, all existing V2.1 regressions plus new authenticated integration tests and independent legacy compile.

Coverage includes owner/supplier/admin privilege boundaries, missing idempotency keys, changed-key payload, foreign evidence media, exact Decimal validation, concurrent over-return denial, independent return approval, physically received not refunded, support cross-customer privacy, internal admin note exclusion, resolve/reopen/close, review uniqueness and delayed publication, supplier admin conflict, hiding published reviews, and regression of checkout/payment/COD/GST/OTP delivery behavior.

## Open release gates

- Refund/credit-note amount calculations, gateway refunds and reconciling a refund to an exact supplier order's tax/discount/delivery share are **not** in this PR. The business must approve return eligibility timelines, inspection/checklists, damaged/rejected shipment-line handling and pickup logistics.
- Restocking requires a separate inspected warehouse movement with inventory authorization; physical receipt is not assumed sellable.
- Review moderation policy, spam/profanity handling, legal retention, customer complaint SLA and staff privacy training require operational signoff.
- Earlier stacked PRs remain unmerged. Official V2.1 staging migration ledger, live Clerk/Razorpay sandbox tests, GST specialist signoff and full-repository baseline checks are still required before release.
