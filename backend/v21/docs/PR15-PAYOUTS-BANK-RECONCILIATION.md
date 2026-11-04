# Buildto V2.1 — PR15: Payout beneficiary, controlled transfer intent and bank reconciliation

This is implementation PR 15 stacked on PR14 `backend/v21-14-controlled-refunds-gst-credit-notes`. It extends the existing modular Express/TypeScript/Prisma/Postgres backend. **No microservices, Redis, Kafka, payout job runner or bank disbursement endpoint.** All external RazorpayX integration uses **GET-only**. Production and RazorpayX live credentials are forbidden in the present staging configuration.

## Meaning of financial states

- **PENDING** transfer: only an exact bank payout **intent**, with a stable external reference ID `BT<UUID-without-hyphens-uppercase>`. It has **not been sent** to RazorpayX. There is no payout POST method in this code.
- **PROCESSING** transfer: a RazorpayX read-only lookup returned `queued`, `pending`, or `processing` for that precise payout ID, source reference, beneficiary and paise.
- **SUCCEEDED** transfer / **PAID** settlement: RazorpayX GET reported `processed` with matching account, exact INR amount, unique internal reference, purpose and nonempty UTR. A balanced, immutable supplier-payable clearing memorandum was posted. This does not claim that Buildto independently verified every beneficiary bank-statement record.
- **FAILED** transfer / settlement: RazorpayX reports `reversed`, `rejected`, `failed` or `cancelled`. The settled payable is **not** marked PAID. Terminal transfer remains reserved; never create another attempt without a formal reconciliation/compensating workflow.
- **Human bank statement attestation**: a third, independent finance administrator compares a real external debit to the exact provider UTR, confirms a single nonreused bank reference, and records an immutable audit entry. This is explicitly NOT a bank API feed or automatic cash position verification. Customer refunds and supplier-held COD cash remain separate.

## Supplier bank beneficiary

- Finance admin registers **only** existing RazorpayX fund account ID (`fa_...`) and account-validation ID (`fav_...`).
- The provider adapter calls only `GET /v1/fund_accounts/:id` and `GET /v1/fund_accounts/validations/:id`; requires **active bank fund account** and validation `completed` **with account_status active/valid**, not simply a completed validation. Registered beneficiary legal name must match the approved supplier legal name and provider fund-account holder.
- A second finance admin rechecks both GET endpoints independently before activating the account, under a supplier row lock. Neither reviewer may be active supplier personnel. A single approved beneficiary per supplier, unique RazorpayX token, unique validation record, and immutable account identity are enforced by database triggers and indexes.
- Full bank account numbers are parsed from the provider response only in transient memory to obtain **last four digits** and are never saved, returned to clients or included in audit/outbox events. Provider credentials are server-held in optional `RAZORPAYX_READ_ONLY_KEY_ID/SECRET`; live keys are forbidden in staging. Fund-account validation is not supported by RazorpayX in test mode according to their documentation; tests use a controlled injected provider adapter.

## Payout intents and external finance operations

- One transfer per settlement at the **database level**. Supplier must be approved, settlement `APPROVED` by an independent prior reviewer with a posted, balanced accrual memorandum, amount exact and >0, no prior transfer, no adjustment, no noncancelled return, no nonrejected provider refund, no open or partially offset COD commission receivables, and one separately approved active validated beneficiary.
- The payout requester must be different from the settlement checker and beneficiary approver, and cannot be a supplier member. All intents use `Idempotency-Key` with serialized locks and exact hash matching; retry does not create a second transfer.
- An authorized operator then **manually creates the exact vendor payout in the RazorpayX Dashboard/approved finance interface**, with `purpose=payout`, the frozen `externalReferenceId`, the frozen amount and the approved `fa_...` destination. Finance maker-checker policy must be enforced by that external system; this backend does not claim to initiate or approve the physical bank transfer.
- Reconciliation fetches `GET /v1/payouts/:id` outside a PostgreSQL transaction and checks fund_account_id, provider_ref, amount in INR paise, `purpose=payout`, `reference_id` and recognized status. `processed` requires a valid UTR. The reconciling finance user must differ from the intent maker and supplier personnel. Immutable status transitions, ledger journal existence and exact payable are further guarded by database constraints. Never retry a reversed transfer implicitly.
- Bank audit verifies an external statement **manually** with separate reviewer, original provider UTR and unique bank-statement reference. Finance report highlights processed payouts not yet independently attested against a real statement.

## Authenticated API

| Method | Path | Access |
|---|---|---|
| GET | `/api/v2/suppliers/:supplierId/finance/beneficiaries` | Supplier FINANCE_READ; only masked account |
| GET | `/api/v2/suppliers/:supplierId/finance/payouts` | Supplier FINANCE_READ; own payout states |
| POST | `/api/v2/admin/finance/suppliers/:supplierId/beneficiaries` | Independent admin FINANCE_MANAGE, `{ "fundAccountId", "validationId" }` |
| POST | `/api/v2/admin/finance/beneficiaries/:accountId/approve` | Different finance admin, `{}` |
| POST | `/api/v2/admin/finance/settlements/:settlementId/payout-intent` | Independent admin, Idempotency-Key and `{ "payoutAccountId" }` |
| GET | `/api/v2/admin/finance/payouts` | Admin FINANCE_MANAGE finance queue |
| POST | `/api/v2/admin/finance/payouts/:payoutId/reconcile` | Different admin, `{ "providerPayoutId" }`; provider GET only |
| POST | `/api/v2/admin/finance/payouts/:payoutId/bank-attest` | Third independent finance admin, `{ "bankStatementReference", "providerUtr" }` |
| GET | `/api/v2/admin/finance/payouts-reconciliation` | Admin FINANCE_MANAGE, recent provider/bank evidence exceptions |

OpenAPI **0.15.0** documents **119** paths. All money is bigint paise strings. All financial mutations are serializable and audited with transactional outbox.

## Schema migration and release gates

- Migration `20261104_payout_beneficiary_reconciliation`: beneficiary proof and maker-checker columns, unique provider account/validation references, one active beneficiary per supplier and one payout transfer per settlement, positive amount and terminal-status guards, immutable destination and payout ownership, posted payout clearing ledger required before SUCCEEDED, and exact SUCCEEDED payout before settlement becomes PAID. An incompatible staging data shape causes migration to **fail closed**. The original baseline and PR14 migration remain unchanged.
- Canonical schema and application Prisma schema retain exact parity; the DB schema inspector recognizes the new fields/indexes/constraints/triggers while preserving baseline-only staging resolve. Disposable PostgreSQL16/PostGIS migration, complete strict TypeScript regression and legacy compile run in dedicated CI.
- Production sign-offs still required: RazorpayX merchant/financial permissions, live beneficiary validation (not supported by provider test mode), penny-drop name-match dispute policy, signed external payout approval and unique reference enforcement, funding/bank balance availability, bank statement source authenticity, payout reversal investigations, auditor approval, live payout reconciliation/webhook sandbox, incident runbooks, GST and financial accountant approval, migration/drift audit, staging rollback and sequential merge of stacked PRs.

**Never mistake `SUCCEEDED` for a bank-statement API verification, `PENDING` for an executed payout, or an attestation for an automatic bank transfer.**
