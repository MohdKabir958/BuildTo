# S08 — BuildTo Supplier RFQ invitations and quotation revisions

## Scope

Invited RFQs only; the backend requires active approved supplier membership and RFQ_QUOTE. OWNER, MANAGER and CATALOG can read invitations and respond. Other roles see a restricted panel and never call RFQ endpoints.

- GET `/api/v2/suppliers/{supplierId}/rfqs`: only open, invited requests, up to 100.
- GET `/api/v2/suppliers/{supplierId}/rfqs/{rfqId}/quotes`: owned quote versions, latest first, up to 50.
- POST `/api/v2/suppliers/{supplierId}/rfqs/{rfqId}/quotes`, one secure `Idempotency-Key` per submission intent.
- Every requested item must be priced once, with same exact quantity and unit as customer RFQ. Exact taxable INR unit price (4dp), GST basis points and delivery paise are sent to the backend; the server calculates/rounds definitive quotation totals and controls versioning. No locally fabricated totals.
- Quote can be revised while request remains OPEN and within deadline; final accepted/rejected quote state blocks revisions.
- Network uncertainty must not result in blind duplicate retries; user must refresh quote history. No local quote awarded/order/payment transitions.
- Existing construction material listing is optional for bespoke RFQ line per approved V2.1 backend quote contract.
- No schema change, no open quote marketplace, no unauthorized supplier invite creation.

## QA gate

S01–S08 regression, strict analyzer, formatter, staging bundle and native Clerk Android check. Real authorized supplier and customer staging award-to-checkout device UAT remains for the later final regression stage.
