# PR 06 — Buildto V2.1 supplier inventory

This change uses the existing single Express/TypeScript backend and V2.1 PostgreSQL schema. There are no new databases, queues, Redis dependencies, microservices or migrations.

## Supplier-facing functions
- Supplier-scoped warehouse creation, activation, editing, listing and stock reads.
- Stock receipts, damage and signed corrections require an exact Decimal(18,3) string, a reason, an expected balance version and an Idempotency-Key.
- All stock writes are authorized by current active SupplierMember plus approved unsuspended supplier. Stock can never be reduced below reserved quantity.
- Stock movement entries are append-only and audit records are written in the same transaction.
- Transfers between two warehouses of the same supplier use ordered row locks and paired outgoing/incoming movement rows. Repeated identical requests replay the same result.
- Warehouse deactivation is blocked until all on-hand and reserved stock is reconciled.

## Safe checkout integration helpers
V2.1 InventoryReservation has a required foreign key to SupplierOrderItem. Therefore reservations are **not publicly exposed** until checkout PR 08. Internal database-transaction helpers:
- holdOrderItemStock: locks the order item and stock balance, validates supplier and listing, reserves exact stock only if available and if all order-item reservations fit within purchased quantity.
- releaseOrderItemStock: moves HELD to RELEASED or EXPIRED and releases the exact reserved amount, without changing physical on-hand.
- commitOrderItemStock: moves HELD to COMMITTED, deducts on-hand and reserved, appends one SALE movement, rejects expired or already released holds, and safely replays an already committed reservation.

These must be called inside a single order database transaction. No outside network calls inside the transaction. Checkout/cancellation must eventually release abandoned holds; PR 06 does not create a speculative background cleanup process.

## API routes
All routes are Clerk authenticated, supplier scoped:
- GET/POST /api/v2/suppliers/:supplierId/inventory/warehouses
- PATCH /api/v2/suppliers/:supplierId/inventory/warehouses/:warehouseId
- GET /api/v2/suppliers/:supplierId/inventory/balances?listingId=...
- GET /api/v2/suppliers/:supplierId/inventory/warehouses/:warehouseId/movements?listingId=...
- POST /api/v2/suppliers/:supplierId/inventory/adjustments
- POST /api/v2/suppliers/:supplierId/inventory/transfers

No public customer reservation or warehouse mutation routes are implemented. Stock availability on browsing remains only a preview. No production data migration or deployment.

## Review and deployment limitations
Staging still needs the officially recorded V2.1 Prisma migration baseline and live Clerk integration tests. PR 06 stacks on PR 05. Tests use a disposable PostgreSQL/PostGIS database and validate the append-only stock ledger, stock invariants and concurrent reservation behavior.
