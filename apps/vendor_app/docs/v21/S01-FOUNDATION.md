# BuildTo Supplier S01 — design system, preview shell, typed V2.1 read client

**Source:** S00 audit and the user's 16-page `Buildto_16_Screens_Enhanced-1 (1).pdf`.  
**Scope:** S01 only. This is the **working Flutter UI and API foundation**, **not** live Clerk onboarding, supplier order handling, media upload, checkout or production release.  
**App:** reuse `apps/vendor_app`. No new app, database schema, backend route, infrastructure service or credential.

## What ships

1. Independent `lib/v21/design/` tokens and Material 3 theme with exact repository brand values: navy `#002B5B` and amber `#F59E0B`. Derived semantic surfaces, typed spacing, corners, typography, contrast-aware statuses and touch-target minimums. Deliberately no changes to the legacy shared Kraveo design system.
2. Reusable BuildTo building-mark/wordmark widget, content max width, outlined and raised cards, action tiles, headings, status labels, empty/loading/error pattern, primary action and step indicator.
3. A working `Home / Orders / Catalog / Stock / More` tab shell, with the PDF's header, navy + amber hero style, strong blue primary actions, clean surface cards, pictographic bottom navigation and meaningful tab behavior. The shell uses responsive grid/scroll/width constraints and accessible semantics.
4. A secure **read-only** HTTP client and typed models for canonical routes `/api/v2/system`, `/api/v2/catalog/categories`, `/api/v2/me` and `/api/v2/suppliers/{supplierId}/access`. It requires an explicit API origin and injects a future in-memory token provider for **protected** calls. No Clerk credential is fabricated, stored or copied from a legacy token.
5. Exact `BigInt` paise formatter and string-based material quantity value object. All unknown server supplier roles fail closed.
6. Opt-in preview entry, widget + network unit tests, automated Flutter analysis, Android debug preview build and reviewer-only screenshots.

## Exact launch instructions

The **existing** `KraveoVendorApp` and Grozo legacy runtime remain the default to avoid accidental cutover:

`flutter run --dart-define=BUILDTO_SUPPLIER_V21_PREVIEW=true`

For signed debug APK, see later staging release work; **S01 artifact is only debug-signed** and does not connect live supplier accounts.

The API client must be instantiated with an explicit `SupplierApiConfig.fromOrigin('https://buildto-v21-staging.onrender.com')` by a future feature, or configured through the public `BUILDTO_V21_API_ORIGIN` compile-time setting. HTTPS required for non-loopback or any release build. Neither the S01 visual shell nor legacy runtime silently calls the new API. This avoids claiming a logged-in or approved supplier exists when S02 is not implemented.

## Fidelity translation from the user PDF

| PDF reference | S01 implemented visual concept | Boundary |
| --- | --- | --- |
| Page 1: BuildTo logo, home, brand hero, section accent, bottom navigation | Vector icon/wordmark, navy + amber hero with custom construction skyline, sections, white cards and labelled 5-tab nav | Customer supplier browsing, offers and cart **not** imported |
| Page 2: white product cards with blue outlines, category grid layout | Tokenized card/overview grid and semantic interactive tiles | No customer Add to Cart, dummy prices or material stock |
| Pages 5, 7: steps and progress status | Neutral reusable `BuildtoStepIndicator` + statuses | Does not mark a shipment/approval complete without real server proof |
| Pages 6, 10, 15: success/failure vocabulary | Tone-based chip/empty/loading states | No fake “payment succeeded”, “refund initiated” or order ID |
| Page 13: profile and compact option rows | More menu with tappable informational rows | Cannot invite an admin or edit supplier profile until authorized endpoints exist |

S01 does **not** claim pixel-perfect logo matching: the provided raster PDF is low resolution and does not contain the original logo vectors/fonts. This PR uses brand.json exact colors and a new non-asset vector mark. When official logo artwork/font files are supplied, S02/S13 can replace the mark and review typography at the same component boundaries without changing operations.

## UI review gate

Automated tests verify live interactions, screen overflow on **320, 360, 393, 412 and 600dp** widths and large-text handling, and no invented currency/order metrics in the S01 shell.

The CI workflow captures `s01-home-360.png`, `s01-home-393.png` and `s01-orders-393.png` as **manual review artifacts**. Screenshots must be compared to the PDF's composition before the user signs off. CI's `--update-goldens` step **generates** review images; it is **not** a golden regression test and cannot independently certify visual parity. Once approved, the team can review and check in immutable binary baselines using a normal Git client, then make subsequent screenshot comparisons fail CI. The repository GitHub connector writes UTF-8 files only and cannot store approved PNG binary snapshots as part of S01.

## Functional/security gates

- **No fake metrics:** no hard-coded money, ratings, customer names, order IDs or inventory figures.
- **No silent privileged access:** identity read requires token provider and every supplier ID is validated. Unknown membership roles fail closed.
- **No unsafe fallback:** the S01 preview is an explicit separate app entry and does not route through Grozo `/api` or old partner sessions.
- **Network contract:** only canonical `/api/v2`, typed V2.1 envelopes and errors, request IDs; no POST mutation methods until business PRs enforce idempotency.
- **No release permission:** the compiled preview shows its limitations; publishing to Play Store or changing production login is out of scope.

## CI and local verification

Run from `apps/vendor_app` with Flutter **3.44.9** and locked dependencies:

`flutter pub get --enforce-lockfile`  
`flutter analyze --no-pub lib/v21 test/v21`  
`flutter test --no-pub test/v21 --concurrency=2`  
`flutter build apk --debug --no-pub --dart-define=BUILDTO_SUPPLIER_V21_PREVIEW=true`

Visual review-only capture:

`flutter test --no-pub tool/s01_visual_capture_test.dart --update-goldens`

CI uploads screenshot artifact and debug APK for human review, not as proof of a production-ready supplier app.

## Explicit follow-on

Only after the user says **go ahead** may S02 implement native Clerk session verification, the explicit supplier selector, staging auth origin/JWT tests, secure sign-out and database RBAC gate. Do not self-activate S02 or the rest of S03–S13.
