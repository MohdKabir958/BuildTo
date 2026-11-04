# Buildto V2.1 — PR 10: Customer COD, Independent Cash Verification and GST Invoice Snapshots

## Scope and architecture

This is **implementation PR 10**, stacked directly on the PR 09 payment branch. We keep one modular Express/TypeScript application using the approved V2.1 Prisma schema and PostgreSQL/PostGIS. No new migrations, queues, Redis, Kafka, dedicated workers or extra services. No production/staging database modifications from this PR.

### Money and stock are separate

1. **COD selection is not payment.** A customer selects COD for an otherwise unpaid and PLACED, fully warehouse-reserved order via `POST /api/v2/orders/:orderId/cod` with an Idempotency-Key and empty JSON object. Selection is blocked if **any** previous gateway attempt exists, even a failed attempt whose provider outcome might be uncertain. The same key replays the original selection. No customer-supplied totals or currency.
2. In one SERIALIZABLE transaction under a locked parent PurchaseOrder, the backend creates exactly one `PaymentAttempt(provider=MANUAL,method=COD,status=PENDING,capturedPaise=0)`, **commits** all held inventory, confirms the parent order, and writes audit and outbox events. This reserves the physical goods for fulfillment, **not a claim of collected cash**. Failed transactions cannot leave partially committed multi-supplier orders.
3. Customer order `paymentStatus` reads the actual payment method and supplier child COD aggregates: `COD_DUE`, `COD_RECORDED_UNVERIFIED` or `COD_VERIFIED` only when every child has its full amount independently verified. It never invents a Razorpay `CAPTURED` event.
4. COD receipt recording is possible **only after PR 11 fulfillment has delivered the full supplier order** and created a delivered Shipment with OTP-verified or separately approved exception handover. This intentionally prevents recording collections against unshipped stock. A supplier user with `ORDERS_FULFILL` may report a full child-order cash collection, including its `shipmentId`, unique `receiptNumber` and a short note. A single supplier order cannot record more than the child total.
5. Supplier receipt is first stored `RECORDED`. The V2.1 PostgreSQL trigger atomically increments `SupplierOrder.codRecordedPaise`, applies full amount/ownership constraints, and **does not** change `codVerifiedPaise` or online payment state.
6. Separately staffed admin FINANCE/OWNER users can review through `POST /api/v2/admin/finance/cod/:receiptId/review`. No seller staff, including employees who also hold finance admin roles for **that supplier**, can approve their own supplier collection. `DISPUTE` makes an unverified claim non-actionable for now; investigation/resolution is a later finance workflow.
7. On `VERIFY`, the admin must supply an external checking/reference string. The backend posts an **exactly balanced two-line supplier-held-cash memorandum**, scoped to that supplier, before changing the receipt to VERIFIED. The V2.1 DB trigger requires the journal to already be posted and atomically increments the child `codVerifiedPaise`. Supplier-held cash is **not Buildto bank or Razorpay cash** and the journal explicitly uses memorandum accounts, not a fictitious platform bank deposit. Full legal accounting mapping, commission offsets and actual supplier settlement belong to PR 13.
8. Verified receipts and posted journals cannot be mutated: PostgreSQL triggers enforce immutability. User, role, amount, receipt ID and linkage are server validated, and audit/outbox operations commit in the same transaction. No server API allows a supplier to self-verify.

## Protected HTTP routes

| Method and route | Permission and meaning |
| --- | --- |
| `POST /api/v2/orders/:orderId/cod` | Customer only. Empty JSON, Idempotency-Key; select unpaid COD once |
| `POST /api/v2/suppliers/:supplierId/orders/:supplierOrderId/cod` | Supplier ORDERS_FULFILL. Idempotency-Key, delivered shipment, receipt number; **unverified** |
| `GET /api/v2/suppliers/:supplierId/orders/:supplierOrderId/cod` | Supplier FINANCE_READ (finance, owner or manager) only |
| `POST /api/v2/admin/finance/cod/:receiptId/review` | Admin FINANCE_MANAGE; `VERIFY` with checked external reference or `DISPUTE` |
| `POST /api/v2/suppliers/:supplierId/orders/:supplierOrderId/invoices` | Supplier INVOICE_ISSUE (FINANCE/OWNER/MANAGER). Empty JSON; immutable server-generated invoice |
| `GET /api/v2/suppliers/:supplierId/orders/:supplierOrderId/invoices` | Supplier FINANCE_READ only |
| `GET /api/v2/orders/:orderId/invoices` | Customer ownership. Only own supplier invoice snapshots |

All routes use existing live Clerk identity checks, DB-scoped authorization and no ID enumeration. Customers cannot edit GST amount or invoice number.

## Invoice rules

- A supplier-finance user can issue **one** invoice per child order after DISPATCHED/PARTIALLY_DELIVERED/DELIVERED, using immutable `SupplierOrder`, `SupplierOrderItem` and customer address snapshots. The invoice is idempotent under the parent order lock. Replacing, cancelling, credit notes and partial-fulfillment revision require their own accounting workflow.
- Requires approved, verified supplier status, a full seller billing address, complete buyer address, exact INR paise, consistency between line and supplier amounts, positive unit/line money, and verified payment capture **or** a confirmed manual COD selection.
- The supplier's legal name, verified seller GST status/GSTIN, financial year in **Asia/Kolkata** (April–March), seller/buyer address, HSN and GST split are stored as immutable issuance snapshots. SupplierId+financialYear+invoiceNumber is unique. The buyer's GSTIN is **not invented**; these are consumer/B2C-oriented records until verified business GST identities are supported.
- `TAX_INVOICE` requires verified REGULAR GST registration and valid GSTIN. Taxable goods require an HSN. `BILL_OF_SUPPLY` requires separately verified COMPOSITION/EXEMPT status and zero GST.
- Sums of taxable goods minus item discounts, taxes, CGST/SGST/UTGST/IGST/cess and non-tax product totals are recomputed and validated before issuance. No client-supplied tax rate, net amount, buyer GSTIN or invoice number is accepted.
- **Important shipping tax gate:** PR 08 applied freight without an independently verified GST treatment. For orders having both taxed goods and nonzero delivery fees, statutory invoice issuance returns `409 FREIGHT_GST_POLICY_REQUIRED` instead of labeling possibly taxable composite freight as exempt. Legal/GST sign-off and correct pricing changes are required before those checkout configurations can issue tax invoices. A correct invoice cannot retroactively change an already accepted order amount.
- A JSON invoice record is not automatically a legally compliant PDF, e-invoice/IRN, e-way bill, tax return, receipt, or digital signature. GST specialist review, place-of-supply/HSN/rate policy, supplier registration, e-invoicing thresholds, invoice numbering/legal legends, credit notes and retention must be completed before statutory production use.

## Testing and release boundaries

Dedicated `.github/workflows/buildto-v21-cod-invoices.yml` deploys a disposable PostgreSQL/PostGIS V2.1 baseline, checks schema parity and official migration, seeds references, builds TypeScript, runs the complete HTTP/PostgreSQL suite including payment regressions, and separately builds the legacy backend. No live credentials.

New integration tests cover: tenant boundaries; untrusted client money; COD idempotence and stock; gateway/COD exclusion; delivery OTP/approved exception gate; supplier permission checks; receipt unique constraints; independent admin dual-role denial; balanced posted ledger; receipt verification replay; invoice seller/buyer/HSN/GST amount snapshots; buyer/supplier read access; invoice duplicate prevention; and refusal to issue mis-taxed freight.

**Not yet ready for production:** PR 11 must implement authentic shipment/OTP verification (test fixtures simulate a valid supervised handover). Financial verification checks are human/operational and need training/evidence handling; PR 13 will implement official accounting posting, COD remittance and supplier settlements. COD disputes, missing cash, partial deliveries/partial COD, refunds, invoice credit notes, actual documents/e-invoice generation, GST signoff, gateway sandbox verification, official staging Prisma migration ledger and live Clerk integration remain explicit release requirements. Do not merge this branch directly into main or deploy as a standalone COD product.
