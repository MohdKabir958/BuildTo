# BuildTo Admin A13 — full refund evidence, beneficiary and payout intent review

This PR completes the finance portal's existing **manual, provider GET-only** workflows, not automatic money execution.

## Existing table and API approach
- Read-only and FINANCE_MANAGE-only `/api/v2/admin/finance/refund-candidates` and `/api/v2/admin/finance/suppliers/{supplierId}/beneficiaries` use existing ReturnRequest, TaxInvoice and SupplierPayoutAccount.
- All payment/refund/payout action routes are pre-existing, audited V2.1 functions with independent actor requirements and exact paise/gateway matching. Their UI labels must distinguish **request**, **approved**, **provider processed**, and **human bank statement attestation**.
- No Prisma model or migration changes and no new external payment POST calls.

## Quality and security conditions
- Tests must demonstrate role denial and bank secret redaction, never merely that a toolbar renders.
- UI requires a second authorized finance actor where the API enforces maker-checker separation.
- Provider status GET is not proof of bank credit; payouts remain disabled for automatic execution.
- Invalid evidence must fail closed, never infer eligibility from preliminary candidate data.
- Frontend uses V2.1 `V21ApiClient` and Clerk bearer tokens; no legacy /api/v1 bypass.

## Rollout
Only stage after merging earlier A10–A12 and validating this PR against disposable PostGIS and admin UI CI. Do not promote to production or alter the existing Neon schema.
