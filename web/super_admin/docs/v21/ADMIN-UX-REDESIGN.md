# Splyzo V2.1 administration — operational UX redesign

## Product goal
A trusted, fast, accessible administration workspace for non-technical operations personnel and reviewers. No fabricated totals, unverified financial state, role escalation, or client-side bypasses.

## Experience standards
- **Clarity:** every page states the current task, filters, freshness of information and what a click will actually do
- **Navigation:** grouped modules, current page indication, keyboard Ctrl+K quick jump and usable mobile navigation
- **Hierarchy:** strong page header, lightweight summary, filters, data table, then contextual detail/actions
- **Error handling:** human-readable problem, safe next step, backend error code and request ID close to the failed action; never silently swallow 4xx/5xx
- **Accessibility:** readable contrast, 44px interaction targets, visible keyboard focus, semantic labels, live-region errors and reduced-motion support
- **Security:** never display private storage keys, Clerk tokens, client-side financial guesses or unauthorized reviewer actions
- **Staging distinction:** visible badge; no production claims or payment execution when disabled

## Visual system
- Deep Splyzo navy (#102B4D) for navigation and primary actions
- Orange (#F26B3C) as sparing accent for active navigation and attention, not as a false action status
- Cool off-white canvas with white cards, blue-gray borders, high-contrast headings, restrained shadows
- Status semantics: pending/under-review amber, approved/verified green, rejected/suspended red, missing evidence amber/red
- Dense but readable tables: consistent headers, safe overflow on small devices, clear current selection
- Consistent spacing and typography across overview, supplier, catalog, delivery, orders, care, finance, team and audit modules

## Workflows and acceptance criteria
| Module | Task-first UX | Acceptance checks |
| --- | --- | --- |
| Overview | Live KPIs, operational queues, shortcuts | Show data source/freshness; never mislabel gateway captures as revenue |
| Suppliers | Filtered review queue, business and owner context, evidence checklist, decision | Missing/invalid documents block approval; 409 error visible beside decision, includes code/request ID |
| Catalog | Categories, brands, products and supplier listing review | Preserve optimistic version checks, show stale-state errors near action |
| Delivery | Cities, PIN coverage, promotions | Validate serviceability without inventing freight |
| Orders | Search/read-only oversight and shipment states | Keep customer PII redacted; don't enable execution actions |
| Customer care | Cases, returns and reviews | Distinguish internal notes, independent decisions and customer-visible actions |
| Finance | Settlement, COD, refunds, payout evidence | Clear maker/checker guardrails, no simulated money transfer |
| Team & access | Admin roles and grants | Show exact affected principal and reason; protect last owner |
| Audit | Searchable immutable action records | Redacted details, accessible filters, no write controls |

## Delivered in PR #69
1. Responsive global admin shell, quick module navigation and consistent V2.1 design tokens across all existing modules
2. Detailed supplier-review workbench with document readiness, defensively disabled approval, and contextual backend errors
3. Live overview refresh: concise metrics, source transparency, and real navigation into critical work queues
4. Regression coverage for evidence blockers and handling HTTP 409 with request ID

## Still required before a production-grade release
- Full browser/device QA at desktop, tablet and narrow mobile widths; visual checks on all nine modules
- Authenticated staging UAT for successful verification and all 4xx transitions, including actual private evidence downloads
- More module-specific UX refinements for catalog, delivery, orders, care, finance, team and audit (shared styling alone does not replace workflow testing)
- CI green on staging release gate and existing React regression suite
- Merge, deployment and explicit release approval; no automatic production deployment in this PR
