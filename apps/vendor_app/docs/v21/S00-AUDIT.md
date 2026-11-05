# BuildTo Supplier Flutter — S00 audit and migration baseline

**Scope:** audit/contract documents and validation only; no runtime UI changes, staging data writes, migrations or deployment.
**Source revision:** `main` commit `d4cd96f6fc4b99172019a590aff5bfb227e3f2ec`.
**Backend authority:** `backend/v21/openapi.json` version 0.24.0 (136 paths) and `backend/v21/src/permissions.ts`.
**Target:** refactor existing `apps/vendor_app/`, not create another application.
**Design authority:** user-supplied 16-page `Buildto_16_Screens_Enhanced-1 (1).pdf`; see `S00-UI-UX-FIDELITY.md`. The PDF describes **customer** screens; supplier behavior must use legitimate V2.1 supplier operations.

## Existing source inspection

| Area | Source | Findings / required migration | PR |
| --- | --- | --- | --- |
| Bootstrap | `lib/main.dart`, `session/session_controller.dart` | Restaurant-oriented routing, legacy auth gate, preview Clerk entry and old session lifecycle | S01–S02 |
| Login/application | `screens/login_screen.dart`, `signup_screen.dart`, `services/partner_auth_service.dart` | Phone/password legacy `VENDOR`, FSSAI, kitchen/restaurant categories; not construction supplier registration | S02–S03 |
| Approval | `models/partner_session.dart` | **Critical:** unknown/missing approval currently defaults to **approved**. V2.1 must fail closed | S02 |
| API transport | `config/api_config.dart`, `services/vendor_api_service.dart`, `vendor_backend.dart` | Legacy `/api`, `/auth`, `/partner`; default emulator URL `10.0.2.2:5000/api`; partial Clerk token bridge but no complete V2.1 client | S01–S02 |
| Dashboard | `screens/vendor_home.dart`, `services/order_queue_controller.dart` | Kitchen queue, prep timers, restaurant status workflow, loud incoming-order alarm | S04/S09 |
| Catalog/stock | `screens/product_inventory_screen.dart`, `services/product_api.dart`, `menu_stock_controller.dart` | Dish/menu and in-stock toggles, not construction listings, warehouse balances or exact quantities | S05/S06 |
| Delivery/location | `services/location/`, `widgets/location_*` | Restaurant location pin and rider assumptions; V2.1 uses approved supplier delivery zones and shipment transitions | S07/S10 |
| Notifications | `services/order_socket.dart`, `services/push/` | Legacy socket event/FCM device contracts; no verified V2.1 socket or mobile notification API | S09/S13 |
| Finance | `screens/settlements_screen.dart`, `payout_details_screen.dart`, `services/payout/` | Legacy finance DTOs must not imply payout verification or bank credit | S12 |
| Design system | `packages/kraveo_ui/`, `lib/widgets/ui/` | Reuse proven widget architecture only; rebrand and restyle to approved BuildTo PDF | S01 |
| Existing tests | `apps/vendor_app/test/` | Restaurant-specific suites (including `vendor_app_test.dart` and `clerk_api_tokens_test.dart`), not yet a supplier V2.1 acceptance suite | S01–S13 |

This is a code-source audit. S00 **does not claim Flutter tests pass** and does not delete or disable old tests. Legacy behavior must remain isolated until its replacement is tested.

## Migration sequence — one PR at a time

| PR | Deliverable | Mandatory check |
| --- | --- | --- |
| S00 | Audit, screen mapping, design guardrails, 50-operation contract checker | API contract unit tests + OpenAPI validation |
| S01 | BuildTo theme/tokens, navigation, V2.1 typed transport, loading/error components, responsive golden infrastructure | Approved PDF visual language; existing app preserved |
| S02 | Real native Clerk sessions, selected supplier, secure token lifecycle, role and approval checks | Real staging JWT audience/azp and membership tests |
| S03 | Business/GST supplier application, review statuses, document evidence | Private media upload/read gap resolved or honestly blocked |
| S04 | Dashboard with real bounded metrics and action cards | No fabricated orders or revenue |
| S05 | Construction listings, pricing/tiers and approval states | Version conflicts, idempotency and admin moderation |
| S06 | Warehouses, balances, adjustments and transfers | Server decimal quantities, expected versions and safe retry |
| S07 | Coverage and delivery flat-rate configuration | Admin-approved areas and truthful serviceability |
| S08 | Invited RFQs and versioned supplier quotes | Awarded quote != payment/order |
| S09 | Order queue, acceptance and permitted rejection | Funding and per-supplier order isolation |
| S10 | Shipment manifests, pack/dispatch/out-for-delivery and customer-issued OTP | Server-only OTP verification, no unsafe shortcuts |
| S11 | Returns receipt and reviews | Goods receipt != refund or restock |
| S12 | GST invoices, COD, settlements, masked beneficiary, payouts and credit notes | Exact paise and honest funding/payment states |
| S13 | Automated/physical-device regression, design goldens, staging UAT and Android release artifact | Do not present a staging APK as production ready |

## Confirmed implementation gaps

| Priority | Gap | Action |
| --- | --- | --- |
| Blocker | Native Clerk: backend disables `CLERK_ALLOW_NATIVE_WITHOUT_AZP` by default and requires explicit audience for native mode. | S02: test real signed tokens against `/api/v2/me` and supplier access; never weaken validation to force login |
| Blocker | `POST /api/v2/supplier-applications/{supplierId}/documents` **links** already provisioned private media, not raw file uploads. | S03: minimal safe private-media provision/read contract, or clearly disable upload until available; no public KYC |
| Important | No verified self-serve supplier staff invitation, business-profile edit, mobile-device push registration or supplier-support messaging operations in OpenAPI. | No fictional working buttons; add a minimal audited API only after review |
| Important | No dedicated supplier dashboard overview contract. | S04: compose bounded supplier-scoped reads or add one tested read-only endpoint if truly needed |
| Important | Current FCM/Socket.IO event contracts are legacy. | Default to foreground refresh/polling; add V2.1 notifications only with a verified backend contract |
| Financial truth | Payout intent and provider-processed payout are **not** automatic bank-credit verification (backend PR15). | S12 shows intent, provider status and bank attestation separately |
| Fulfillment truth | Received customer returns do not automatically refund or restock (backend PR12). | S11 preserves actual financial/stock status |
| Scope | V2.1 delivery belongs to suppliers; no separate BuildTo rider app (backend PR11). | S10 uses supplier-led shipment workflow, not rider tracking |

## Security and behavior rules

1. Unknown approval, role, payment, shipment or financial status **fails closed**; never use the old approval default.
2. Authorize every route using active PostgreSQL supplier membership and approved/not-suspended supplier status. Supplier switching clears cached results, queued actions, auth-sensitive widgets and old alerts.
3. Never store backend/Clerk secret keys in Flutter. Use HTTPS and runtime-safe public configuration; verify native session tokens with the V2.1 backend.
4. Use exact string Decimal and paise values; server prices, taxes, stock commitments and ledgers are definitive. Preserve idempotency keys on uncertain retries and refresh on version conflict.
5. Accept only funded or explicitly selected COD orders under server rules. A paid/COD-selected order cannot be casually supplier-rejected. Only previously committed warehouse stock may be shipped.
6. Handover OTP is **customer-issued and short-lived**; do not generate supplier-side codes or fake delivered transitions.
7. Do not carry over kitchen dishes, prep timers, fake dashboard numbers, restaurant GPS, old audio/socket contracts or restaurant stock toggles into BuildTo screens.
8. No extra database, queue, Kafka, Redis, microservice or background worker.

## S00 verification and acceptance

`apps/vendor_app/tool/v21_supplier_contract.json` records **50 HTTP method/path pairs across 10 groups**, all verified against `backend/v21/openapi.json` 0.24.0 during planning. Run:

`node --test apps/vendor_app/tool/check_v21_contract.test.mjs`
`node apps/vendor_app/tool/check_v21_contract.mjs`

The dedicated `buildto-v21-supplier-contract.yml` workflow repeats both checks for the PR. This verifies **API existence**, not that the Flutter app already calls the endpoints.

**S00 done:** the audit is reviewed, machine check passes, missing contracts have explicit owners, and the PDF styling rules are approved as future UI acceptance criteria. S00 does not deliver redesigned screens or live authenticated E2E functionality.
