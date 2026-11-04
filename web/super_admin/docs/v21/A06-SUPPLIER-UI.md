# Admin A06 — Supplier applications UI

## Shipped surface
- OPERATIONS/OWNER-only supplier list with backend status filtering, keyset pagination, explicit refresh and truthful empty/error states.
- Selected supplier business, GST, contact, owner membership, evidence metadata, document statuses and reviewer notes.
- Reason-required approval, rejection, suspension and document review actions, including self-review denial in the UI (server also enforces it).
- No supplier impersonation, stock writes, fabricated approval counts or customer-only APIs.

## Trust boundary and launch gap
A05 currently supports **linking only pre-provisioned private evidence assets**. It has no image/PDF upload or secure document-content preview endpoint. A06 does not offer downloads or raw object keys. Before an actual compliance reviewer marks evidence VERIFIED, the organization must securely inspect the original via an approved outside-the-console process, and record the reason. A complete web upload+private KYC viewer is a separate security-relevant feature; **A06 is not equivalent to an end-to-end document upload implementation**.

Supplier-facing application creation belongs to the upcoming Flutter app; A05 provides its API already. Stage actual app and private-media integration before claiming onboarding fully operational.
