# Splyzo customer V2.1

The default customer entry point now opens the construction marketplace. The
legacy experience remains available with `BUILDTO_CUSTOMER_V21=false` for
regression testing. Customer V2.1 does not initialize legacy grocery providers,
legacy token storage, demo orders or legacy push registration.

## Run the connected Android staging app

Use the repository-pinned Flutter 3.44.9 / Dart 3.12.2. Native Clerk uses the
existing shared Android SDK bridge and its owned publishable-key configuration.
Do not use a fixture Clerk key for user acceptance.

```sh
cd apps/customer_app
flutter pub get --enforce-lockfile
flutter run \
  --dart-define=BUILDTO_CUSTOMER_V21=true \
  --dart-define=AUTH_MODE=clerk-test \
  --dart-define=BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com
```

Debug browsing defaults to the existing staging API. Sign-in requires the
correct native Clerk configuration. Public browsing works without signing in;
private requests require a current SDK session and a backend-provisioned active
User. No supplier membership is required for customer actions.

Release builds require `AUTH_MODE=clerk`, an explicit HTTPS API origin and
`BUILDTO_V21_PRODUCTION_API_HOST` matching that origin. Staging/test/local hosts
are rejected for release. These checks do not grant production approval.

## Shared workflow and API ownership

| Customer feature | Existing shared backend |
| --- | --- |
| Catalog, supplier offers and storefronts | `/api/v2/catalog/*` |
| Versioned cart | `/api/v2/cart` and `/api/v2/cart/lines/:listingId` |
| Address, site and project ownership | `/api/v2/me/addresses`, `/me/sites`, `/me/projects` |
| Stock, tax and delivery quote | `/api/v2/checkouts` |
| Order placement and status | `/api/v2/checkouts/:quoteId/place`, `/api/v2/orders` |
| Payments and cancellation | `/api/v2/orders/:orderId/payments` |
| Cash on delivery eligibility | `/api/v2/orders/:orderId/cod` |
| Supplier shipments and handover OTP | `/api/v2/orders/:orderId/shipments` |
| Bulk requests, invitations and quotations | `/api/v2/rfqs/*` |
| Supplier-issued invoices and credit notes | `/api/v2/orders/:orderId/invoices` |
| Returns and private evidence | `/api/v2/orders/:orderId/returns`, `/api/v2/media` |
| Refund reconciliation read model | `/api/v2/orders/:orderId/refunds` |
| Delivered supplier-order reviews | `/api/v2/orders/:orderId/reviews` |
| Saved offers and inbox | `/api/v2/me/wishlist`, `/me/notifications` |
| Admin-visible support conversations | `/api/v2/support/cases/*` |
| Published policies | `/api/v2/content/:slug` |

No customer database or duplicate order system is created. Customer purchases
become the same PurchaseOrder/SupplierOrder records handled by the supplier app
and admin. RFQs explicitly invite approved suppliers; they are not assumed to
broadcast automatically. The accepted quotation checkout uses the backend's
exact address/clientRequestId contract.

## Additive backend changes

- Public supplier directory returns only `id` and `displayName`, with a cursor.
- Product browsing accepts `supplierId`. Price labels include exact decimal
  `fromPrice`, `fromUnit` and `fromPriceTaxInclusive`; prices belong to the first
  available selling unit and never replace a checkout quote.
- Offers include public supplier display names.


Deploy these API changes before accepting the new app against a hosted backend.
No Prisma migration is needed. Existing supplier and admin financial execution
boundaries remain unchanged.

## UX and state safety

- Warm off-white, navy and orange palette; bundled Jakarta and Bricolage fonts;
  responsive cards, keyboard-accessible address selection and semantic actions.
- Exact decimal quantities, minimum/step/maximum controls and integer paise.
- Cart version conflicts require review. Order placement retains an idempotency
  key across uncertain retries. A refreshed quote gets a new placement key only
  when its quote ID changes.
- The payment SDK opens the provider order returned by the backend. Its callback
  never marks an order paid or calls a legacy confirmation endpoint. Pending
  payments resume an existing attempt; they do not create a fresh charge.
- Sign-out, account/session changes and access loss invalidate in-flight private
  responses and dispose the navigator, including private sheets/detail routes.
- Images load from the configured API's public catalog image route only.
- Return attachments use owned private media uploads, bounded at 10 MiB each.
- Notifications are in-app records. Push dispatch and GPS tracking are not
  invented when those backend capabilities are disabled or absent.

## Verification

```sh
flutter analyze --no-pub lib/v21 test/v21
flutter test --no-pub --concurrency=2 test/v21
flutter test --no-pub --concurrency=2
flutter build bundle --debug --no-pub \
  --dart-define=AUTH_MODE=clerk-test \
  --dart-define=BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com
```

Set `SPLYZO_CUSTOMER_CAPTURE_DIR` to an absolute local directory to capture the
actual widgets with isolated fixture data. These captures are design QA, not
proof of a live payment, login or shipment. Real-device Clerk, file-picker,
provider/webhook, supplier delivery and admin reconciliation acceptance are
required before a production launch.
