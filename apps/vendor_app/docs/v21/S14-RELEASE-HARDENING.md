# S14 — Supplier release configuration hardening and safe handoff

This final supplier PR adds a fail-closed runtime release policy. It does not authorize deploying an untested app. All S00–S13 quality gates and physical UAT requirements remain binding.

## Release-mode security invariants
A real BuildTo Supplier release must use:
- BUILDTO_SUPPLIER_V21=true. Without this selector, the preserved legacy Grozo vendor experience still exists in the same monorepo; it must not be mistaken for a BuildTo release.
- AUTH_MODE=clerk, not clerk-test or legacy. Native Android Grozo auth mode must also be clerk.
- BUILDTO_V21_API_BASE_URL must be a plain trusted HTTPS origin with no path, query, user info or fragment, no insecure port and no test/staging host.
- BUILDTO_V21_PRODUCTION_API_HOST must be the deployment-approved host and must exactly match the origin host. No default production host is invented.
- Owned release keystore and real Clerk production publishable key configured by Release Engineering. Never commit keys, tokens, OTPs or backend secrets.

The SupplierReleasePolicy is checked before the native Clerk SDK initializes in a release-mode V2.1 app. It blocks test mode, missing host pinning, staging, loopback, wrong HTTP scheme and mismatched host. Debug Flutter tests and existing pinned staging CI are intentionally unaffected.

## Required external signoff before a production release
1. Choose and approve the real production API domain, key, certificate, data residency, access and rollback plan; do not infer it from buildto-v21-staging.onrender.com.
2. Attach S13 real-device / 16-page reference visual approval, access-revocation UAT, payment and COD receipts, independent finance reviews, GST/credit-note validation, delivery OTP proof (redacted), returns and refunds separation.
3. Have Release Engineering independently run and attest a real signed store-target AAB/APK with the approved production Clerk key, approved API host and native mode. Do not release a debug APK, staging API or fixture key.
4. Verify the installed signed app cannot access a different supplier or silently fall back to the preserved restaurant session; verify 401/403/offline states before rollout.
5. Sign release notes, app version, crash monitoring, rollback, customer support handoff and security findings. Record reviewer identity and evidence location.

**Final status until signed:** automated CI validation only. S14 intentionally does not change backend finance authority, create money movement APIs, invent tax documents, or claim real-device acceptance.

## Human reviewer checklist
- [ ] Staging Flutter regression and Android native Clerk CI green on final main merge
- [ ] Production HTTPS host separately approved and verified
- [ ] Real Clerk production project and owned release signing
- [ ] Original supplier UI/UX PDF acceptance documented
- [ ] Finance, returns and OTP independent UAT recorded
- [ ] Release owner approves store submission and rollback

The final checkbox is a HUMAN deployment decision, never an automated pass.
