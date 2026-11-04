# BuildTo V2.1 Admin Portal — PR A00: contract audit and implementation gates

Audited on 2026-11-04 against `main`, using:
- `backend/v21/openapi.json` v0.16.0 — **119 paths**; do not assume an undocumented route exists.
- `backend/v21/src/permissions.ts` — role/permission rules, enforced server-side.
- `backend/prisma/v21/schema.prisma` — existing 72-model canonical database schema.
- `web/super_admin/src/App.tsx`, `src/services/api.ts`, `src/auth/ClerkAdmin.tsx`, `src/components/`.

**Non-negotiable:** Build the admin portal against `/api/v2`. No schema edits, no new migration, no writes to Neon production, no legacy `/api/v1` fallback. Only the approved V2.1 backend routes may access the existing staging database.

## What can actually be reused

| Reuse with review | Needs replacement |
|---|---|
| React 18, Vite 5, TypeScript, Tailwind and Vitest setup | Monolithic Grozo `App.tsx` (legacy orders, riders, restaurant state) |
| ClerkProvider / Clerk hooks in `src/auth/ClerkAdmin.tsx` | Its old `validateSession()` call, `ADMIN`-only role assumptions, Grozo messages |
| `ErrorBoundary`, toast, confirmation dialog, icons, forms, accessible responsive sidebar | Sidebar's grocery categories, store maps, rider dispatch, Grozo naming |
| Reusable table, drawer, status chip, pagination and empty-state patterns | `src/services/api.ts` (legacy `/api/v1`, `/api/admin`, passcode login and legacy DTOs) |
| Relevant catalog, finance, operations visual layout patterns | Legacy finance/order status transitions, vendor/rider actions, Socket.IO assumptions |

**Do not couple new modules to the existing 43 KB legacy API service.** Create `src/v21/` adapters and progressively replace the app entrypoint after the new authentication/permission foundation is tested.

## Exact backend API inventory and PR dependencies

`/health`, `/ready`, `/api/v2/system`, `/api/v2/me` and `/api/v2/admin/access` exist.

| Admin module (PR) | Already implemented in /api/v2 | Required bounded backend API addition (no migration) |
|---|---|---|
| A02: Clerk and RBAC | `GET /me`, `GET /admin/access`; signed webhook | Owner bootstrap procedure for a synchronized Clerk User with explicit AdminMembership; **never** a public admin-creation route |
| A04: admin team | AdminMembership exists; `TEAM_MANAGE` permission defined | List, grant/change and revoke *existing provisioned* admins; independent OWNER checks and audit events. Invite-by-email requires a carefully scoped Clerk invitation workflow, not a new DB table |
| A05–A06: supplier onboarding | Supplier, SupplierMember, SupplierDocument, MediaAsset exist; `SUPPLIER_APPROVE` defined | Admin supplier list/details, registration/verification, document review and reasoned approval/rejection/suspension with audit; avoid bypassing signed user provisioning |
| A07: catalog | Category/product/brand creation, product review, listing pending/review already exist | Admin listing of **inactive** categories/brands/products if public active-only endpoints are insufficient |
| A08: delivery/promotions | Admin delivery city/area create/update and promotions list/create/update exist | Admin list of **inactive** city/service areas (public endpoints expose active-only); use existing data/models |
| A09: dashboard | Data present across Supplier, PurchaseOrder, SupplierOrder, ReturnRequest, Settlement, SupportCase | Bounded aggregate read endpoint with explicit metric definitions, timestamps and role-aware visibility |
| A10: global orders | Customer-owned and supplier-owned order endpoints exist | Read-only admin global order list/details, server-filtered/paginated, supplier split, funding and shipment status; no unauthorized order mutation |
| A11: support and returns | Admin case list/read/update/messages; return review; review moderation already exist | Extend only if a confirmed admin workflow cannot be implemented with current endpoints |
| A12–A13: finance | Existing COD, settlement, refund, payout, reconciliation and attestation routes | No new execution endpoint; use existing independent reviewer controls and provider evidence |
| A14: audit | AuditEvent table exists; `AUDIT_READ` permission defined | Read-only paginated admin audit list/detail, redacted to remove PII, secrets and raw provider payloads |
| A15: staging | Render V2.1 `/ready` is live | Frontend hosting, HTTPS origins, CORS, Clerk parties, smoke tests; backend stays staging-gated |

## Server-authoritative role contract

| Role | Backend permissions relevant to the portal |
|---|---|
| OWNER | All currently defined admin actions |
| OPERATIONS | ADMIN_READ, SUPPLIER_APPROVE, SUPPORT_MANAGE, SERVICE_AREA_MANAGE, PROMOTION_MANAGE |
| CATALOG | ADMIN_READ, CATALOG_APPROVE |
| FINANCE | ADMIN_READ, FINANCE_MANAGE |
| SUPPORT | ADMIN_READ, SUPPORT_MANAGE |
| AUDITOR | ADMIN_READ, AUDIT_READ |

The UI may hide a forbidden action for ergonomics, but the API must *always* re-check access on the current database membership and deny forged requests. Admin assignment/revocation and finance operations must use existing audit logs. Never make Clerk metadata alone authoritative for backend roles.

## Security and data handling rules

1. Browser obtains a short-lived Clerk session token with `getToken`; send `Authorization: Bearer …` to the explicit HTTPS V2.1 API origin. Never store JWTs in localStorage or log tokens.
2. Clerk authorized parties and backend CORS must include only the exact deployed frontend HTTPS origin(s). Remove the temporary backend-origin placeholder when frontend staging is configured.
3. Handle 401 as reauthentication, 403 as insufficient authorization, 404 as not-found (including cross-supplier resources), 409 as version/idempotency conflict, 429 as throttling, 5xx as retryable **only for safe reads**. Never blindly retry money-moving mutations.
4. All financial values are exact integer paise strings or explicit decimal strings; do not use floating-point arithmetic or display payment *intent* as settled cash.
5. Use page limits, server-side filters, safe sort keys, no unbounded joins; respect role-aware masking of contact, banking, audit and GST data.
6. Confirm destructive/sensitive actions, state explicit provider status and evidence; never offer live refunds or automatic payouts, which V2.1 explicitly disables.
7. Add accessible labels, keyboard behavior, loading, empty, error and conflict states; test role-based navigation and direct URL access.
8. No new DB tables, Prisma schema edits, migrations, microservices, Redis, Kafka or distributed infrastructure for the admin plan.

## PR sequence and minimum gates

- **A00 (this PR):** existing contract inventory, missing endpoint list, review of legacy UI, executable OpenAPI smoke gate.
- **A01:** V2.1 app shell, BuildTo navigation, layout, reusable UI primitives and route-level placeholders; no live business mutations.
- **A02:** Clerk sign-in, bootstrap admin, live `GET /api/v2/me` and `GET /api/v2/admin/access`, denied states and role-aware routing.
- **A03:** typed `src/v21/apiClient`, data validation, pagination, request IDs, auth error handling and safe mutation patterns.
- **A04–A08:** role-aware team, supplier registration/review, catalog and service-area modules; minimal new backend admin routers only where absent.
- **A09–A11:** real dashboard metrics, global order monitoring, operational support and review queues.
- **A12–A13:** finance UI reuses the existing audited routes and maker-checker checks; no synthetic provider success.
- **A14:** audit and security review; redaction, accessibility and negative authorization coverage.
- **A15:** staged frontend build/deploy, exact Clerk/CORS configuration, full user journeys, smoke and handover.

Each feature PR: TypeScript build, relevant Vitest tests, permission-negative tests, Prisma-backed API integration on disposable PostGIS when backend touched, unchanged 72-model canonical schema parity and live staging `/ready`. Do not merge green UI with red backend security tests. No existing database reset/migration.
