# BuildTo Supplier — mandatory 16-screen UI/UX fidelity contract (S00)

**Design authority:** user-supplied `Buildto_16_Screens_Enhanced-1 (1).pdf`, 16 pages (customer app references). This PDF is **not** checked into the repository and is not an app asset. Treat it as a visual specification, not evidence that customer-only features exist in supplier V2.1.
**Non-negotiable:** professional, advanced, attractive and consistent BuildTo UI; do not ship an off-the-shelf Flutter/Material look or reuse Grozo restaurant branding.
**Enforcement begins in S01**, continues on **each** screen PR (S02–S12), and closes at S13 on real devices.

## Observed design language to preserve

- **Brand presentation:** BuildTo mark/name at prominent app entry points, strong deep-navy primary surfaces, white/light page backgrounds, fine blue outlines and bright orange/gold action accents.
- **Composition:** clear top bars and section headers; prominent hero/feature artwork where useful; grid product cards with large item imagery; gently rounded white cards; spacious dividers; compact status pills; readable primary buttons.
- **Typography:** bold hierarchy for names, headings and Indian rupee values; comfortable body sizing; short, unambiguous action labels; no clipped numerals. The rasterized PDF does **not** uniquely identify the original typeface or numeric exact colors: S01 must source approved brand assets/font or formally record measured visual tokens, rather than claim invented values are exact.
- **Navigation:** pictographic bottom navigation with labels and a selected state where appropriate, adapted to supplier work: **Home / Orders / Catalog / Stock / More**. The PDF's **Cart** tab is customer-only and must not be copied as a supplier purchase action.
- **Status and confirmations:** explicit icon + text + hue for progress, success, warnings and errors; never use color alone. Use the distinct visual language of pages 6, 7, 9, 10 and 15 only when the actual backend status justifies it.
- **Authenticity:** use true material images/assets approved for BuildTo, not food photos or generated placeholder thumbnails in a staged release. Never reproduce PDF mock order IDs, prices, dates, fake phone numbers, ratings or “refund issued” messages as live data.
- **Presentation only:** the numbered navy banners outside phone screenshots and iOS status-bar chrome in the PDF are presentation annotations, **not** app widgets. Respect Android system insets instead of drawing a fake 9:41 clock.

## Page-by-page visual translation

| Reference page | Customer mock shown in PDF | Supplier screen applying the design pattern | Boundary |
| --- | --- | --- | --- |
| 1 | Home: navy BuildTo brand, search, hero, nearby suppliers, category cards, bottom nav | Home supplier dashboard, key actions, critical queue / stock tiles, five-tab supplier nav | No customer supplier browsing or fake metrics |
| 2 | Browse Category: search/tags, 2-column product cards, navy primary CTAs | Catalog master/product search and own listings | Supplier creates/edits listings, not shopping cart |
| 3 | Product Detail: large pack image, price, stock badge, detail rows | Own listing details: SKU, unit, price tiers, MOQ, approval and edit CTA | Stock is per warehouse and server-scoped |
| 4 | My Cart: stacked line items, quantity buttons, price breakdown | Shipment planning detail: item allocations and committed quantities | No customer cart or locally priced order |
| 5 | Checkout: stepper, address/payment choice, primary continuation | Supplier onboarding or RFQ quote multi-step wizard | Supplier does not choose a customer's payment method |
| 6 | Order Placed: check success state and navy actions | Successful listing/quote submission acknowledgement | “Submitted” is not “approved” or “paid” |
| 7 | Track Order: progress steps, blue status panel and item list | Supplier shipment stage timeline, manifest and verified OTP handover | No unsupported driver identity/contact UI |
| 8 | My Orders: filter chips, order cards, colored statuses | Supplier-owned order queue with status tabs and contextual actions | Funding verified by backend |
| 9 | Cancel Order: details, red destructive outline, support link | Restrained unpaid-only supplier rejection flow | Never permit paid/COD unilateral cancellation |
| 10 | Order Cancelled: large status icon, refund amount | Rejected/exception/return status presentation | Never promise refund timing or amount without an actual refund |
| 11 | Wishlist: clean list rows, small item image, CTA | Stock replenishment alerts / low-stock list pattern | No supplier wishlist API invented |
| 12 | Notifications: timestamped activity rows, category icons | Supplier activity/read-only alerts UI only when backed by verified V2.1 API | Old Socket.IO/FCM event contracts not assumed |
| 13 | Profile / Settings: avatar and settings rows | Supplier business/account menu, member/finance permissions and support links | Unsupported staff edit actions disabled |
| 14 | Support / Help: grouped contact/options rows | Supplier help and policy/resource views | No fake live chat or arbitrary phone number |
| 15 | Payment Success: big verified success icon, exact amount, navy CTA | Finance confirmation only after verified provider status and distinct attestation | Pending payout ≠ transfer ≠ bank-verified credit |
| 16 | Repeat Order: familiar material cards, quick CTA | Frequently managed listings/quote templates **only if supported** | No supplier repeat-customer-checkout action |

## Deliverable screen system for S01 onward

1. **Tokens:** document approved navy, orange, green/red status, canvas, text, outlines, type scale, spacing, corner radius, elevation and icon size once; no separate palette in each feature.
2. **Components:** BuildToScaffold, BuildToTopBar, BuildToPrimaryButton, BuildToOutlineButton, BuildToCard, BuildToStatusChip, BuildToProductTile, BuildToEmptyState, BuildToErrorState, BuildToSkeleton, BuildToField, BuildToBottomNavigation. Names are architectural examples, not code delivered in S00.
3. **Structure:** supplier list/detail/wizard patterns, sticky action footer when appropriate, contextual confirmations for mutations, clear save/retry/refresh behavior.
4. **Accessibility:** at least 48×48dp interaction targets, readable contrast, semantic labels and touch feedback, logical focus order, font scaling, keyboard and inset handling. No truncation/overflow at device text scale.
5. **States per API feature:** initial loading, pull-to-refresh, pagination/loading-more, empty results, offline/retry, expired session, no membership, forbidden, conflict/retry, pending/submitted, success, partial/unknown. State visuals must match BuildTo language.
6. **No appearance-for-function tradeoff:** loading must be non-deceptive; irreversible mutations confirm server result before rendering “success”; expensive visual effects must not block scrolling or performance.

## UI acceptance gates for every S01–S13 PR

- Each new/changed screen supplies screenshot evidence alongside the **specific reference PDF page(s)** and a review note of approved supplier-specific deviations.
- Flutter golden/visual tests for representative **360×800, 393×852 and 412×915 logical-pixel** phone sizes, plus 320px width and large text-scale overflow checks where widgets support those constraints. Use stable fonts, locale, network-free imagery and no time-dependent data in goldens.
- Golden baselines are reviewed, never blindly updated to silence design regressions.
- Full device pass: Android physical device/emulator, safe area, keyboard, touch targets, scroll, orientation policy, screen reader/semantics, real API states and poor-network conditions.
- S01 must deliver an approved sample of home/nav/card/action components **before** S02–S12 replicate them across the application.
- Do not sign off “exact visual match” from a low-resolution reference alone: S01 resolves any ambiguous brand font/icon/asset decisions with user-provided source assets where available. Preserve recognizable composition and high quality even when supplier behavior differs.

## Feature gate and source traceability

Design reviews cite this document and the relevant page number. Functional reviews cite `S00-API-SCREEN-MATRIX.md` and `v21_supplier_contract.json`. A feature is complete **only** when design, permissions, backend behavior, async states and automated/device tests all pass.

**S00 boundary:** these are binding future acceptance criteria. S00 does not claim the old restaurant Flutter app visually meets them.
