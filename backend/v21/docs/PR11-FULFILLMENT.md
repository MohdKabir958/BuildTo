# Buildto V2.1 — PR 11: Supplier fulfillment, shipments and verified handover

## Boundaries and deployment safety

Stacked on implementation PR 10 (`backend/v21-10-cod-gst-invoices`) and the existing modular V2.1 Express/TypeScript/Prisma service. Uses the existing Postgres shipment, shipment line, status-event and delivery-proof tables and pre-existing quantity/allocation triggers. **No migrations, new background services, Redis, Kafka or microservices; no production Neon writes or deployment.**

Only the supplier responsible for an order fulfills its own line items. Buildto has **no rider/driver app**. Delivery is performed by suppliers and their personnel.

## Protected workflow

1. `GET /api/v2/suppliers/:supplierId/orders` — supplier access to own order queue.
2. `POST /api/v2/suppliers/:supplierId/orders/:supplierOrderId/accept` — accept a pending order only after valid full warehouse stock commitment and one genuine online capture or explicitly selected COD. Never accept an unpaid online order.
3. `POST /api/v2/suppliers/:supplierId/orders/:supplierOrderId/reject` — reject a **strictly unpaid** pending child order, release its own HELD stock, create status/audit/outbox records. A paid or COD-selected child must not be unilaterally rejected or cancelled; finance adjustment/refund is required. Other suppliers' children remain independent.
4. `POST /api/v2/suppliers/:supplierId/orders/:supplierOrderId/shipments` with `Idempotency-Key` — allocate exact decimal quantities to a supplier-owned active warehouse and create a PLANNED shipment. All items must be owned by that supplier order and covered by previously committed stock in the chosen warehouse. Allocation is checked at the service layer and enforced again by PostgreSQL triggers. Exact duplicate request keys replay the original manifest.
5. `POST /api/v2/suppliers/:supplierId/shipments/:shipmentId/pack`, `/dispatch`, `/out-for-delivery` — controlled PLANNED → PACKED → DISPATCHED → OUT_FOR_DELIVERY transitions. The child order progresses to READY/DISPATCHED, audit/outbox and immutable events.
6. `GET /api/v2/orders/:orderId/shipments` — customer-only shipment tracking; no OTP, HMAC hash, lockout state or exception reason leaked. `GET /api/v2/suppliers/:supplierId/orders/:supplierOrderId/shipments` — supplier-scoped manifest.
7. `POST /api/v2/orders/:orderId/shipments/:shipmentId/otp` — the authenticated **owning customer** generates an unpredictable six-digit, five-minute, shipment-bound OTP. Only a keyed SHA-256 HMAC is stored; the raw OTP is returned to the owner once. A code cannot be reissued during its valid window and is never exposed in supplier/customer shipment-history APIs. `BUILDTO_V21_DELIVERY_OTP_HMAC_SECRET` must contain at least 32 UTF-8 bytes; when absent, OTP endpoints fail closed.
8. `POST /api/v2/suppliers/:supplierId/shipments/:shipmentId/handover` — an authorized supplier member supplies the customer-provided OTP. Constant-time digest compare, serializable parent-order lock, five-attempt maximum, 30-minute lockout and no repeat stock/delivery commit. Successful handover sets **all allocated lines on that shipment** delivered, writes a shipment event, and transitions its supplier order to PARTIALLY_DELIVERED or DELIVERED according to *all ordered quantities*. A second truck can finish the remaining quantity.
9. `POST /api/v2/admin/shipments/:shipmentId/exception-approve` — SUPPORT_MANAGE administrator can approve a fully justified exception **only when independent of the supplier**. Supplier personnel may complete a shipment without OTP **only after** this approval. Both exception and fulfillment are separately auditable.
10. Optional handover media ID is checked against an already-owned private MediaAsset. The service does not automatically upload a photo or grant public media access.

## Finance integration

- PR09 Razorpay capture remains **CAPTURED** in customer order views after supplier progress/partial delivery/full delivery; noncaptured online attempts are never dispatch evidence.
- PR10 selected COD allows fulfillment but is still **COD_DUE** until the supplier records cash and an independent finance verifier reviews the receipt; supplier self-recorded cash is not payment confirmation.
- PR10 tax invoice issuance uses existing immutable order/registration/tax snapshots; PR11 does not override GST determination or generate invoices automatically.
- Supplier child outcomes independently drive the parent order state under the existing Postgres trigger. They do **not** cancel other suppliers.
- Not all shipment quantities have been received merely because a driver clicked a button. The customer OTP or approved exception confirms shipment-level handover. Shipment-by-shipment partial deliveries work; *rejected items, mid-shipment partial acceptance and partial paid-order cancellations* remain future reconciliation/return/credit-note policies.

## Tests

Dedicated `.github/workflows/buildto-v21-fulfillment.yml` runs a disposable PostgreSQL 16/PostGIS database, schema parity/validation, initial baseline and catalog reference seed, strict TypeScript, entire HTTP/transaction suite, and independent legacy backend build.

New integration tests cover: unauthenticated, cross-customer and cross-supplier writes; finance/viewer RBAC; no fulfillment before payment/COD; exact Decimal line allocation, overship prevention, idempotent shipment creation; two-truck partial/full deliveries; COD only after full verified delivery; authorized customer OTP issuance; single-use and incorrect OTP counter/lockout; independently approved exception; no supplier self-approval; Razorpay capture remains paid after order completion; independent unpaid child rejection and reserved stock release.

## Outstanding release gates

- **No SMS sender or provider-based OTP delivery** is claimed: raw OTP is exposed only to the authenticated customer API response, who must share it with the supplier representative on handover.
- User app must not present an OTP to the supplier before physical verification, must not store it in analytics or logs, and should require the recipient to inspect goods before sharing.
- Real end-to-end field testing, fraud/exception operational policies and human approval logs are still needed; support staff should not casually approve exceptions.
- Partial shipment damage/rejection requires a separate discrepancy/return/credit note policy before open fulfillment. COD collection per supplier order, not a partial truck, is a deliberate safety policy.
- Refunds, accepted paid-order cancellation and financial settlement reconciliation remain later PRs, not prematurely granted permissions. Staging migration ledger, live Clerk/Razorpay sandbox, tax signoff and broader repository baseline CI are still release blockers.
