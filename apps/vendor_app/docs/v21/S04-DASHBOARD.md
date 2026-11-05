# Supplier S04 — real bounded BuildTo dashboard

## Design
BuildTo's approved supplier adaptation of the 16-screen customer PDF: dark navy #002B5B hero, amber #F59E0B primary action, highly readable business-at-a-glance cards, real recent-order statuses, accessible quick links, five-tab navigation, and responsive 320/360/393/412 mobile layouts. No legacy Grozo restaurant metrics, imagery, sound or socket timers.

## Source of truth — three or four real API reads
Only after S02 has verified the current Clerk session and active approved supplier membership:
- GET /api/v2/suppliers/{supplierId}/orders — up to 100 latest supplier-order rows. Compute **awaiting acceptance**, **in fulfillment** statuses and show up to five recent order statuses, no invented public number, fake financial amounts or client-approved orders.
- GET /api/v2/suppliers/{supplierId}/listings — up to 100 latest non-deleted listings. Count only status APPROVED AND active as 'Published listings', not every draft.
- GET /api/v2/suppliers/{supplierId}/inventory/warehouses — up to 100 owned warehouses; count only active.
- GET /api/v2/suppliers/{supplierId}/rfqs — only for OWNER, MANAGER, CATALOG roles that have RFQ_QUOTE, and only open current invitations. INVENTORY, FULFILLMENT, FINANCE and VIEWER never send this permission-restricted request. An unavailable RFQ section is hidden, **not** shown as zero.

Every read is issued by the same injected native Clerk-token-backed V2.1 HTTP client. The backend independently verifies PostgreSQL membership on each route. No new endpoint, migrations, DB changes, queue, Redis or Kafka.

## Accuracy, permissions, and privacy
- These are **bounded list snapshots**, not exact all-time aggregate metrics. If a list is saturated at 100 entries, each derived count displays a trailing '+' (including zero matches), to indicate a lower bound. The explanation remains visible.
- Do not sum paise/currency totals from placed orders: those are not captured funds, net revenue, settlements or bank credits. Do not sum stock across different units, or pretend to have a low-stock threshold; use only actual statuses.
- Unknown server statuses, malformed/duplicate records, foreign supplier listings/warehouses, invalid UUIDs, invalid dates, and any failed endpoint **fail closed**. A network failure clears the previous snapshot and shows retry/recheck, never fabricated zeros.
- Clearing permissions, switching business, changing Clerk session or changing role removes the dashboard subtree. A stale asynchronous response is ignored after unmount/reload. No local token or dashboard cache persists across accounts.
- Pull-to-refresh and explicit hero refresh re-read the three/four scoped APIs. No fictional live push or auto-updating realtime claims.
- Dashboard shortcuts navigate to existing Orders/Catalog/Stock/More tabs; feature tabs still state their later PR scope. These shortcuts do **not** implement S05–S13 business mutations.

## Verification
Dedicated S04 workflow: locked Flutter packages, strict Dart format after initial review, static analysis, S01–S04 tests, isolated staging bundle. The S01/S02/S03 workflows also trigger for the same Flutter V2.1 paths.

Tests must cover genuine bearer headers, owner vs viewer/finance RFQ permissions, bounded 100+ semantics, unpublished listings/inactive warehouses, 401/403 and foreign-supplier rejection, unknown or duplicate server rows, refresh hiding stale figures, mobile 320/360/393/412px, 1.5x text scaling and real tab navigation. No fake revenue shown.

### Staging limitations
This is an **opt-in** Flutter V2.1 app. The existing Render staging branch is separately managed and Clerk native token audience/azp and live approved membership UAT are not guaranteed by mocked CI. Dashboard's three existing read routes were implemented in earlier V2.1 backend PRs; the RFQ endpoint is role-restricted. No staging deployment or production cutover is included.

S05–S13 remain outside S04, requiring an explicit next "go ahead". UI raster fidelity needs final visual sign-off with approved high-resolution design assets before production release.
