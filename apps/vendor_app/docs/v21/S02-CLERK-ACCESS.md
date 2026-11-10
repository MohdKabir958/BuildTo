# Supplier S02 — Native Clerk authentication and V2.1 supplier permissions

**Scope:** staging-only authenticated supplier shell, no business mutations, no new endpoint, no database or schema changes. **Design baseline:** approved 16-page BuildTo reference PDF and S00/S01 UI fidelity contract. The existing Android native Clerk SDK is reused; no parallel sign-in SDK and no Flutter-stored credentials.

## What ships

- Native Clerk session via `packages/kraveo_ui/lib/src/auth/clerk_sessions.dart` and the preinstalled Kotlin bridge. Android handles passwords, MFA, recovery, token refresh and encrypted SDK persistence.
- S02 UI under `lib/v21/auth/`: BuildTo-branded sign-in, backend-verifying loading, no-approved-membership, recheck, expired/denied/offline, multi-supplier selection and sign-out. The shared Compose Clerk form uses BuildTo navy `#002B5B` and amber `#F59E0B` **only** for the supplier app, behind the Android manifest flag; other apps retain their own theme.
- `SupplierAuthController` uses Clerk `user_` + `sess_` only to invalidate old sessions. It authorizes nothing from email, JWT roles or client metadata.
- Verified path: `GET /api/v2/me` then `GET /api/v2/suppliers/{supplierId}/access`; only an exact matching supplier ID and role can unlock a shell. PostgreSQL backend checks active approved memberships and suspension on each request.
- Refresh on app resume, explicit permission refresh, account change and supplier re-selection. Authenticated screens immediately clear old supplier context while checking. An account with two businesses chooses explicitly; no arbitrary ID entry or reuse of stale role.
- The existing S01 five-tab shell displays actual verified supplier UUID suffix and role, not fabricated business names/orders. Its feature tabs remain honest staging placeholders until the matching later PRs.
- Backend-specific failures remain distinct: 401 expired session, 403/404 denied membership, network/provider unavailable. SDK-local sign-out does not falsely claim remote revocation.

## Enable the S02 staging app

The old Grozo restaurant app stays the default until its flows are replaced. **Explicit opt-in is required**:

- Dart defines: `BUILDTO_SUPPLIER_V21=true`, `AUTH_MODE=clerk-test`, `BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com`.
- Native Android Gradle environment: `GROZO_AUTH_MODE=clerk-test` and `CLERK_PUBLISHABLE_KEY=pk_test_...` (public development publishable key for the same *actual* Clerk instance as Render).
- The Dart auth mode and Android auth mode must both be Clerk test; wrong/missing values fail closed and do not fall back to local passwords or restaurant session tokens.
- Do not add `CLERK_SECRET_KEY`, webhook signing secret, database URL, Firebase server key or admin credentials to Dart defines, manifest, source code or CI.
- The staging Android application ID is currently `in.grozo.vendor` in the repository's existing branding config; do **not** rename it during S02 because it affects Clerk OAuth redirect configuration, signing and installed accounts. Final native launcher/name package transition belongs to the reviewed release plan.

Example (bash; put the actual **public** key in your operator's environment, not in a committed file):

`cd apps/vendor_app`
`export GROZO_AUTH_MODE=clerk-test`
`export CLERK_PUBLISHABLE_KEY=pk_test_YOUR_STAGING_PUBLIC_VALUE`
`flutter pub get --enforce-lockfile`
`flutter run --dart-define=BUILDTO_SUPPLIER_V21=true --dart-define=AUTH_MODE=clerk-test --dart-define=BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com`

This run command is for local/staging **Android** only. Native iOS Clerk integration is not claimed or shipped in S02.

## Backend native-token compatibility gate — critical

The V2.1 backend intentionally defaults `CLERK_ALLOW_NATIVE_WITHOUT_AZP=false` and requires an explicit configured `CLERK_AUDIENCE` before allowing native tokens that omit `azp`. The mobile app does not edit these server settings, forge JWT claims or assume a token with the expected audience is available.

Before claiming live integration, the operator must:

1. Verify the development Clerk instance matches the public key packaged in the Android build, and test the native SDK's actual JWT claims (issuer, audience and azp) without copying the raw token into logs or tickets.
2. Configure Render's backend-only, explicitly approved audience/authorized-party/native policy to match verified real tokens **without weakening signature, expiry, session status or account checks**. For an absent `azp`, the explicit native flag and audience are both mandatory. Do not alter active admin frontend CORS/origins merely to enable native.
3. Verify a real active Clerk login against `/api/v2/me` (requires a synced local User), then the actual supplier's `/access`. An admin-only or customer-only Clerk account must never become a supplier by signing in.
4. Validate pending/rejected/suspended suppliers, stale memberships, multiple supplier accounts, reauth, lost network, 401, 403/404 and real native sign-out on an Android device. Production remains disabled.
5. Configure Clerk Android OAuth redirect intent filters for the existing application ID and verify the native MFA/recovery flows. No fixture credentials are proof of this gate.

**Current verification boundary:** CI with mocked Clerk and HTTP transport proves Flutter request sequencing and server-response gating, not that staging native tokens satisfy all live Render settings. Do not label an offline/mock test as live E2E.

## UI/UX and safety acceptance

- Use BuildTo brand colors, heading scale, rounded controls and high-contrast status explanations inherited from S01. The native Clerk form uses supplier-only Compose branding; no Grozo logo in the supplier login flow.
- No access to Home/Orders/Catalog/Stock/More shell until the backend confirms exact supplier membership. Authenticated supplier labels are UUID suffixes because `/me` does not provide business name.
- No fake orders, finance balances or storefronts. Pending applicants are informed of S03 rather than shown a nonfunctional "Apply" form.
- Check narrow 320px screens, 360px/393px/412px phone layouts, large text and session switch while async calls are outstanding.
- On logout/identity switch, never retain supplier-scoped business data or callback actions; previous async responses cannot unlock the new account.
- All actual supplier **business mutations** stay backend-controlled in future S05–S12. Flutter's visual gating is not authorization.

## Automated validation

`dart format --output=none --set-exit-if-changed lib/v21 test/v21`
`flutter analyze --no-pub lib/v21 test/v21`
`flutter test --no-pub --concurrency=2 test/v21`
`flutter build bundle --debug --no-pub --dart-define=BUILDTO_SUPPLIER_V21=true --dart-define=AUTH_MODE=clerk-test --dart-define=BUILDTO_V21_API_BASE_URL=https://buildto-v21-staging.onrender.com`

CI must also compile the Android staging-native bridge when feasible; build-only tests do not assert that someone has signed in. Existing old Grozo vendor, driver and customer runtime app modes are not silently migrated. Known unrelated baseline customer analyzer/terminology failures remain tracked, not exempted in S02.

**Next: S03 supplier application/onboarding**, only after the user's explicit next-PR instruction. This PR must not proceed into S03.
