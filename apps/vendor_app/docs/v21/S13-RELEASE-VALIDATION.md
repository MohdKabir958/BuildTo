# S13 — Supplier V2.1 release QA and visual acceptance matrix

## Automated checks are not a device signoff
GitHub Actions runs pinned Flutter 3.44.9, formatting, analysis, the entire supplier regression suite, responsive test views at 320×800 / 360×800 / 393×852 / 412×915, supplier-switch isolation and the staged Flutter bundle. S02 independently compiles the actual Android Clerk staging APK.

These checks are never treated as proof that a production Clerk session worked on a real phone, that a payout reached a bank, or that the user-supplied 16-page visual reference was pixel-matched. This PR introduces repeatable release validation and blocks overclaiming.

## Manual acceptance (required evidence, not completed by CI)
| Stage | Physical-device / integration scenario | Evidence to attach |
|---|---|---|
| Identity | Native Clerk login, token refresh, signout, app resume, 401/403, revoked membership, two suppliers | Redacted device video, backend request IDs, no cross-account content |
| UI design | Compare S00 reference PDF pages 1, 2–3, 7–8, 10, 13–15 to Home, Catalog, Shipments, Orders, Care and Finance; compare at 320, 360, 393 and 412 dp and 1.5x font | Approved reference-versus-device screenshots with deviations explicitly signed |
| Listings / stock | Real catalog approval, 2 warehouses, quantity races and rejected CAS edit | Supplier and admin audit events; no negative or fabricated stock |
| Invitations | Invited-only RFQ quotes, exact decimals and conflict handling | Server state before/after, denied other-supplier access |
| Orders | Online capture versus COD selected, accept, unpaid-only refusal | Forbidden paid cancellation evidence |
| Delivery | Customer issues OTP, supplier physically verifies, invalid/expired/rate-limited cases | OTP and customer PII redacted; independent-admin exception path |
| Financials | GST invoice after dispatch, customer COD collection, independent COD review, full-return GST credit, settlement, provider payout and bank attestation | Statutory document IDs and independent reviewer evidence |
| Reviews / care | Independent return approval, receipt, review moderation | No self-approved returns, no supplier refund action |
| Adverse states | Network offline, stale session, duplicate intent, 409 conflict, slow fetch, keyboard and TalkBack | No false success or duplicate money events |
| Store release | Signed production APK/AAB, correct non-test Clerk key, production API allowlist, privacy/security review | Release owner and DevOps written approval |

Release status MUST remain **AUTOMATED-ONLY / NOT PRODUCTION SIGNED-OFF** until all required actual screenshots and independent reviews are attached. No sample test prices, bearer tokens, six-digit OTPs or bank account details belong in artifacts.

## Contract boundary
S00-UI-UX-FIDELITY.md and the original Buildto_16_Screens_Enhanced-1 (1).pdf guide presentation. Customer-only cart/checkout/wishlist UI must never be fabricated as a supplier action. No arbitrary Grozo restaurant reuse; BuildTo navy/amber system stays consistent.
