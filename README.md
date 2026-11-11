# Splyzo — Construction Materials Platform

Splyzo connects customers, approved construction-material suppliers and delivery partners for sourcing and delivering building materials to project sites.

## Apps and services

- `apps/customer_app/` — customer ordering and site delivery tracking
- `apps/vendor_app/` — supplier registration, catalogue, inventory and order fulfilment
- `apps/driver_app/` — delivery partner app
- `web/super_admin/` — Splyzo operations and administration portal
- `web/landing/` — public product website
- `backend/v21/` — active V2.1 API and schema
- `branding/` — canonical Splyzo brand configuration and artwork

## Brand

The public product name is **Splyzo**. The canonical logo is `branding/assets/splyzo-logo.png`; `branding/brand.json` defines display names, palette, tagline and shared app asset path.

Existing Android application IDs, native Clerk bridge package names, database identifiers and selected environment-variable names are retained for upgrade and integration compatibility. They are implementation identifiers, not public product branding. New launcher icons and splash artwork use Splyzo.

## Backend

- Active API: `backend/v21/src/`
- Active schema: `backend/prisma/v21/schema.prisma`
- Staging API: `https://buildto-v21-staging.onrender.com` (existing infrastructure hostname; migrate separately before changing deployed endpoints)
- Status: staging only; not production-ready.

The older code under `backend/src/` and `backend/prisma/schema.prisma` remains in controlled retirement while clients are migrated. Do not run legacy Prisma migrations against the V2.1 database.

## Local checks

- Flutter: run `flutter pub get`, `dart format`, `flutter analyze` and the relevant app tests from each app directory.
- Admin Portal: run the package scripts in `web/super_admin/package.json`.
- Brand configuration: `python3 scripts/configure_brand.py --check`.

## License

MIT License (see `LICENSE`).
