# Supplier S01 — BuildTo visual foundation & secure V2.1 transport

**Status:** PR implementation only; this is NOT a functioning authenticated supplier app.
**Visual authority:** user-supplied 16-screen `Buildto_16_Screens_Enhanced-1 (1).pdf` and S00 `S00-UI-UX-FIDELITY.md`. The PDF is a raster customer mock and does not provide editable Figma tokens or a high-resolution brand asset. Centralized proposed colors/geometry require visual review before S02.

## Delivered in S01

- Shared BuildTo tokens, light ThemeData, Material accessibility defaults and rounded buttons/cards: `lib/v21/design/buildto_theme.dart`.
- Reusable branded mark, primary button, panels, status pills, section heading, skeleton, responsive max-width: `lib/v21/design/buildto_components.dart`.
- Five-tab supplier shell (Home, Orders, Catalog, Stock, More) styled to match the PDF's navy/white/orange composition. All tabs navigate, but protected content correctly shows **account connection required** instead of fake inventory/order data: `lib/v21/screens/supplier_shell.dart`.
- Strict V2.1 API-origin config, auth-token dependency injection (no legacy fallback), safe DTO envelopes, status/request ID handling, typed errors, precise idempotency/If-Match propagation and no automatic POST retry: `lib/v21/api/supplier_v21_api.dart`.
- Typed `/api/v2/me` identity and supplier role projections. Unknown roles and malformed/duplicate memberships **fail closed**: `lib/v21/api/supplier_v21_models.dart`.
- Widget/transport/model tests and a dedicated targeted CI workflow.

## How to run the isolated visual preview

`cd apps/vendor_app`  
`flutter pub get --enforce-lockfile`  
`flutter run --dart-define=BUILDTO_SUPPLIER_V21_PREVIEW=true`

The existing legacy app remains the default in this PR to avoid silently exposing a preview as a live supplier app. The preview intentionally does **not** start the old restaurant push/sockets/auth/financial controllers. Do not use it to fulfill actual orders.

V2.1 transport accepts a **server origin** through `--dart-define=BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com` and refuses untrusted HTTP in release. No Clerk keys or server secrets are embedded in the preview; S02 must pass verified active Clerk tokens via the injectable token provider. Live /me data is not loaded in this preview.

## UI fidelity references

| S01 component | PDF page |
| --- | --- |
| BuildTo brand/nav/card palette | 1, 8, 13 |
| Large dark-navy hero with orange accent | 1 |
| Product/warehouse action cards | 2, 3, 11 |
| Status chips and clear progress/success colors | 6, 7, 8, 10 |
| Standardized large navy primary CTAs | 2–6, 15 |
| Honest permission and empty-state messaging | Supplier adaptation; not a customer mock action |

The top banner with page numbers and fake device clock in the PDF are **not** app UI. No sample prices, ratings, order numbers or paid/refunded success claims are shipped.

## Quality gates

`dart format --output=none --set-exit-if-changed lib/v21 test/v21`  
`flutter analyze --no-pub lib/v21 test/v21`  
`flutter test --no-pub test/v21`  
`flutter build bundle --debug --no-pub --dart-define=BUILDTO_SUPPLIER_V21_PREVIEW=true`

- Tests: five-tab interaction and state gating, 320/360/393/412-pixel layouts, 1.5× text-scale smoke, forbidden unauthenticated calls, safe API origins, idempotency headers, 409/429/timeout contracts and fail-closed membership DTO.
- Visual golden snapshots need approved font/logo and capture pipeline. This PR tests responsive layout rather than claiming pixel-perfect matching from low-resolution PDF. The next PR should not treat it as final sign-off on custom artwork.
- Legacy baseline CI has known customer Flutter and terminology failures unrelated to S01; do not bypass them or claim they passed.

## Out of scope until explicitly approved

- S02: native Clerk sign-in, account switching, server-authenticated memberships and real business reads.
- S03 onward: onboarding, catalog changes, real inventory/orders/fulfillment, payouts, returns, supplier documents.
- Media upload, push/device registration, database migrations, API modifications, production deployment, and screenshot-based stakeholder signoff.

**Merge is not product completion:** S01 creates a tested visual and API foundation. The real app remains behind the staging preview switch until the later feature series is connected and accepted.
