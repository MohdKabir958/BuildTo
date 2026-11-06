# Supplier S09 — Order queue, acceptance and restricted refusal

Only current, approved BuildTo V2.1 supplier memberships may list their own orders. OWNER, MANAGER and FULFILLMENT may attempt acceptance or a narrowly allowed unpaid refusal. All server mutations recheck supplier membership and parent order state.

- GET `/api/v2/suppliers/{supplierId}/orders` returns a bounded sample of 100 records, not a universal count. Order totals remain exact paise; detailed payment state is deliberately not invented by the client.
- POST `.../orders/{supplierOrderId}/accept` verifies completed capture or selected COD and committed stock on the server. Only `PENDING_ACCEPTANCE` becomes `CONFIRMED`. Network uncertainty requires a new read rather than assuming success.
- POST `.../orders/{supplierOrderId}/reject` requires 12–200-character reason. The UI explains that only **unpaid and non-COD-selected** pending orders qualify; server refuses a financial commitment with 409. No local bypass, no automatic cancellation or refund.
- Role restrictions are UI convenience only; backend checks `ORDERS_FULFILL` again. Supplier switching clears all old data. No legacy kitchen queue, audible alarms or unsupported push/sockets.

The responsive page preserves BuildTo navy/amber source, honest status chips and refresh/empty/error states; actual Clerk device testing and PDF visual acceptance are S13 gates.
