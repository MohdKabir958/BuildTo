# S06 — BuildTo Supplier Warehouses & Inventory

This stage replaces the **Stock** placeholder only for a verified, approved supplier. The active supplier ID comes from S02 Clerk and live database membership; the V2.1 server checks permissions for every request.

## Backend contract

- GET/POST `/api/v2/suppliers/:supplierId/inventory/warehouses`; PATCH `/warehouses/:warehouseId`
- GET `/balances` (bounded 200) and `/warehouses/:warehouseId/movements` (bounded 100)
- POST `/adjustments` and `/transfers` with one secure `Idempotency-Key` per user intent, exact quantity strings, positive receipt/negative damage, meaningful reason and current `expectedVersion` of each balance.
- Warehouses start inactive. Only the backend can activate, reject stock below committed reservations, create a missing balance or commit paired transfer movements.
- The UI explicitly labels bounded samples and never presents old stock after failed authorization or an inconsistent DTO. A network failure after POST may have committed: user must reconcile/refetch, not generate another key and blindly repeat.
- OWNER, MANAGER, INVENTORY have write controls; all supplier roles may read. No local stock calculations or fake numbers.

## Acceptance

Read-only viewing, warehouse creation/activation, adjustment, transfer, movement history, conflict/403 fail-closed behavior, 320px layout and exact decimals must be verified against the user-approved BuildTo navy/amber source. Real Clerk device and approved supplier UAT remain release gates. No migrations and no legacy Grozo routes.
