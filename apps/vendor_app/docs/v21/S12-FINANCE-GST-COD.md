# Supplier S12 — Finance, GST tax documents, COD and controlled credits

Supplier finance lives under Business > Finance & GST. It uses existing V2.1 routes, never local payouts, direct bank mutations, fabricated amount totals, or customer finance permissions.

## Permission and independent review
- OWNER/MANAGER/FINANCE have FINANCE_READ and INVOICE_ISSUE; OWNER/MANAGER/FULFILLMENT can record supplier-held COD under ORDERS_FULFILL.
- GET `/api/v2/suppliers/{supplierId}/finance/{statement,beneficiaries,payouts}` requires FINANCE_READ. Beneficiaries are *masked*; supplier cannot add or approve bank accounts.
- GET `/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/{invoices,cod}` requires FINANCE_READ. The server verifies own supplier order.
- POST `.../invoices` sends exactly `{}`, requires INVOICE_ISSUE and backend-verified dispatch, GST eligibility and payment/COD; the server owns statutory numbering, snapshots, discounts, HSN and tax amounts.
- POST `.../cod` uses a stable unique idempotency intent and references a delivered, independently verified customer handover. Recorded supplier cash is **unverified** until separate admin finance review. No supplier self-verification.
- POST `/api/v2/suppliers/{supplierId}/returns/{returnId}/credit-note` is **full-return only**, requires independently approved physical receipt, and the issuing user must differ from the goods receiver. GST note is not the refund: admin finance independently handles gateway refunds.
- Settlement `PAID`, provider `SUCCEEDED`, or RazorpayX processed do **not** assert bank credit. Finance endpoints explicitly report `bankingReconciled:false` and provider-only evidence. Beneficiary approval and payouts are admin-only.

## Engineering controls
All money is immutable integer paise strings validated with BigInt. Unknown statuses, foreign supplier documents, unmasked bank accounts and unsupported bank verification fail closed. The app never serializes raw bank account details and does not infer totals across bounded 100-row histories. Auth and supplier switching clear data. Network-uncertain COD attempts must reconcile by refresh rather than mint a different intent.

Release acceptance requires customer/supplier device COD and OTP flows, independent finance reviewer attestations, GST verification and approved staging test data; no automated check can replace these.
