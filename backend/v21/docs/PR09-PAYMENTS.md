# Buildto V2.1 — PR 09: Razorpay Payment Lifecycle and Pre-payment Corrections

## Branch and boundary

Stacked on implementation PR 08 (`backend/v21-08-cart-checkout-orders`) in the existing Express/TypeScript/Prisma modular backend.
No new tables, migrations, Redis, Kafka, distributed cache, background worker or microservice. No merge or production Neon writes.

## Audit of the four reported defects

1. **Clerk contacts: confirmed.** The signed Clerk webhook persisted only a name. Now selects the declared primary verified email and phone, validates email/E.164 syntax, normalizes email, preserves contact values when an update omits contact collections, and respects terminal account tombstones. Position-zero selection is not correct when primary IDs point elsewhere. Invalid/unverified primary contacts are not trusted. No raw PII in audit/outbox.
2. **Two Clerk network checks per request: performance trade-off confirmed.** JWT verification (signature/issuer/authorized party/expiry) is still performed on every request. A per-process bounded positive cache of provider session+account state (maximum 1,000 entries and 15-second TTL) avoids two repeated network checks on hot sessions. All local DB identities and memberships are read per request. Provider bans/revocations may take up to 15 seconds to be noticed. Positive checks never survive process restarts. No Redis.
3. **Expired stock reservation reactivation: not a checkout bug as reported.** A new checkout creates a new PurchaseOrder and new SupplierOrderItem IDs; a repeated Idempotency-Key returns the original result. A cancelled/expired order is terminal. Reopening old `InventoryReservation` rows bypasses order and audit invariants; do not reactivate. New retry requires a fresh priced checkout and a fresh order. Old closed/expired holds remain immutable in history.
4. **Cancelled RFQ leaves SUBMITTED supplier quotes: confirmed lifecycle inconsistency.** Cancellation now rejects submitted quotes in the same serializable transaction as the RFQ update and audit/outbox. REJECTED is accurate for customer cancellation; WITHDRAWN falsely implies that a supplier withdrew.

## Payment endpoints (only with validated gateway configuration)

- `POST /api/v2/orders/:orderId/payments`: authenticated customer, required `Idempotency-Key`, body `{"paymentMethod":"UPI"|"CARD"|"NET_BANKING"}`. Exact server-authored paise; only a PLACED customer-owned order with live reservations can start. Creates a PaymentAttempt before provider HTTP calls. Provider order creation is outside the DB transaction. On success stores provider order ref and returns key ID (public), method, amount, status, and order reference; no secret keys.
- `GET /api/v2/orders/:orderId/payments`: only owner can view their attempts. No raw gateway payloads.
- `POST /api/v2/webhooks/razorpay`: original raw request bytes signed with HMAC-SHA256 and the configured webhook secret; constant-time signature compare. Deduplicate via `x-razorpay-event-id` + event digest. Respond 503 for an unmatched, valid event so the gateway retries after a provider order is linked. Unsupported/malformed events are recorded but do not update financial state.
- `GET /api/v2/orders/:orderId` now derives paymentStatus from actual PaymentAttempt state instead of hardcoded AWAITING_PAYMENT_INTEGRATION.

## Financial consistency rules

- `PaymentAttempt` records exact integer BigInt paise and a per-order unique key. A repeated key does NOT create another Razorpay order. A competing nonterminal attempt is rejected.
- Outbound payment creation is bounded by timeout and verified against response order ID, amount, INR, and our unique receipt. If response is unknown, the attempt remains CREATED and **is not retried blindly**. Operator/provider reconciliation is required.
- A signed `payment.authorized` can transition PENDING → AUTHORIZED but never means paid or dispatch-ready.
- A signed `payment.captured` or `order.paid` must contain a matching captured payment entity with an exact order reference, total, and INR. A stale `payment.authorized` or `payment.failed` cannot override CAPTURED.
- A successful capture atomically marks the attempt CAPTURED, commits HELD stock once through the existing stock movement helper, confirms the parent order, and writes audit + transactional outbox. Supplier child orders remain pending acceptance.
- If capture arrives after cancellation, another capture, or expired/unavailable stock, the money is recorded but the parent order is **not confirmed**; it remains on the review path. A finance-led refund/reallocation policy is required before this can be served to live customers. Never manufacture inventory to force fulfillment.
- A single failed Razorpay payment event is not proof its whole provider Order has irreversibly failed; it is recorded without releasing payment/stock locks. This conservative v2.1 policy prioritizes avoiding double-charge over automatic retry. Reconciliation and safe retry UX must be verified with provider sandbox.

## Limits and release gates

- Gateway endpoints are disabled unless `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and `RAZORPAY_WEBHOOK_SECRET` are all valid; staging refuses a live key. Enable **automatic capture** in the test gateway and subscribe to payment authorized/captured/failed and order paid webhooks.
- Gateway credentials stay server-side. No customer callback, screenshot or mobile success response is payment evidence.
- Payment refunds, supplier-collected COD, per-supplier payment allocations following partial cancellation, GST invoice issuance, reconciliation jobs, and settlements remain PR 10–13 gates. Do not expose COD as paid before its verification workflow.
- The checkout stock hold is 20 minutes. A payment starting near expiry is rejected. Late payments require manual review; verification of actual provider/provider-initiated refunds and operational hold reclamation is a release gate.
- Full provider sandbox tests, webhook delivery/replay, staging Prisma ledger, live Clerk authorization, migration parity and PR review remain mandatory. No production deployment.

## CI

Dedicated `.github/workflows/buildto-v21-payments.yml` runs fresh disposable PostgreSQL/PostGIS baseline, reference seeds, V2.1 TypeScript compile, all API + negative/security/transaction integration tests, and independent legacy build. No production DB credentials or live payment calls in CI.
