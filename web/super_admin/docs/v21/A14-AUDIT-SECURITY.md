# Admin A14 — privileged audit read and security review

**Existing-table only**: uses the already-deployed `AuditEvent` model. No change to `backend/prisma/v21/schema.prisma`, migrations or production database.

## Scope
- `GET /api/v2/admin/audit` with `limit` (1–50), `cursor`, optional `entityType` and `action`.
- Enforced `AUDIT_READ` permission on every request: OWNER and AUDITOR only. FINANCE, SUPPORT, CATALOG and OPERATIONS are refused.
- Pagination is deterministic (`createdAt DESC, id DESC`), no arbitrary sort or unbounded result.
- Explicitly projects only ID, timestamp, actor identity/role, action and entity reference. Audit event `beforeState`, `afterState`, `ipHash` and request IDs are not returned (even if present in database).
- React audit table with filters, pagination, loading/empty/error states. No mutation controls.
- DB-backed denial and redaction tests plus admin UI tests and OpenAPI parity.

## Security gates for the overall admin portal
- Backend database roles and current Clerk session remain authoritative; hiding a UI tab is not an authorization check.
- Never return sensitive document object keys, Clerk tokens, OTP hashes, payment provider secrets, raw audit snapshots or bank account digits.
- Keep finance actions two-person where required; never infer bank transfer from payout intent.
- Keep `/api/v2` only; no legacy API fallback or arbitrary remote URL for tokens.
- Build and test against disposable PostGIS only, and do not deploy to production as a side-effect of CI.

## Manual review before merge
- Run the V2.1 full HTTP/Prisma suite with a test database and role-negative coverage.
- Run `npm test`, `npm run build` and admin contract check inside `web/super_admin`.
- Confirm `AuditEvent` includes no client-facing before/after fields in the API response.
