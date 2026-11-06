# S11 — Supplier return receipt and moderated customer reviews

BuildTo supplier care is read-only for customer reviews. Supplier OWNER, MANAGER and FULFILLMENT may record only **physical receipt** of a previously independently approved return. Other approved supplier members may view their own orders, claims and reviews.

- GET `/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/returns` returns up to 100 supplier-owned claims; the UI selects one of the latest 100 orders instead of issuing 100+ background queries.
- POST `/api/v2/suppliers/{supplierId}/returns/{returnId}/receive` accepts empty JSON. Only independently approved/IN_TRANSIT claims may become RECEIVED; backend rechecks `ORDERS_FULFILL`.
- Physical receipt is not a refund, a credit note, a warehouse restock, or authorization to resolve a financial dispute. These are independent later controlled flows.
- GET `/api/v2/suppliers/{supplierId}/reviews/manage` reads strictly moderated customer feedback. Supplier cannot create, edit, publish, hide or reply to reviews through unsupported API routes.
- The UI never displays customer identifiers or fabricates publicly readable private evidence media links. Exact quantities, supplier/order ownership, financial status and moderation state are validated.

Automated Flutter regressions, pinned staging bundle and Android Clerk build are PR gates. A real approved return receipt and release-device UI/golden acceptance remain required before production.
