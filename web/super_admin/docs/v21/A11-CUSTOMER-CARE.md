# Admin A11 — Support, returns and customer review moderation

BuildTo uses its **existing** V2.1 customer care APIs; no new backend controllers, schema changes or migrations in A11.

The OPERATIONS/SUPPORT/OWNER workspace calls admin-only support case, returns and review moderation endpoints. It provides:
- Open support queue and private conversation detail. A reply can be public or an `internal:true` staff note; private notes never go to customer APIs. Resolving/closing requires a customer-visible note and the backend enforces the transition.
- Return queue with `REVIEW`, `APPROVE`, `REJECT` and a minimum 12-character note. **Support decisions do not issue GST credit notes, restock inventory, reserve refunds or transfer funds.**
- Pending supplier reviews and independent `PUBLISH`/`REJECT` moderation. Supplier personnel cannot self-review; backend checks current membership.

All three existing API queues are capped to the first 100 records and UI says that visible-item counts are **not global totals**. Full pagination would need reviewed backend modifications; no fake infinite scroll or counts.

Read-only support loading/error states, audit-backed state transitions and negative permission tests in the existing backend remain authoritative.
