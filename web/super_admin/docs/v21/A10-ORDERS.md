# Admin A10 — Read-only global order oversight

`GET /api/v2/admin/orders` (status, exact public order number, 1–50 page size, cursor) and `GET /api/v2/admin/orders/{orderId}` require an active AdminMembership with OWNER/OPERATIONS/SUPPORT/FINANCE role. CATALOG, AUDITOR and ordinary customers are denied.

Both responses intentionally omit the customer's name, contact information and shipping address; payment provider order/payment references, webhook payloads, delivery OTP secrets, shipment carrier contacts and invoice tax-identity snapshots are also omitted. No admin API for cancelling, reassigning, capturing, refunding, or directly changing shipments was added.

Order totals are **quoted order obligations** in decimal-string paise, never proof of payment; payment attempts disclose explicit statuses and verified capture evidence but no secrets. Supplier order items and shipment tracking are read-only.

Filter and keyset pagination bound response size; one order detail limits nested supplier orders/items/shipments/payments to 100 entries each. Large orders need a future explicit paginated detail contract rather than unsafe unbounded lists.

Tests verify DB truth, exact strings, forbidden role access, omission of private address/provider references and read-only client behavior. No new tables, Prisma schema edits or migrations.
