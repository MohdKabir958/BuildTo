# Splyzo supplier workflow review — 12 November 2026

The implementation extends draft PR #62. Local automated checks pass; this is not a production launch or a real-device acceptance signoff.

## Problems corrected

| Area | Previous behavior | Result |
| --- | --- | --- |
| Authentication | Missing JWT authorized-party claim was accepted regardless of native-session configuration | Missing `azp` requires explicit native opt-in; foreign and malformed origins fail closed |
| Identity contacts | Lazy provisioning could copy unverified provider contacts | Only verified primary contacts are provisioned; local suspension remains authoritative |
| Session/supplier changes | Replacing the home widget could leave a private modal/detail route visible | Session, supplier, role or access-stage changes dispose the old navigator and its overlays |
| Supplier approval | Business/GST evidence and independent-review checks were absent | Related supplier personnel cannot review their application; current independently verified business/GST documents are required |
| Documents | Applicants had to paste an already-provisioned media UUID; administrators could only see metadata | Native file selection and private upload; authenticated, integrity-checked owner/reviewer downloads in admin |
| Catalog | A newly created master product was immediately active | New master products remain inactive until explicitly published |
| Product images | No media relation or publication/read boundary | Separate administrator-created catalog images, public only when linked to an active product/category; KYC evidence cannot be published |
| RFQ submission | Flutter expected an extra `quote` wrapper absent from the real backend response | Client consumes the actual quote DTO; successful submissions no longer fail during response parsing |
| Freight | Only flat rates were supported; richer rates could look flat in supplier UI | Configurable truck tariffs and server-calculated RFQ freight, verified product conversions, capacities, trip counts and immutable quote/order snapshots |
| Projects/sites | Models existed without customer CRUD | Owned, paginated project/site APIs; cross-account references denied, archival preserves history, inactive projects cannot be used at checkout |
| Content/devices | Missing API contracts | Versioned/audited plain-text content publishing; encrypted, bounded, account-scoped device registration with explicit push-disabled status |
| UI consistency | Mixed BuildTo/Splyzo labels, inherited font inconsistencies and technical copy | Splyzo labels, explicit typography, clearer product wording and honest tariff/status labels |

The original PR's configurable commission, wishlist, notification inbox and durable customer-notification dispatcher remain included.

## Validation

| Check | Result |
| --- | --- |
| Backend V2.1 compilation and Prisma generation | Passed |
| Canonical schema parity | Passed; 72 models, 35 enums; immutable original baseline retained |
| Fresh disposable PostgreSQL 17/PostGIS 3.5 migration and catalog verification | All six migrations applied; passed |
| Full backend integration suite | **199 passed, zero failed** |
| Targeted completion tests after device re-registration adjustment | **8 passed, zero failed** |
| Legacy backend compilation | Passed separately |
| Flutter SDK | Repository-pinned **3.44.9 / Dart 3.12.2** |
| Supplier Flutter analysis | No issues found |
| Supplier Flutter regression suite | **117 passed, zero failed** |
| Supplier API adoption manifest | **52 operations / 12 groups** match OpenAPI; validator tests 7/7 |
| Admin supplier review tests | 3/3 passed |
| Admin TypeScript check | Passed |
| Whitespace and Dart format checks | Passed |
| Local Android bundle | Attempted; blocked by missing Android SDK in this workspace |

Backend tests exercise real disposable PostgreSQL/PostGIS transactions, permissions, stock reservations, checkout, supplier fulfillment, OTP evidence, COD, GST invoices/credit notes, refund evidence and payout reconciliation. Payment/identity provider responses are controlled test fixtures, not live transfers or live Clerk accounts. The original refund test used a GSTIN different from its supplier; that fixture was corrected while retaining the seller-identity guard.

Flutter tests cover welcome/recovery, membership selection and refresh, session loss and private-route disposal, onboarding, catalog, warehouses/stock, delivery, RFQs, orders, shipment repositories, returns/reviews and finance. Existing phone checks include 320, 360, 393 and 412 logical-pixel widths and large-text cases. Native Android Clerk bridge code was inspected; a real signed-device sign-in was not performed.

## Private visual review

The generated captures are kept as private local QA artifacts and are excluded from the public repository. Automated approval review blocked their public upload; no screenshot-sharing approval is assumed. Reproduce them with the test command below.

These are **widget-test fixtures at 393×852 logical pixels**, rendered at 2× resolution with Flutter's Roboto/Material icon fonts. Empty states and dashboard sample records are test data. They are not production screenshots, approved goldens, or proof of exact fidelity to the unavailable original 16-page design PDF. Layout, spacing, readability, status honesty and access boundaries were reviewed.

| Screen | Capture |
| --- | --- |
| Welcome | `01-welcome.png` (local QA) |
| Dashboard | `02-dashboard.png` (local QA) |
| Catalog | `03-catalog.png` (local QA) |
| Stock | `04-stock.png` (local QA) |
| Orders | `05-orders.png` (local QA) |
| Delivery | `06-delivery.png` (local QA) |
| RFQs | `07-rfqs.png` (local QA) |
| Finance | `08-finance.png` (local QA) |
| Returns | `09-returns.png` (local QA) |
| Document upload | `10-upload.png` (local QA) |

## Deployment configuration and remaining acceptance work

1. Deployment follow-up: the three pending additive migrations (supplier photos, media product images and RFQ freight snapshots) were rehearsed on an isolated staging copy and applied to the existing Neon staging branch with official Prisma. Rollback must preserve uploaded media and accepted quote/order records. The private Neon bucket passed authenticated roundtrip and denied anonymous access (403); Render environment wiring and rollout require deployment access.
2. Set `BUILDTO_V21_MEDIA_ROOT` to an absolute **private persistent volume**, never a static web directory or ephemeral deployment filesystem. File bytes are bounded, SHA256-checked and mode 0600; directories are mode 0700. JPEG/PNG uploads are decoded and reencoded, PDFs are attachment-only. The private S3 adapter also supports Neon branch storage; set the five `BUILDTO_V21_MEDIA_S3_*` variables documented in `docs/ops/PR62-DEPLOYMENT.md`. Document-malware scanning remains external.
3. Set `BUILDTO_V21_DEVICE_ENCRYPTION_KEY` to a vault-managed canonical base64 encoding of 32 random bytes when device registration is wanted. AES-256-GCM ciphertext is stored; neither raw nor encrypted tokens are returned. This change registers devices; it does **not** enable FCM dispatch.
4. Native sessions without `azp` need the deliberate `CLERK_ALLOW_NATIVE_WITHOUT_AZP=true` setting for the correct Clerk instance. Complete real-device sign-in/sign-up, MFA/recovery, token renewal, account switching, revocation, camera/files, keyboard, screen-reader and poor-network UAT. Verify the Android CI build and installed APK; no iOS native-auth acceptance claim is made.
5. Freight is **supplier-attested road distance in accepted RFQ quotations**, not automatically routed distance. KG/CUM conversion factors are administrator-managed per product/sale unit. Unknown cargo, capacities or precise radius/polygon coverage fail closed. Direct customer checkout continues to support flat rates; bulk/complex freight uses the RFQ path. No freight rates or physical conversion factors are guessed or silently defaulted.
6. Automatic Razorpay refunds and RazorpayX payouts remain **unimplemented/disabled** in the API's external execution boundary. The existing approved manual execution and read-only reconciliation paths were tested. Automatic executors, live provider/bank UAT and independent finance/release approval remain separate work; passing mocks does not complete those integrations.
7. Configure the approved commission policy before checkout. Existing release-stage restrictions, production readiness flags, bank-verification distinctions and finance separation remain intact. Hosted CI and external acceptance must be reviewed separately from this staging deployment.

## Reproduction

```sh
cd backend
npm ci
npm run db:v21:parity
npm run build:v21
# Against a newly provisioned disposable PostGIS *_test database only:
npm run db:v21:deploy-empty
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f ../architecture/buildto-schema-v2.1/sql/reference-seed.sql
npm run test:v21:api

cd ../apps/vendor_app
flutter pub get --enforce-lockfile
flutter analyze --no-pub lib/v21 test/v21
flutter test --no-pub --concurrency=2 test/v21
```

Set `SPLYZO_CAPTURE_DIR` and `SPLYZO_VISUAL_FONT_DIR` (Flutter SDK `bin/cache/artifacts/material_fonts`) to regenerate the optional fixture captures. These are review evidence, not auto-approved golden baselines.
