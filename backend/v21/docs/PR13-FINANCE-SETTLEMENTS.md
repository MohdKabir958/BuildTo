# Buildto V2.1 — PR 13: Finance reconciliation, COD commissions and non-disbursing supplier settlements

## Architecture and controls

PR 13 is stacked on PR 12 (`backend/v21-12-returns-support-reviews`) in the existing modular Express/TypeScript/Prisma/Postgres service. Uses existing settlement, settlement line, COD commission receivable, ledger account, journal and line records and PostgreSQL journal-posting/immutability and refund-budget triggers. No Redis/Kafka, microservices, new migration or premature background infrastructure.

**Critical meaning of statuses:** Razorpay `CAPTURED` means provider payment capture, **not Buildto bank credit**. COD `VERIFIED` means supplier physically collected cash and finance independently verified its claim; **Buildto did not receive the cash**. A settlement `APPROVED` here means an independent FINANCE administrator recorded a human-attested bank-statement reference and posted a balanced **accrual memorandum**; it is **not a payout**. All payouts remain disabled and there are no `PayoutTransfer` writes, bank transfers or refund-provider calls. No API marks a settlement `PAID`.

## Reconciliation and private supplier statements

- `GET /api/v2/suppliers/:supplierId/finance/statement` requires `FINANCE_READ` for that supplier, returns up to 100 latest settlement summaries/lines and independently verified COD fee receivables. There are no bank account details or public finance endpoints.
- `GET /api/v2/admin/finance/suppliers/:supplierId` requires `FINANCE_MANAGE` and provides delivered supplier orders, funding-type evidence, active settlement allocations and hold markers.
- All amounts are immutable server-priced bigint **paise strings**; no client-supplied fee, tax, discount or supplier settlement totals are accepted.

## Online settlement proposals

- `POST /api/v2/admin/finance/settlements/drafts` requires finance admin and `Idempotency-Key`, with `supplierId`, `settlementKey`, 1–50 unique supplierOrderIds and bounded ISO UTC period.
- Each supplier order must be DELIVERED with **verified full shipment-line handover**, a matching issued GST invoice, exactly one verified Razorpay full-parent capture, nonnegative contractual platform fee strictly less than the supplier-order total, and no pending/current return or captured-refund request.
- COD-selected orders and payments with merely AUTHORIZED/CREATED/FAILED flag are rejected. Only same-supplier orders created within the declared period may be allocated.
- The engine locks parent orders in stable order inside bounded SERIALIZABLE transactions, checks existing active (non-CANCELLED) settlement lines, calculates `grossPaise`, `commissionPaise` and `payablePaise = gross - commission`. Client cannot set commission, net, adjustments or refund offsets. Every proposal begins `ON_HOLD`, not APPROVED/PAID.
- Exact duplicate request key/payload is safely replayed. A changed request key payload fails. Cancelled drafts remain auditable and may free supplier lines for a different future proposal.

## Independent review, memorandum posting and cancellation

- `POST /api/v2/admin/finance/settlements/:settlementId/approve` requires a different FINANCE_MANAGE user from the draft maker and someone who is not an active member of the beneficiary supplier. A human bank-statement reference of 12–120 characters must be attested. A prior attestation reference cannot be knowingly reused.
- Before approval, every supplier order, payment, invoice, shipment proof, return/refund and allocation is rechecked in the same serializable transaction.
- A balanced journal posts a **debit to online capture clearing memorandum**, credit to supplier payable memorandum and, if applicable, credit to platform fee memorandum. The existing database trigger forbids unbalanced posting and changes to posted journal headers/lines.
- Audit afterState records `bankEvidenceType=HUMAN_ATTESTED`, `gatewayBankVerified=false`, `payoutExecuted=false`. Approval **does not mean** bank deposit verification by a provider; operating staff must independently validate their source evidence.
- `POST /api/v2/admin/finance/settlements/:settlementId/cancel` cancels only `ON_HOLD` drafts with a logged reason. A posted accrual/APPROVED settlement cannot be silently undone, and a payout is not created.

## Verified supplier-held COD commissions

- `POST /api/v2/admin/finance/cod-commissions/:supplierOrderId/recognize` requires independent FINANCE_MANAGE user not employed by the supplier, one full verified COD receipt, the corresponding posted COD memo, completed supplier delivery, and exact positive immutable `platformFeePaise`.
- Creates exactly one SupplierCommissionReceivable per supplier order with `commissionPaise = platformFeePaise`, `offsetPaise = 0`, `status = OPEN`, and a linked balanced posted COD commission memorandum.
- Idempotent repetition returns the existing receivable after proving its journal is posted and its amount matches the immutable contract snapshot. The supplier still holds the original COD cash; Buildto has not received a bank payment or netted the fee.
- No automatic commission offsets, supplier account debits, settlement transfers, receipts or payouts are claimed.

## Audit and verification

- `GET /api/v2/admin/finance/journals/:journalId` is finance-admin-only and shows journal lines, account codes, debit/credit equality and posting state, never raw bank account details.
- OpenAPI **0.13.0** includes 104 route paths and the 7 new finance paths. A dedicated disposable Postgres/PostGIS CI workflow compiles V2.1 and legacy, checks schema parity, runs the full HTTP integration suite including finance, COD, payments and shipments.
- Tests enforce supplier/admin RBAC, undelivered/unenforced OTP refusal, missing invoice, unverified online payment and COD separation, exact fee/amount allocation, duplicate draft rejection, cancellation, maker-vs-approver separation, supplier conflicts, balance of posted journal entries, return and refund holds and COD commission memo recognition.

## Outstanding release blockers

- **Payouts are not implemented:** verified bank-credit reconciliation integration, verified destination account/token, batch approval policy, disbursement gateway, transfer idempotency, webhook confirmation, payout failures, double-payout prevention and final bank-ledger reconciliation remain gated work.
- **Refunds and GST credit notes are not implemented:** customer return approval is not sufficient money authorization. Precise refund allocation across supplier items, tax, freight and commissions, provider refunds, ledger reversals and Indian GST credit-note approvals are needed before production refunds.
- Operational bank attestation policy, settlement audit independence, GST accounting signoff, live Clerk/Razorpay sandbox, prior staged PR merges, official V2.1 migration ledger and full-repository baseline CI remain release gates. No production Neon database, provider bank API or real customer money was changed by PR 13.
