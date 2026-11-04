# BuildTo V2.1 admin portal — implementation roadmap

**A00 baseline contract:** backend V2.1 OpenAPI 0.16.0 has 119 documented paths; 41 under `/api/v2/admin/`. Existing React admin has ~150 source files, 52 test files, and legacy Grozo client coupling.

**Target:** Keep one React/Vite/TypeScript frontend at `web/super_admin/` and one modular Express backend at `backend/v21/`. Neither frontend convenience nor admin onboarding justify introducing a second backend or changing the existing 72-table Prisma V2.1 schema. All five missing admin capabilities use existing V2.1 tables; **no migrations** in this admin series.

| PR | Scope | Dependencies | Done when |
| --- | --- | --- | --- |
| A00 | Existing UI/API reuse audit, contract freeze, PR/role/fixture matrix | none | Every admin screen is mapped to an existing or explicitly scheduled endpoint |
| A01 | New BuildTo shell under `src/v21/`; responsive menus and real empty states | A00 | Legacy client not invoked; UI and contract tests pass |
| A02 | Clerk-only sign-in, `/me` + `/admin/access`, server-authoritative RBAC, safe owner bootstrap runbook | A01 | Unprovisioned or revoked users cannot access workspace |
| A03 | Typed V2.1 fetch client, retries, conflict handling, paise/Decimal formatting, request IDs | A02 | 401/403/409/429 and idempotency tested |
| A04 | Admin membership team APIs and screens | A03 | Owner-only grants, last-owner lockout, audit events |
| A05 | Supplier onboarding/document-review backend APIs | A04 | Role-checked review transitions, current schema only |
| A06 | Supplier applications and approvals screens | A05 | Complete authentic supplier review journey |
| A07 | Category/brand/material/listing review screens | A06 | Version conflicts, decimals and CATALOG role enforced |
| A08 | City/area/promotions and configuration screens | A07 | Active/inactive semantics correct |
| A09 | Read-only operational statistics endpoint and dashboard | A08 | Exact queue counts reconcile to DB fixtures |
| A10 | Global order and shipment admin read endpoints/screens | A09 | Safe DTO, role checks, no impersonation |
| A11 | Support, returns and review moderation | A10 | Private notes and refund distinctions preserved |
| A12 | COD/GST/settlement admin finance views | A11 | Maker/checker status correctly represented |
| A13 | Refund and payout evidence flows | A12 | No automatic provider POST; third-party bank attestation separate |
| A14 | Audit/reporting API, security and accessibility regression | A13 | Bounded reads and role coverage, no private data leaks |
| A15 | Staging UAT, deployment, exact CORS/Clerk origin and rollback | A14 | Fully verified staging console with production disabled |

## Invariants

1. `backend/prisma/v21/schema.prisma` and three reviewed migration SQL files remain unchanged. Do not run `prisma migrate reset`, create schema changes or use legacy migrations.
2. New backend reads/writes live in `backend/v21/`, use `requireIdentity`, `requireAdminPermission`, bounded explicit DTOs and existing `AuditEvent`; no raw database responses or bank details.
3. Clerk `getToken()` is obtained in memory; no legacy admin passcode, bearer localStorage, client-asserted role or generic supplier API impersonation.
4. V2.1 openAPI paths are source of truth, never rename `/api/v1/` endpoints by string substitution.
5. Finanz actions must reflect provider evidence, real money movement and maker/checker controls. A request or payout intent is *not* a completed transfer.
6. Every PR has its own build and regression evidence, and staging/production DBs are not used as test fixtures. Use disposable local PostGIS.

## Manual prerequisites (when implementation reaches A02/A15)

Staging must use a real HTTPS admin origin in both Render CORS and Clerk authorized parties; temporary Render API self-origin must be replaced. An OWNER must be provisioned via a controlled, audited backend operation; signing up in Clerk does not grant admin permissions. No credentials or database URLs belong in frontend source.
