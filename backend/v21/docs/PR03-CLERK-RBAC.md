# Buildto V2.1 PR 03 — Clerk identity and DB-enforced RBAC

## Security boundary

Clerk signs authentication tokens and manages sessions. **Only PostgreSQL can authorize Buildto supplier/admin actions.** No value from a token's `role`, `metadata`, request body or supplier ID is accepted as a grant.

The V2.1 server validates a Clerk JWT via the official SDK with expected issuer, authorized party and optional audience, and then asks Clerk for the **active session** and current non-banned user. Provider unavailability fails closed. The app then queries V2.1 `User` by exact `clerkUserId`, refusing unknown, suspended, deleted or closed accounts. Identity is not automatically created from an unrecognized Bearer token.

### Webhooks

`POST /api/v2/webhooks/clerk` receives **raw** JSON, verifies the Svix v1 HMAC signature in constant time and rejects messages older/newer than five minutes. The signed message ID deduplicates delivery within a serializable database transaction. The receipt lives in `OutboxEvent` marked `DELIVERED` to keep it out of normal event worker processing, while the change is captured in `AuditEvent`.

- `user.created`: Creates a new local account with status ACTIVE. No email-based auto-linking, no admin/supplier role.
- `user.updated`: Updates only `displayName` on a non-deleted account.
- `user.deleted`: Creates a permanent tombstone if missing or closes an existing user; atomically revokes admin and supplier memberships.
- Later stale user events **cannot** revive a closed/deleted account.
- Unknown signed event types get a 202 ignored response, without changing identity data.
- No raw webhook data, email, phone, address, signing secret or token is stored in audit events or logs.

Note: Display-name updates can arrive out of order; they carry **no authorization or financial privilege**. A future profile module can reconcile provider timestamps if needed. The current service does not implement account restoration; that requires a separate audited operator flow.

### Active database memberships

Only `AdminMembership(active=true, revokedAt IS NULL)` grants the declared admin actions. Supplier access requires `SupplierMember(active=true,revokedAt IS NULL)` **and** `Supplier(approval=APPROVED,suspendedAt IS NULL)`, scoped by **both userId and supplierId**. The server checks the DB on each request. A user with multiple supplier memberships cannot cross supplier boundaries. Unknown/other supplier IDs yield 404 without exposing their existence.

PR 03 exposes only:
- `GET /api/v2/me`: the authenticated user's own minimal identity and active memberships.
- `GET /api/v2/admin/access`: DB-approved admin role only.
- `GET /api/v2/suppliers/:supplierId/access`: DB-authorized membership on that exact supplier.

**No public role-grant endpoint, management API, supplier write, payout, or admin mutation exists in PR 03.** Explicit role provisioning will come through a privileged audited operator procedure and later domain services.

## Staging configuration

Configure backend-only, through secret management:

```
CLERK_SECRET_KEY=<server_secret>
CLERK_ISSUER=https://<clerk-issuer>
CLERK_AUTHORIZED_PARTIES=https://<approved-admin-or-customer-origin>
CLERK_WEBHOOK_SIGNING_SECRET=whsec_<signed-provider-secret>
# Optional if a protected session token uses an audience:
CLERK_AUDIENCE=<audience>
CLERK_JWT_KEY=<clerk-public-jwt-key>
# Native clients require a configured audience and explicit opt-in:
CLERK_ALLOW_NATIVE_WITHOUT_AZP=false
```

Webhooks should be configured at Clerk for `user.created`, `user.updated`, and `user.deleted` after the staging API baseline is resolved and the route is deployed.

## Tests

The dedicated GitHub Action `Buildto V2.1 Clerk and RBAC security` uses a disposable PostgreSQL 16/PostGIS database. JWT-provider calls are **dependency-injected only in automated tests**, while production `server.ts` always uses the real Clerk SDK. Tests cover signature tampering, timestamp replay, duplicate deliveries, user soft deletion, membership revocation, cross-supplier attempts, suspended suppliers and explicit admin permission denial. PR 02 foundation tests also run.

## Production restrictions still enforced

- Application cannot start against Neon production (PR 02 config is staging/local allowlisted).
- Staging still needs its official PR 01 Prisma migration ledger resolved before any API server will listen.
- No frontend/mobile app connected, no business workflow introduced, and no migrations run against Neon production.
