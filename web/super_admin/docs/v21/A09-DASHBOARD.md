# Admin A09 — Database-authoritative operational dashboard

`GET /api/v2/admin/overview` requires `ADMIN_READ` on the active database AdminMembership.

Snapshot returns `asOf`, rolling preceding 7-day start, counts from real Supplier, SupplierListing, PurchaseOrder, SupplierOrder, SupportCase, ReturnRequest, Shipment, RefundRequest and PayoutTransfer tables. No mock totals, second-order joins, caches or background aggregates. Counts are **not** revenues or promises.

Only OWNER and FINANCE see `financeEvidence` from PaymentAttempt rows with `status=CAPTURED` AND `verifiedAt IS NOT NULL`. Value is a **decimal integer paise string**. It is explicitly **provider capture evidence, not platform revenue, settlement, payout, COD or verified bank cash**. Others receive `financeEvidence:null`.

The UI shows live loading/errors, a timestamp, and does not persist snapshots or retry money execution. No extra database table, migration, Prisma schema edit or worker.

Testing: role permission denials, finance visibility, API contract path parity and React offline states. Staging integration remains required.
