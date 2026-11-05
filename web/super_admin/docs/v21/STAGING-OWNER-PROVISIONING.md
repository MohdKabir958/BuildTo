# A02 — first BuildTo admin OWNER: manual and audited staging process

**The frontend intentionally cannot create administrators.** Clerk sign-up only identifies a person. `GET /api/v2/me` checks the local persisted `User`, then `GET /api/v2/admin/access` independently requires a current, active `AdminMembership` with `ADMIN_READ` permission.

Before a first-ever staging OWNER can use the console:

1. Confirm the staging **development** Clerk instance and the correct signed webhook endpoint `/api/v2/webhooks/clerk`. The verified Clerk user must sign in once so their signed webhook creates a V2.1 `User` record (email/phone from verified primary contact only).
2. An operator must independently verify who the owner is, their Clerk `user_...` subject, verified primary email, and that the corresponding staging DB user is `ACTIVE` and not deleted. **Never assign OWNER by a frontend email or a caller-supplied role.**
3. Before any membership change, make a Neon staging branch backup. From the explicitly selected `backend/v21-staging` branch, read-only check the target `User`, current `AdminMembership` and whether an active OWNER already exists.
4. Grant exactly one active `AdminMembership` role `OWNER` inside a single transaction, with a matching `AuditEvent` recording the operator, subject and action; the database must reject an existing active owner and any wrong target. Only a reviewed, manually approved operator operation should perform this first grant. No automatic owner role on sign-up, JWT or Clerk metadata.
5. Verify `GET /api/v2/me` returns `adminRole:'OWNER'` and `GET /api/v2/admin/access` returns `role:'OWNER'` for the real signed-in account; non-admin signed-in accounts must receive 403 from admin/access.
6. Future admin membership changes will happen via A04's OWNER-only endpoints, with last-owner safeguard and maker/checker evidence for finance operations.

**Environment:** staging frontend requires `VITE_ADMIN_VERSION=v21`, `VITE_AUTH_MODE=clerk-test`, exact `VITE_API_BASE_URL` and public `VITE_CLERK_PUBLISHABLE_KEY=pk_test_...`. Never put `CLERK_SECRET_KEY` or database credentials in Vite variables. HTTPS frontend origin must be added explicitly to Render `BUILDTO_V21_CORS_ORIGINS`, `CLERK_AUTHORIZED_PARTIES` and Clerk allowed origins; the current temporary API self-origin is not a valid frontend substitute. CSP is updated when deploying A15.

**Non-goals:** no database migrations, no manual SQL pasted into client code, no staging-owner writes by GitHub Actions, and no production branch operations.
