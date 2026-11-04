# Admin A03 — V2.1 request boundary

The BuildTo admin app uses the same React/Vite application and Clerk provider as A02. `V21ApiClient` is available from a context only **after** A02's signed-in user has passed both `/api/v2/me` and `/api/v2/admin/access`. No legacy `src/services/api.ts` functions are imported into the new V2.1 screens.

### Guarantees

- Auth token is obtained from Clerk `getToken` on each call; no passcode, cookie shortcut or localStorage bearer.
- Only same-origin paths beginning with `/api/v2/` can receive credentials.
- Requests have a finite timeout, explicit cache disabled and controlled cancellation.
- Errors expose HTTP status, safe API error code and request ID to distinguish 401, 403, 404, 409, 422, 429 and network failures.
- Mutations are **never automatically retried**, especially finance writes. Caller-supplied `Idempotency-Key` must persist across manual retry of a single intent. Some endpoints require `expectedVersion` in JSON: use `withExpectedVersion`.
- All monetary amounts use string paise via `formatPaise`; all decimal quantities remain strings. Never use JavaScript floating-point arithmetic for invoices, stock or settlements.
- API responses are always checked for the expected `data` envelope, but each feature still validates its own typed DTO at the boundary. Do not render raw Prisma records.

### Scope

A03 adds the shared transport and error/precision foundations. Business endpoints/screens will be introduced one module at a time in A04–A14, reusing the transport and adding dedicated regression fixtures.

No new database migration, backend service, external state library, polling system or queued writer is introduced.
