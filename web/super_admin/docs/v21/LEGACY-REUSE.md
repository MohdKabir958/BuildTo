# Admin V2.1 legacy reuse decisions

**Keep as foundations** (inspect and selectively import, never copy legacy business assumptions): React 18, Vite, Tailwind, TypeScript, `@clerk/react`, typography, icon components, `components/ui/ConfirmDialog.tsx`, `components/ui/Toast.tsx`, `components/ui/Drawer.tsx`, `components/ui/EmptyState.tsx`, `components/ErrorBoundary.tsx`, responsive shell styling, accessible focus patterns.

**Rewrite with V2.1 contracts**: `src/App.tsx` (44KB tightly bound to campus/driver data), `src/services/api.ts` (43KB of legacy `/api/v1` calls), `Sidebar.tsx` nav items, dashboard, products/catalog panels, customer support, order detail, finance forms, `auth/ClerkAdmin.tsx` (Clerk frontend is reusable but its `validateSession` method calls the old API).

**Do not port**: Grozo restaurants/dishes/menus, hostel/campus maps, rider dispatch/Socket.IO tracking, ad hoc cash collections, passcode login, localStorage bearer tokens, old OTP codes, unsupported payment payout mutation endpoints and fictional analytics.

**Transition:** New `src/v21/` is isolated and may be selected with `VITE_ADMIN_VERSION=v21` until independently signed-in and verified. The inherited UI remains unchanged until migrations are tested and A15 cutover is authorized. Do not delete old frontend files while baseline CI and old apps still import them.

**Implementation choices:** one React app, one entrypoint, one Clerk provider, no Redux/extra state library, no second backend, no runtime-generated mock totals, no direct Prisma from the browser. Keep feature-scoped typed API modules.
