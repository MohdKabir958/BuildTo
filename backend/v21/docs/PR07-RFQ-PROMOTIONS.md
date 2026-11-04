# Buildto V2.1 — PR 07: RFQs, Supplier Quotes and Promotions

## Architecture
The RFQ and promotions modules run in the existing **single Express API + PostgreSQL V2.1**. No new queues, Redis, microservice, or schema migration is introduced. All protected actions use the same Clerk identity and database membership policies as previous PRs. RFQ state transitions and promotion accounting use serializable database transactions with bounded retries.

## RFQ business workflow

1. Authenticated customer creates a **DRAFT** RFQ with 1–30 exact-decimal material quantities, active units, optional active products and an optional project **owned by the same customer**. A short location snapshot contains only city, PIN and delivery notes; do not expose the customer's saved private address or phone to unrelated suppliers.
2. Customer opens the draft and explicitly invites approved suppliers. Multiple invitations are supported but only customer-authorized invitations are stored. Duplicate invitations are idempotent.
3. Only active supplier memberships with `RFQ_QUOTE` can view the invitation or submit/revise a quote. Supplier status must remain approved and unsuspended. VIEWER and other suppliers cannot access it.
4. A quote must price **every RFQ line exactly once**, using exactly the requested quantity and unit. Listing-backed lines must belong to that supplier and match the RFQ product. Bespoke nonlisting quotes are permitted. Quote amounts use exact PostgreSQL Decimal and BigInt paise.
5. Quotes are versioned. Revising a submitted quote marks the prior version `REVISED`; the latest remains `SUBMITTED`. Historical quote lines and prices are preserved.
6. Only the RFQ customer can award one current, valid, submitted quote. A transaction locks the RFQ row, marks the selected quote `ACCEPTED`, rejects competing submitted quotes and sets the RFQ to `AWARDED`. Two concurrent awards cannot both win. Other users receive a 404.
7. **Awarding an RFQ is not payment or order placement.** A subsequent checkout PR will create the actual supplier order with `sourceQuoteId`, reconfirm the supplier and delivery arrangements, reserve stock and handle payment/COD.

### Exact quote amount policy
`unitPrice` is **INR excluding GST per quoted unit**, supplied as an exact decimal string with up to 4 fractional digits. `subtotalPaise` is the sum of line quantities × price × 100 rounded to paise (HALF_UP). `taxPaise` is calculated from the rounded taxable paise for each line using the quoted basis points, rounded HALF_UP. `lineTotalPaise` is taxable + tax. `totalPaise=subtotalPaise+taxPaise+deliveryPaise`. No caller-supplied subtotal/tax/total is accepted.

RFQ quote taxes are provisional commercial estimates; supplier tax-registration checks and legally compliant tax invoices belong to the checkout, tax and finance PRs.

## Promotion business workflow

Admin roles `OPERATIONS` and `OWNER` may create and activate/deactivate a code-based promotion. The code is unique and normalized to uppercase. Promotions are immutable after creation apart from the active toggle; changes to an active promotional offer must use a new code rather than silently change pricing terms.

Supported:
- Fixed discount in integer paise, capped by the authoritative order subtotal.
- Percentage discount in whole basis points, with optional paise cap.
- Free-delivery discount limited to actual server-calculated delivery fee.
- Minimum cart subtotal, start/end UTC timestamps, global redemption limit and per-customer redemption limit.

### Transactional checkout integration
There is deliberately **no** client-facing endpoint allowing an arbitrary subtotal to be checked or discounted. Checkout PR 08 must calculate subtotal and delivery from trusted DB records. The function `recordOrderPromotion(tx,{code,customerId,orderId})` locks the actual promotion row, verifies activation/timing/limits, reads the persisted order, verifies the exact expected discount and creates one `PromotionRedemption`. The uniqueness of `orderId` prevents multiple coupons per order. The promotion row lock serializes concurrent redemptions and prevents global-limit overruns. This function is only valid within the same order transaction. No speculative promotion reservations or background jobs are required.

## HTTP endpoints

Customer:
- `GET/POST /api/v2/rfqs` (POST requires `Idempotency-Key`)
- `GET /api/v2/rfqs/:rfqId`
- `POST /api/v2/rfqs/:rfqId/open`
- `POST /api/v2/rfqs/:rfqId/invitations/:supplierId`
- `GET /api/v2/rfqs/:rfqId/quotes`
- `POST /api/v2/rfqs/:rfqId/quotes/:quoteId/award`
- `POST /api/v2/rfqs/:rfqId/cancel`

Supplier:
- `GET /api/v2/suppliers/:supplierId/rfqs`
- `GET/POST /api/v2/suppliers/:supplierId/rfqs/:rfqId/quotes`

Admin:
- `GET/POST /api/v2/admin/promotions`
- `PATCH /api/v2/admin/promotions/:promotionId`

## Release and testing limitations

- Live Neon production data and schemas are unchanged, no deployment or merge.
- Promotion discounts are not yet usable in customer checkout until PR 08 calls the internal helper inside its own transaction.
- Accepted RFQs are not purchase orders until PR 08 creates and validates an order.
- Supplier documents, project site management, tax invoice compliance, payment gateway and final freight calculation remain future work.
- CI uses disposable PostgreSQL/PostGIS and reruns auth/catalog/delivery/inventory tests, real quote totals, supplier isolation and promotion concurrency.
- Staging requires official Prisma migration baseline history and live Clerk provider checks before deployment.
