# PR 62 staging deployment

Target backend: `buildto-v21-staging` on Render. Target database: Neon project
`long-cake-87118137`, branch `br-noisy-water-b5gc1kgz`, database `neondb`.
Do not deploy the legacy backend entry point or change the production-readiness flags.

## Commands

Build from the repository root:

```sh
cd backend && npm ci && npm run db:v21:parity && npm run db:v21:validate && npm run build:v21
```

Apply reviewed migrations with the official Prisma runner, using the direct staging
connection as `DATABASE_URL`:

```sh
cd backend && npm run db:v21:deploy
```

Start from the repository root:

```sh
cd backend && node v21/dist/server.js
```

Migration checks at startup/readiness are read-only. They reject incomplete or
modified migration history. No SQL splitting, swallowed migration errors or
handwritten migration-ledger entries are used.

## Private object storage

Neon bucket `splyzo-private-media` is private. Configure these Render secret
environment variables; never commit their credential values:

| Variable | Value |
| --- | --- |
| `BUILDTO_V21_MEDIA_S3_ENDPOINT` | `https://br-noisy-water-b5gc1kgz.storage.c-7.us-east-2.aws.neon.tech` |
| `BUILDTO_V21_MEDIA_S3_REGION` | `us-east-2` |
| `BUILDTO_V21_MEDIA_S3_BUCKET` | `splyzo-private-media` |
| `BUILDTO_V21_MEDIA_S3_ACCESS_KEY_ID` | Scoped Neon credential token ID |
| `BUILDTO_V21_MEDIA_S3_SECRET_ACCESS_KEY` | Scoped Neon S3 secret |

Only storage read/write scopes are required. The API retains owner/reviewer
authorization and SHA256 verification. Private evidence is never served as
static content. The S3 adapter uses HTTPS, path-style addressing and immutable
UUID object keys. Partial configuration fails startup rather than falling back
to ephemeral storage. Supplier catalog photos already stored in `CatalogImage`
remain supported alongside catalog media assets.

Verify `/health` and `/ready` after deploy. Check all seven reviewed Prisma
migrations and the deployed Git commit. Authenticated object roundtrip must
succeed while an anonymous object request returns 403. Staging success does not
replace real-device authentication, provider/bank acceptance or production approval.
