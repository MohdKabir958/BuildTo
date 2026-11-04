# BuildTo — Construction Materials Platform

BuildTo is a construction-materials marketplace with customers, suppliers, delivery coordination, inventory, checkout, Indian tax and controlled payments.

## Current backend

- **Active API:** `backend/v21/src/` — Express/TypeScript
- **Active schema:** `backend/prisma/v21/schema.prisma` — Prisma/PostgreSQL/PostGIS
- **Approved migrations:** `backend/prisma/v21/migrations/` — three V2.1 migrations
- **Staging deployment:** [BuildTo V2.1 API on Render](https://buildto-v21-staging.onrender.com)
- **Staging endpoints:** `/health`, `/ready`, `/api/v2/system`
- **Status:** staging only; not production-ready.

The repository is adapted from the former Grozo/Kraveo platform. `backend/src/`, `backend/prisma/schema.prisma`, older migrations and some client code are **legacy**, not the active V2.1 API. We are retiring them in dependency order because existing admin/mobile code still calls legacy `/api/v1` endpoints; deleting them blindly would break remaining transition tests and client contracts.

Read `backend/v21/docs/LEGACY-CLEANUP-PLAN.md` and `backend/prisma/README.md` before removing anything else. Never run old Prisma migration scripts against Neon V2.1.

## Apps

- `apps/customer_app/` — Flutter customer app, integration migration pending
- `apps/vendor_app/` — Flutter supplier app, integration migration pending
- `apps/driver_app/` — legacy delivery app pending business-scope review
- `web/super_admin/` — existing admin frontend, V2.1 integration pending
- `branding/` — brand assets/configuration

## License

MIT License (see `LICENSE`).
