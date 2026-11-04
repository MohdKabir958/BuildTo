# BuildTo V2.1 Admin Portal — A00 interface audit and implementation boundary

**Status:** Initial admin PR; contract/client foundation only. This PR does not launch the new portal or change the live backend.

## Source-of-truth

- Existing frontend: `web/super_admin` (React 18, Vite, TypeScript, Tailwind, Clerk).
- New backend: `backend/v21` (modular Express server; current `/api/v2` contract).
- Published contract: `backend/v21/openapi.json` (119 paths at V2.1 release candidate 0.16.0).
- Current staging: `https://buildto-v21-staging.onrender.com`; `/health`, `/ready` and `/api/v2/system` respond successfully.
- Legacy UI `src/services/api.ts` still calls Grozo `/api/v1` / `/api/admin`, so do not plug it directly into the new API.

## Non-negotiable guardrail

**Do not modify `backend/prisma/v21/schema.prisma` or any V2.1 migration file, and do not execute a Neon migration for this admin work.** The five identified admin needs can use the existing 72 V2.1 application models:

| Feature | Existing tables | Needed backend change |
|---|---|---|
| Team roles and access | `User`, `AdminMembership`, `AuditEvent` | Owner-only team read/grant/revoke routes; explicit initial-owner provisioning with safe audit |
| Supplier onboarding and review | `Supplier`, `SupplierDocument`, `SupplierMember`, `MediaAsset`, `AuditEvent` | Permissioned queues and review state transitions |
| Global order visibility | `PurchaseOrder`, `SupplierOrder`, `Shipment`, `PaymentAttempt`, `CodCollection` | Paginated **read-only** cross-supplier admin projections |
| Dashboard summaries | Existing orders, suppliers, listings, returns and support tables | Bounded aggregate read endpoints, documented time windows |
| Audit history | `AuditEvent` | Paginated, redacted, permission-scoped read endpoints |

Write new backend routes only when the corresponding admin PR needs them. Enforce permissions and revalidation **inside backend services**, never just by hiding frontend tabs. Use Prisma exact selects and explicit DTOs; no raw secrets or full bank account numbers.

## Existing API to consume without backend changes

- `GET /api/v2/me`, `GET /api/v2/admin/access`.
- Catalog discovery; `/api/v2/admin/catalog/categories`, `brands`, `products`, `listings/pending` and listing `review`.
- Admin delivery `cities` and `areas`, admin promotions.
- Admin support cases, returns, reviews, shipment exception approval.
- Admin finance supplier summaries, COD review, settlements, posted journals, refund queues/review/reconciliation, beneficiary approval and payout intent/status/bank-attestation endpoints.

Not all supplier actions belong in an admin console: stock adjustments and supplier shipment progression require active *supplier* membership, even for an admin. Do not bypass this with unrestricted admin impersonation.

## Frontend migration rules

1. Prefer reusing clean, accessible design-system components, table controls, modal/focus management and Clerk React sign-in.
2. Use `src/v21/apiClient.ts` for V2.1 operations. It accepts an explicit origin and a token provider from Clerk, never falls back to legacy localStorage, and rejects `/api/v1` URLs.
3. Treat `{data, requestId}` as the transport envelope; display structured errors. Define concrete DTO types as each page is implemented, and verify them against actual route responses.
4. Money quantities must use string decimal paise and exact decimal quantity fields, not floating-point calculations. No automatic money-movement buttons.
5. No Socket.io dependency for V2.1: the new backend is HTTP-based. Use bounded explicit refresh/polling where needed.
6. Keep the old portal running until the V2.1 screens and routes are integrated, then remove legacy UI dependencies in a separate reviewed cleanup PR.
7. Before the browser can call staging: deploy the frontend under its real HTTPS origin, update Render CORS and Clerk authorized parties to exactly that origin, and verify authentication/403/404 behavior. Never use the backend URL as the assumed frontend origin after deployment.

## PR sequence

- **A00:** verified endpoint/permission matrix; isolated Clerk-token API client with unit tests (this PR).
- **A01:** BuildTo admin shell, navigation, accessibility and route boundaries (reuse existing presentation components).
- **A02:** Clerk-only login, admin introspection and secure initial OWNER provisioning.
- **A03:** module-specific typed API DTOs, session/error UX and predictable mutation controls.
- **A04:** admin team routes + owner access management UI.
- **A05:** supplier/document review API with audit and tests.
- **A06:** supplier onboarding/review/suspension UI.
- **A07:** product/category/brand/listing-review UI against existing routes.
- **A08:** city/service-area and promotion UI against existing routes.
- **A09:** bounded admin metrics endpoint + dashboard UI; use accurate KPI labels.
- **A10:** global order read projections + monitor screens.
- **A11:** existing support/return/review moderation UI.
- **A12:** COD, GST and settlement review UX with independent approval safeguards.
- **A13:** refund, payout, beneficiary and bank-attestation UX without direct money transfer.
- **A14:** audit list API/UI, security hardening and role-level test matrix.
- **A15:** end-to-end staging deployment, smoke/UAT and legacy UI retirement gates.

**Each PR:** tests for authorized and unauthorized use, empty/loading/error states, backend feature gates, no schema drift, staging build and explicit acceptance review. No Redis, Kafka, separate admin API service or new tables.
