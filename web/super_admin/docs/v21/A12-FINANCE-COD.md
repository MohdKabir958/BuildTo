# Admin A12 — COD and settlement evidence (not bank execution)

**Existing models only:** CodCollection, Supplier, SupplierOrder, PaymentAttempt, Settlement, SettlementLine, LedgerJournal, AuditEvent. No migrations, Prisma edits or new infrastructure.

A12 adds two minimal FINANCE_MANAGE-only reads:
- `GET /api/v2/admin/finance/suppliers`: 1–50 keyset page of supplier IDs, display names, approval and suspension status; no GSTIN, bank account or private contact.
- `GET /api/v2/admin/finance/cod`: 1–50 keyset page of recorded (or status-filtered) supplier-held cash receipts, exact paise strings, no collector details.

**Reuse existing verified actions:**
- Supplier finance statement and ledger journal are read-only.
- Settlement draft is idempotent, validates capture/invoice/full shipment/return eligibility and stays `ON_HOLD`.
- A second independent FINANCE admin attests external bank evidence via `settlements/{id}/approve`. This posts a balancing *memorandum*, not bank transfer.
- COD reviewer independently verifies or disputes a supplier-reported collection. Even VERIFIED COD remains supplier-held, not platform cash.
- Distinct-person rules and bank reconciliation gates stay server-side. A finance role alone cannot override them.

The portal shows exact money strings, no floats, finance risk warnings and a confirmation for each independent attestation. It **does not initiate refunds, bank payouts or gateway POSTs**. All read lists are bounded. A13 covers controlled refund and payout statuses separately.

Test: HTTP 401/403, finance scoped reads and privacy; React finance controls; full V2.1 finance integration regressions. No staging database writes.
