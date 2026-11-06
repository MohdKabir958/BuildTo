# S10 — Supplier-led shipments and customer-issued handover OTP

**API:** supplier shipments are child resources of verified supplier orders. OWNER/MANAGER/FULFILLMENT may plan a shipment from approved active warehouse allocations, pack, dispatch, mark out-for-delivery and verify customer-issued OTP. All reads require current SUPPLIER_READ, writes require ORDERS_FULFILL.

- GET `/api/v2/suppliers/{supplierId}/orders/{supplierOrderId}/shipments` returns bounded 100 shipment records.
- POST `.../shipments` accepts 1–40 exact decimal order line quantities, active warehouse ID and optional carrier/tracking info. A new cryptographic idempotency key is minted once per form; backend must confirm valid payment/COD and committed unallocated warehouse reservations. No fake stock or local delivered balance.
- POST `.../shipments/{id}/pack`, `/dispatch`, `/out-for-delivery` enforce PLANNED→PACKED→DISPATCHED→OUT_FOR_DELIVERY.
- POST `.../shipments/{id}/handover` accepts only customer-issued six-digit OTP, never supplier-generated. Backend verifies five-minute expiry and rate limits; only verified handover yields DELIVERED. Emergency exception requires *independent admin approval*, with no supplier bypass in UI.
- No rider app, no tracking stream or GPS, no local shipped/delivered transition, no finance settlement assumption. Network-uncertain mutations are reconciled by re-fetch rather than assumed successful.

Validation: exact decimal, scoped results, forbidden state, unknown OTP, Android Clerk staging bundle, customer/supplier device handover UAT and PDF design comparison remain release gates. No production-readiness claim.
