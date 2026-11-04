# Buildto V2.1 — PR 08: Cart, Server-Priced Checkout and Multi-Supplier Orders

## Why one backend is enough
Buildto continues as **one modular Express/TypeScript backend and its existing PostgreSQL V2.1 schema**. No Redis, Kafka, microservices, separate worker or new database. This is a practical quality-oriented marketplace implementation, not a design for millions of customers.

## Customer workflow

1. Customer adds/removes up to 30 approved supplier listings. Each change supplies an exact quantity string and `expectedVersion` from the cart. Server validates listing approval, supplier approval, active product/category, minimum/step/maximum quantities. Stale updates return `409 CART_VERSION_CONFLICT`. No customer can edit another person's cart.
2. `POST /api/v2/checkouts` with `Idempotency-Key`, owned address, optional owned site, optional promotion code and current cart version. The backend loads the cart and **calculates all prices itself**. Quote expires after 10 minutes.
3. Checkout checks exact seller price tiers, active warehouse available stock (preview only), customer-owned address, active supplier coverage by PIN and PostGIS radius/polygon, per-supplier minimum order, active flat delivery rate and any free-above threshold. Complex weight/distance/bracket freight is **not guessed**; those orders require a separately approved RFQ/freight quote.
4. Checkout stores an immutable `CheckoutQuote` with the address snapshot, per-item price and listing version, per-supplier rates and minimums, coupon terms and calculated amounts, and a server-owned fingerprint. The customer cannot provide or override subtotals, taxes, discounts, delivery fees or total.
5. `POST /api/v2/checkouts/:quoteId/place` with `Idempotency-Key` and a unique `clientRequestId` rechecks all live catalog/address/delivery/prices/cart data. If any field differs, the request fails with a clear conflict. **No silent price increase.**
6. One serializable database transaction creates the parent `PurchaseOrder`, one `SupplierOrder` for each supplier, immutable `SupplierOrderItem` commercial snapshots, all required `InventoryReservation(HELD)` rows, promotion redemption if applicable, marks checkout quote CONSUMED, and clears/increments the cart. It commits **all supplier orders or none**. No stock is consumed before the later payment/COD acceptance workflow.
7. A reservation expires after 20 minutes if not confirmed. Customer may cancel a strictly pre-payment order. Cancellation releases all HELD reservations atomically, marks supplier orders CANCELLED and returns any unspent promotion usage. A bounded, opportunistic expiration recovery checks older unpaid orders before another placement; it requires no dedicated background worker.

### Payment and fulfillment safety
- Order status at PR 08 placement is **PLACED** and child supplier orders are **PENDING_ACCEPTANCE**, but the API explicitly exposes `paymentStatus: AWAITING_PAYMENT_INTEGRATION`. This is **not a paid or dispatch-authorized order**.
- PR 09 must integrate actual Razorpay payment attempts, webhooks, payment authorization/capture, and a locked payment-to-reservation confirmation protocol.
- PR 10 must integrate supplier-collected COD, detailed tax invoices and finance/commission records. PR 11 must prevent supplier dispatch unless payment/COD eligibility is confirmed and required reservations are committed.
- Before PR 09, any order with an active payment attempt is **not cancellable through this customer endpoint**. Recovery skips it to prevent a race with gateway settlement. No payment calls happen inside stock transactions.

## Pricing and exact money
- Unit prices and exact quantities are `Prisma.Decimal`; INR paise and financial aggregates use `BigInt` and JSON decimal strings. Server uses HALF_UP at line paise boundaries.
- Tax-inclusive and tax-exclusive listings are both supported. The taxable amount is calculated from the authoritative price; discount is allocated across eligible taxable goods by deterministic largest-remainder proportions; GST is recalculated on discounted taxable goods.
- **Shipping promotions apply to freight, not taxable product prices.** The trusted checkout quote stores the original delivery fee. `FREE_DELIVERY` writes zero net delivery and zero merchandise discount; the promotion redemption records the original saved fee. Fixed/percentage promotions discount merchandise only.
- Checkout requires verified REGULAR GST registration for taxable supplier lines. GST is split into CGST+SGST, CGST+UTGST or IGST using the supplier's GSTIN state code and destination state. Unverified/unsupported taxable configurations fail closed; PR 10 retains responsibility for full tax-invoice issuance and exceptions.

## Customer routes
- `GET /api/v2/cart`
- `PUT /api/v2/cart/lines/:listingId` (exact quantity and `expectedVersion`)
- `DELETE /api/v2/cart/lines/:listingId` (JSON body `expectedVersion`)
- `POST /api/v2/cart/clear` (JSON body `expectedVersion`)
- `POST /api/v2/checkouts` (required `Idempotency-Key`)
- `GET /api/v2/checkouts/:quoteId`
- `POST /api/v2/checkouts/:quoteId/place` (required `Idempotency-Key`)
- `GET /api/v2/orders`, `GET /api/v2/orders/:orderId`
- `POST /api/v2/orders/:orderId/cancel`

All routes require Clerk verification and read/write **only the current customer's records**. Supplier/Admin finance/fulfillment APIs are not exposed here.

## Release limitations
- No payment charge, order confirmation, COD collection, shipment, payout or tax invoice is performed in PR 08. **Do not deploy these provisional orders to customers** until the later payment/COD and fulfillment gates are complete.
- Accepted RFQ quotes with bespoke lines are not yet converted to a payable checkout. They need a dedicated `sourceQuoteId` conversion path that also validates applicable delivery, GST and stock/fulfillment terms; never silently replace the accepted quote's price with a normal catalog listing.
- Delivery coordinates remain customer-entered, not independently geocoded; warehouse and supplier confirmation are required before physical dispatch.
- Reservation expiry is reclaimed opportunistically as traffic occurs; there is no guarantee that an expired hold is reclaimed at the exact expiry instant during idle time. PR 09 should integrate recovery with its payment finalization and scheduling where operationally necessary.
- Staging still requires the official V2.1 Prisma baseline history and live Clerk integration verification; earlier PRs remain stacked drafts. No production Neon queries/writes, schema migrations, merges or deployments occurred.

## Test plan
Disposable PostgreSQL/PostGIS CI validates 2-supplier split, cart ownership/versioning, tax-inclusive and tax-exclusive pricing, verified GST split, PIN/area freight, changed price/cart rejection, idempotent placement, held-not-sold inventory, coupon freight isolation, cancellation, competing checkout transactions, recovery of expired unpaid holds, and all previous foundation, Clerk, catalog, delivery, RFQ and inventory tests. Legacy backend compilation runs independently.
