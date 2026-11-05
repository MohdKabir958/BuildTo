# BuildTo Supplier Flutter — S00 screen × V2.1 API contract map

**Canonical API:** `backend/v21/openapi.json` 0.24.0; **49 existing operations / 10 groups** enumerated in machine-readable `apps/vendor_app/tool/v21_supplier_contract.json`.
**Interpretation:** these are verified backend API **shapes**, not claims the current Flutter app already calls them. Client implementation is S01–S12. Descriptions are constrained to what current backend docs/routes support.

| Supplier UI / PR | Required API groups and representative exact routes | Client state, restriction and validation |
| --- | --- | --- |
| Sign-in, supplier selector (S02) | `GET /api/v2/me`, `GET /api/v2/suppliers/{supplierId}/access` | Server-confirmed supplier memberships only; no JWT role, guessed supplier ID or unknown approval default. Cleared when identity/member changes. |
| Application + progress (S03) | `POST /api/v2/supplier-applications`, `GET /api/v2/me/supplier-applications` | Customer identity may apply; pending membership grants **no** supplier write access. Distinguish pending, under review, approved, rejected, suspended. |
| Evidence checklist (S03) | `POST /api/v2/supplier-applications/{supplierId}/documents` | Links **existing private media**, not an upload. Keep upload disabled until secure backend storage and reader is designed/tested. |
| Dashboard (S04) | Composite of supplier-scoped orders, inventory, RFQs, finance reads | No authoritative aggregate endpoint assumed; derive only labeled snapshots without currency arithmetic using float. |
| Material catalog + listing (S05) | `GET /api/v2/catalog/categories`, `GET /api/v2/catalog/products`, `GET /api/v2/suppliers/{supplierId}/listings`, `POST .../listings`, `PATCH .../listings/{listingId}`, `POST .../submit`, `PUT .../price-tiers` | Public product masters are **not** supplier listings. Supplier edits require version preconditions; submit requires backend moderation; use exact tier/quantity strings. |
| Warehouse + balances (S06) | `GET/POST /api/v2/suppliers/{supplierId}/inventory/warehouses`, `GET .../balances`, `GET .../movements`, `POST .../adjustments`, `POST .../transfers` | Availability snapshot != reservation. Mutations need idempotency/version safeguards; stock movements remain append-only. |
| Service areas (S07) | `GET /api/v2/suppliers/{supplierId}/delivery`, `PUT .../delivery/areas/{areaId}`, `PUT .../flat-rate` | Admin-approved areas only; server-defined flat/handling paise, no arbitrary freight claim. |
| RFQ invitations/quote versions (S08) | `GET /api/v2/suppliers/{supplierId}/rfqs`, `GET/POST .../rfqs/{rfqId}/quotes` | Supplier must be invited, quote every line, submit with idempotency; quoted award is not funded order. |
| Supplier orders (S09) | `GET /api/v2/suppliers/{supplierId}/orders`, `POST .../orders/{supplierOrderId}/accept`, `POST .../reject` | One exact supplier only; accept funded/COD-eligible stock, reject only strictly unpaid pending child. No fake “cancel paid order.” |
| Shipments + OTP (S10) | `GET/POST .../orders/{supplierOrderId}/shipments`, `POST .../shipments/{shipmentId}/pack`, `/dispatch`, `/out-for-delivery`, `/handover` | Planned → packed → dispatched → out-for-delivery → verified handover. Customer issues 6-digit 5-min OTP via *customer* route; supplier only submits it. Honor lockouts. |
| Returns + reviews (S11) | `GET .../orders/{supplierOrderId}/returns`, `POST .../returns/{returnId}/receive`, `GET .../reviews`, `GET .../reviews/manage` | Supplier can receive only approved goods. Receipt is not refund, inspection, stock adjustment or tax credit by itself. Unpublished reviews are not public. |
| Finance (S12) | `GET .../finance/statement`, `GET .../finance/beneficiaries`, `GET .../finance/payouts`, `GET/POST .../orders/{supplierOrderId}/invoices`, `GET/POST .../cod`, `POST .../returns/{returnId}/credit-note` | Supplier FINANCE_READ/INVOICE_ISSUE permissions. Backend controls GST and exact totals. Mask bank details. PENDING payout is an intent, SUCCEEDED provider-processed but not third-party bank ledger verification. |
| Profile, settings + help (S03/S13) | `GET /api/v2/me` and supplier access; no unverified writes | Profile editing, invitations and chat are not implicitly available from role models; disabled or reviewed backend extension. |

### Error and mutation contract (every feature)

- Canonical envelope is server-provided `data` / `requestId` for success; handle typed server errors, retryable network faults and account/session revocation.
- `401`: reauthenticate or show signed-out state; `403`: deny unauthorized action, not permission bypass; `404` on foreign supplier IDs prevents resource enumeration.
- `409`: conflict, fetch latest server version then ask user to review changes. Never overwrite or generate a new idempotency key on an uncertain retry.
- `428` on relevant mutations: provide a stable per-intent `Idempotency-Key` (contract docs); clients must not create duplicate orders/shipments/adjustments.
- `429` and `5xx`: bounded retry/refresh, never pretend a request failed or succeeded solely due to timeout.
- All amounts: exact paise strings; all quantities/unit prices: exact decimal strings. Parse only into a decimal-safe representation, never IEEE-754 double for business calculations.
- Supplier permissions are server-enforced by `backend/v21/src/permissions.ts` roles: OWNER, MANAGER, CATALOG, INVENTORY, FULFILLMENT, FINANCE, VIEWER. UI may *hide* actions but never treats UI gating as authorization.

### Hard boundary: absent or unsupported supplier endpoints

The audited 0.24.0 OpenAPI does **not** establish general supplier staff invitation/role-mutation, supplier profile editing, private raw-KYC upload/download, supplier chat, push device token registration, a read-only supplier aggregate dashboard, or restaurant-style Socket.IO order events. No screen should claim those actions work. Each gap has an owner and an implementation prerequisite in `S00-AUDIT.md`.

### Evidence and commands

The route manifest was checked against the 136-path canonical OpenAPI when generated. Repeat checks after any backend API change:

`node --test apps/vendor_app/tool/check_v21_contract.test.mjs`  
`node apps/vendor_app/tool/check_v21_contract.mjs`

The contract CI guard is deliberately limited to static endpoint existence and checker behavior. Real Clerk staging, supplier RBAC, data shapes, UI widgets and device UAT must be implemented and tested by **later** PRs.

**UI visual authority:** `S00-UI-UX-FIDELITY.md` ties supplier screen types back to all 16 customer mock pages while refusing unsupported customer-side actions.
