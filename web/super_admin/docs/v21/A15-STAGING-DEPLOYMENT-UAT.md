# BuildTo Admin A15 — Staging deployment, UAT and rollback

**State: code and CI release gate.** A merged PR is not itself proof of a live, authenticated staging portal. Do not mark staging UAT complete before the operator steps below succeed.

## Constraints

- Uses the original React/Vite portal in web/super_admin and the single V2.1 Express backend. No schema change, migration, DB reset, Kafka, Redis, second API or production configuration.
- Render Node API: https://buildto-v21-staging.onrender.com. At the time this PR was prepared, Render tracked the **release branch**, not main, with autoDeploy disabled. Admin routes merged to main do NOT become available on that API automatically.
- Neon staging: branch br-noisy-water-b5gc1kgz. Production database branch is not in scope.
- Clerk staging issuer: informed-griffon-7675.clerk.accounts.dev. Actual public Clerk publishable key must be checked against this instance in the development Clerk dashboard before real sign-in; do not substitute a guessed key or use a live key.
- No VITE_ variable may contain a server credential, DB URL, webhook secret or payment key.

## Source/CI checks

1. Run node scripts/check-v21-contract.mjs from web/super_admin.
2. With the **verified** public development Clerk key, set environment VITE_ADMIN_VERSION=v21, VITE_AUTH_MODE=clerk-test, VITE_API_BASE_URL=https://buildto-v21-staging.onrender.com and VITE_SOCKET_URL=https://buildto-v21-staging.onrender.com. The legacy hosted auth build checker expects VITE_SOCKET_URL, but V2.1 does not create a Socket.IO connection.
3. Run npm ci, npm run build, npm run check:v21:staging, and npm test -- --run in web/super_admin. The public test fixture in GitHub Actions proves the build/CSP contract, **not actual Clerk account ownership**.
4. Run all V2.1 Prisma parity, TS and disposable PostGIS HTTP tests, including owner/finance/support/auditor role denial, exact cents/Decimal, audit redaction, finance controls and release preflight.

## Operator-required live staging rollout

1. Choose HTTPS **staging-only** frontend hosting with the exact Vercel security headers in web/super_admin/vercel.json (or demonstrably equivalent CSP). No wildcard trusted origins.
2. Verify the real development Clerk publishable key and configure the V2.1 public Vite variables listed above in the static frontend hosting project. Do not expose server environment values. Build from the exact reviewed main commit.
3. Add the actual HTTPS frontend origin to the API's **BUILDTO_V21_CORS_ORIGINS** and **CLERK_AUTHORIZED_PARTIES** environment variables and to Clerk authorized origins. Preserve other explicit legitimate origins only. Do not guess a frontend URL or set wildcard origins.
4. Reconcile admin code from main into the Render release branch **without dropping** its .node-version, staging smoke checks or startup security adjustments. Explicitly review diff, commit and deployment target. Never silently switch to a different DB or use deploy-empty migrations against staging.
5. Deploy the reviewed backend commit to the existing staging service using its manual deployment mechanism. Verify its /ready and /api/v2/system before sending admin traffic, and that /api/v2/admin/audit and other new routes exist but deny unauthenticated callers.
6. Follow STAGING-OWNER-PROVISIONING.md: signed Clerk provisioning, independently verified first OWNER, read-only preflight, Neon staging backup, audited OWNER grant, then verify owner identity using real Clerk sign-in. Signup alone is **not admin approval**.
7. Execute node web/super_admin/scripts/smoke-v21-staging.mjs for safe public GET probes.
8. UAT with authorized staff by exact roles OWNER, OPERATIONS, CATALOG, FINANCE, SUPPORT, AUDITOR. Test supplier applications and document approval; catalog categories, products and listing version conflict; cities/areas; promotions; dashboard aggregates; order funding/shipments; support private notes, returns and reviews; audit redaction and pagination.
9. Test forbidden direct API calls return 403, revoked admin denied, nonexistent supplier/order 404 where applicable, unknown Origin 403, unauthenticated private routes 401. Verify browser network panel never exposes full bank account, OTP hash, provider secret, credit card data, private evidence object keys or stored bearer token.
10. **Finance UAT uses test-only provider evidence:** different maker and reviewer for COD receipt, settlement, refund, masked beneficiary and payout status. Payout intent must NOT execute bank transfer. Provider processed is NOT independent bank debit or customer credit.
11. Test responsive layout, keyboard navigation, loading/error/empty states, support internal note privacy, frontend security headers and content security policy. Capture screenshot/browser console and permission negative evidence.
12. Record exact deployed backend/frontend commit, staging URL, health response, security checklist and approved rollback version before marking staging UAT complete.

## Rollback policy

- Rollback static frontend first, or remove the staging frontend origin from allowed CORS/Clerk parties to prevent authenticated writes. Verify service stays healthy.
- Rollback backend **application routing** only to a compatible verified release, preserving immutable financial journals and migration history. Do not reverse Prisma migration, delete payment events or rewrite settled ledger entries.
- Any release flag that incorrectly claims production readiness or automatic money execution is a hard release blocker. Production cutover requires separate approval after legal, finance and provider checks.

## Staging sign-off: not yet verified by code/CI

- [ ] Verified actual frontend HTTPS URL and strong CSP
- [ ] Verified public Clerk key and real owner sign-in
- [ ] Render backend release branch synced and deployed to staging
- [ ] Exact CORS and Clerk authorized origins updated
- [ ] All roles tested against deployed APIs and UI
- [ ] Test-only finance maker/checker walkthrough completed
- [ ] Rollback targets captured and operator signed off

These boxes must remain unchecked until observed on live staging.
