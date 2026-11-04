# Buildto V2.1 — PR14: Controlled full-return refunds and GST credit notes

PR 14 stacks on PR 13 (`backend/v21-13-finance-reconciliation-settlements`). No production database use, Stripe/Razorpay refund POST, automatic disbursement, microservices, workers, Redis or Kafka.

## Financial meaning and gating

* The customer first requests a return (PR12). Independent support approves it, and supplier fulfillment confirms **physical receipt**. That is **not a customer refund**.
* A supplier employee authorized for **INVOICE_ISSUE**, who did not physically receive the goods, issues the GST credit note against an existing immutable **TAX_INVOICE**. Supplier must remain approved, active, GST regular and have a GSTIN.
* The first release supports **ONLY a complete received supplier order, all ordered quantities and exactly the whole original tax invoice**. It does **not** support partial GST allocations, multi-claim partial returns, taxable freight apportionment or non-TAX_INVOICE commercial notes. Such claims remain blocked, not guessed.
* Previous invoice `taxablePaise`, each CGST/SGST/UTGST/IGST/cess split, HSN, SKU, quantity, invoice amount and original financial year are reused exactly. Missing/contradictory source line snapshots block issuance. A new, unique `BTCN-` number uses the issuance financial year in Asia/Kolkata. Both original invoice and credit note remain queryable by supplier finance and original customer.
* An approved/noncancelled settlement allocation blocks credit-note issuance and refund authorization. No silent clawback of a previously approved supplier payable is permitted.
* A finance administrator independently **requests** the full refund after the issued GST note exists. The amount is server-derived, the owning parent order is row-locked, exactly one Razorpay `CAPTURED` payment with signed payment evidence must cover the parent amount and the supplier order, and the existing DB trigger reserves available provider refund budget. Supplier-held COD, unsupported/incomplete invoices, unsettled returns and client-proposed refund values fail.
* A **different** finance administrator, not the requester and not active supplier personnel, reviews and approves. `APPROVED` means **only permission for external merchant operations**, NOT money returned.
* To execute the refund, approved finance staff must initiate it through the merchant's controlled Razorpay dashboard/approved offline financial process. The Buildto API has **NO POST refund operation** because a timeout cannot safely be repeated without a provider-level idempotency guarantee. Staff then submit the real `rfnd_...` ID to `/reconcile`.
* Backend calls Razorpay **GET /v1/refunds/{id}** outside a DB transaction, verifying exact provider refund ID, original payment ID, INR paise and known status. `pending` becomes `PROCESSING`, `failed` becomes `MANUAL_REVIEW` (budget remains reserved and another refund cannot accidentally begin); only `processed` becomes `SUCCEEDED` and posts one immutable balanced **memorandum**, not a bank debit claim.
* `SUCCEEDED` means Razorpay independently reports the refund processed, **not** that the customer's bank account has credited. All responses expose `customerBankCredit: NOT_VERIFIED`.
* A provider status mismatch, missing gateway lookup, gateway outage, changed provider reference or changed return/order evidence fails closed without changing status.

## Additive migration and evidence

New migration `20261104_return_refund_credit_note_link` adds optional cross-transaction columns to `RefundRequest` and `TaxInvoice` plus unique constraints and FKs to original tax invoice and received return. SQL triggers prevent:
- New refunds without a return ownership link or a received return
- Editing refund source, amount, payment or idempotency key
- Fabricating `SUCCEEDED` without approval, provider refund ID and completed timestamp
- Moving posted processed refunds back to pending or rewriting provider references
- Forged credit notes from the wrong supplier/source/return, missing issued tax invoice or any amount/GST-split difference from the original
- Deleting an issued credit note or deleting/modifying the linked source invoice
- Unsafe refund status transitions
- Duplicate credit/refund allocations for a single received return, independently of route-level checks

The canonical schema in `architecture/buildto-schema-v2.1/prisma/schema.prisma` and scoped backend Prisma schema remain in exact sync; original approved baseline migration is unchanged. Strict PostgreSQL catalog verification checks the **latest** additive columns, FKs, guards, indexes and triggers after deploying to a disposable database; legacy baseline resolution can use baseline-only schema verification.

## New authenticated API endpoints

| Method | Path | Auth / purpose |
|---|---|---|
| POST | `/api/v2/suppliers/:supplierId/returns/:returnId/credit-note` | `INVOICE_ISSUE` and independently separated receiver; `{}` |
| GET | `/api/v2/orders/:orderId/refunds` | Order customer only; no other-order enumeration |
| GET | `/api/v2/admin/finance/refunds` | `FINANCE_MANAGE` open finance queue |
| POST | `/api/v2/admin/finance/refunds/requests/:returnId` | `FINANCE_MANAGE` + `Idempotency-Key`, `{}`; reserves budget |
| POST | `/api/v2/admin/finance/refunds/:refundId/approve` | A separate, supplier-independent `FINANCE_MANAGE` admin; `{}` |
| POST | `/api/v2/admin/finance/refunds/:refundId/reconcile` | `FINANCE_MANAGE`, read-only Razorpay lookup; `{ "providerRefundId": "rfnd_..." }` |

OpenAPI 0.14.0 documents **110 paths**. No public refund write API; the gateway signature/credential remains server-held and cannot be supplied by an HTTP request.

## Tests and release blockers

The PostgreSQL-backed integration suite covers complete GST-registered full return, per-line source evidence, origin credit copies, seller permissions, receiver/issuer separation, refund requester/approver separation, idempotency, captured budget, COD exclusion, partial return rejection, active settlement hold, pending/processed/failed provider events, wrong provider payment/amount rejection, customer ownership, immutable ledger and tax source, and full legacy regressions.

Release gates remain: legal/GST advisor sign-off on credit-note format, original reference and mandatory fields; statutory treatment of partial orders, freight, discounts, invoices spanning financial years and supplier-specific GST credit rules; actual regulated Razorpay dashboard refund process and reconciliation operations; bank/UPI customer credit support workflow; payout withholding/reversal policies; staged DB migration/drift checks; formal maker-checker and audit procedures; sandbox + live mode separation. PR 15 will address independent bank reconciliation and controlled supplier payouts only after these separate evidence gates are agreed.

**This PR is safe for staged review, not an authorization to execute real merchant refunds.**
