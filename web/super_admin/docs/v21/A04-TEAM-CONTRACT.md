# A04: active admin memberships (existing PostgreSQL models, no migrations)

Server routes are available **only after verified Clerk identity** and database `AdminMembership` permission `TEAM_MANAGE` (OWNER only). The frontend cannot create user accounts or provision an initial owner itself.

| HTTP | Path | Input | Response |
| --- | --- | --- | --- |
| GET | `/api/v2/admin/team?cursor=&limit=25` | Optional UUID cursor; limit 1–100 | `data:{items,nextCursor}` |
| POST | `/api/v2/admin/team` | `{email,role,reason}` | 201, current member |
| PATCH | `/api/v2/admin/team/{userId}` | `{role,reason}` | 200, current member |
| POST | `/api/v2/admin/team/{userId}/revoke` | `{reason}` | 200, revoked member |

Only active, verified-primary-email `User` records synchronized by the signed Clerk webhook can be granted membership. All mutations execute as SERIALIZABLE DB transactions, acquire a short global team-role lock, re-check OWNER authority, enforce last-active-owner and self-management restrictions, and record bounded `AuditEvent` role transitions and justifications. Read pagination uses `userId` order/cursor, never unbounded `findMany`.

UI must distinguish **grant role to an existing Clerk account** from sending a Clerk invitation. The app does not send mail, trigger Clerk account creation, import an arbitrary raw email or bypass the first-owner operator runbook.

For CI, `backend/v21/test/admin-team.test.cjs` uses disposable PostGIS/Prisma fixtures and mocked verified Clerk identity, including permission denial, no self changes, concurrent duplicate grants and action audit. **Do not use Neon staging as a fixture.**
