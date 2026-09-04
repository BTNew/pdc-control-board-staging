# Overnight PDC QA detailed report — 2026-09-04

Result: PASS WITH DOCUMENTED BASELINE DEBT

## Scope, containment and authoritative release

- STAGING only: `cdsmnqxtyyoeoznmbidd`.
- Production `vjdtsswhroyguxyfjdkt`: no request, query, write or deployment.
- Email/external commitments: none.
- PR: https://github.com/BTNew/pdc-control-board-staging/pull/45 (merged `d488f1f18c1058df6d068a467b7347e088e43ef8`).
- Pages and remote main: `d488f1f18c1058df6d068a467b7347e088e43ef8`; four release assets match the merge byte-for-byte.
- STAGING migration head: `20260905010200 / archived_snapshot_volatility_repair`.

## Programmatically cross-checked coverage

- Routes: 35 across 3 viewports = 105 fresh authenticated observations/screenshots.
- Interaction records: 4358 JSON and CSV rows, 818 passed, 3540 explicitly blocked.
- Synthetic transaction assertions: 26/26 passed across 15 fixtures.
- Fresh remediation verification: 15 checks across 5 routes × 3 viewports.
- Deduplicated findings: 11 total; 5 product defects resolved, 6 baseline/environment/forward-debt items remain open.

The release qualification is deliberately two-stage. The exhaustive 35-route/4,358-interaction sweep is the pre-remediation discovery baseline at candidate SHA `6fc3cd3f6392ba76c5947f6571d8fd01f4563ffa`. The final deployed SHA `d488f1f18c1058df6d068a467b7347e088e43ef8` changes only the five discovered UI surfaces plus the STAGING archived-snapshot wrapper; all five surfaces were then retested across all three viewports, the database contract was probed under an approved administrator, the complete 189-test Node suite was rerun, and deployed `index.html`, `app.js`, `styles.css` and staging config were byte-compared to the merge. The earlier exhaustive sweep is not misrepresented as having run at the final SHA.

## Defects and debt

### UI-001 — Deleted Vehicles cannot load because archived snapshot RPC returns HTTP 405

- Severity: High
- Category/classification: Functional/Network
- Status: resolved
- Reproduction/actual: Visible error: “Could not load Deleted Vehicles — cannot execute SELECT FOR SHARE in a read-only transaction (25006)”; RPC responds 405.
- Expected: Deleted vehicle data or a valid empty state loads.
- Evidence: `lanes/ui/screenshots/desktop/deleted.png`, `lanes/ui/screenshots/tablet/deleted.png`, `lanes/ui/screenshots/mobile/deleted.png`, `screenshots/remediation/desktop-deleted.png`, `screenshots/remediation/tablet-deleted.png`, `screenshots/remediation/mobile-deleted.png`
- Root cause: Migration 20260830093000 replaced the previously VOLATILE administrator snapshot with a STABLE lifecycle wrapper. Its actor helper takes a row lock, which PostgreSQL rejected in the resulting read-only function context (25006).
- Fix: Append-only STAGING migration 20260905010200 restores VOLATILE while preserving lifecycle enrichment, fixed search_path and authenticated-only ACLs.
- Retest: Fresh approved-administrator RPC returned ok/archive_vehicle_snapshot with zero items; all three deployed viewports rendered Deleted Vehicles without HTTP 405 or load error.

### UI-002 — AI Auditor is visible to administrator but its snapshot request is forbidden

- Severity: Medium
- Category/classification: Functional/Access
- Status: resolved
- Reproduction/actual: “Auditor not assessed — Your current account is not authorised to read the auditor snapshot”; GET/RPC response is 403.
- Expected: Either the visible route loads its read-only snapshot or the navigation explains/hides the additional authorization requirement.
- Evidence: `lanes/ui/screenshots/desktop/ai-auditor.png`, `lanes/ui/screenshots/tablet/ai-auditor.png`, `lanes/ui/screenshots/mobile/ai-auditor.png`, `screenshots/remediation/desktop-ai-auditor.png`, `screenshots/remediation/tablet-ai-auditor.png`, `screenshots/remediation/mobile-ai-auditor.png`
- Root cause: AI Auditor navigation looked generally available even though the existing server-owned auditor scope intentionally requires separate approval beyond the ordinary administrator role.
- Fix: Preserved fail-closed authorization and made the additional gate explicit in the visible navigation label and tooltip.
- Retest: All three deployed viewports show AI Auditor · Restricted with the separate-approval tooltip; the unscoped test administrator remains correctly denied.

### UI-003 — Narrow operational tables clip/overlap data without a visible horizontal-scroll affordance

- Severity: Medium
- Category/classification: Responsive/Visual
- Status: resolved
- Reproduction/actual: Parts row text overlaps/clips and later columns are not discoverable; Back End Data truncates after MODEL with no visible cue.
- Expected: Responsive rows reflow, or the UI clearly exposes horizontal scrolling without overlapping text.
- Evidence: `lanes/ui/screenshots/mobile/parts.png`, `lanes/ui/screenshots/tablet/backend.png`, `screenshots/remediation/desktop-parts.png`, `screenshots/remediation/tablet-parts.png`, `screenshots/remediation/mobile-parts.png`
- Root cause: Wide tables were scrollable but overlay scrollbars made overflow undiscoverable, and the Parts vehicle/customer column lacked a narrow-screen minimum width.
- Fix: Added an explicit compact-screen swipe cue and a 190px minimum for the Parts vehicle/customer column.
- Retest: Fresh tablet/mobile checks show the cue on Parts and Back End Data, preserve bounded document width, retain horizontal table overflow, and measure the Parts column at least 190px.

### UI-004 — Scrollable compact navigation hides most destinations without an affordance

- Severity: Low
- Category/classification: Responsive/UX
- Status: resolved
- Reproduction/actual: Additional planners, operational pages, and Admin are off-canvas with no visual scroll affordance.
- Expected: Users can discover that more navigation items are available.
- Evidence: `lanes/ui/screenshots/mobile/dashboard.png`, `lanes/ui/screenshots/tablet/dashboard.png`
- Root cause: Compact navigation intentionally overflowed horizontally but had no persistent discoverability cue.
- Fix: Added a compact-screen Swipe navigation for more cue without changing route access or keyboard semantics.
- Retest: Fresh tablet/mobile checks show the cue on all five sampled routes.

### UI-005 — Collected Vehicles route retains the wrong top-bar title

- Severity: Low
- Category/classification: Content/Navigation
- Status: resolved
- Reproduction/actual: Global title is “Control Board” while the section title is “Collected vehicles”.
- Expected: Global title is “Collected Vehicles”.
- Evidence: `lanes/ui/screenshots/desktop/collected.png`, `lanes/ui/screenshots/tablet/collected.png`, `lanes/ui/screenshots/mobile/collected.png`, `screenshots/remediation/desktop-collected.png`, `screenshots/remediation/tablet-collected.png`, `screenshots/remediation/mobile-collected.png`
- Root cause: The route title map omitted collected, so navigation fell back to Control Board.
- Fix: Added the Collected Vehicles title-map entry.
- Retest: Fresh deployed desktop/tablet/mobile checks return pageTitle=Collected Vehicles.

### REL-BASE-001 — Duplicate Supabase Preview integrations disagree

- Severity: Medium
- Category/classification: baseline_environment
- Status: open
- Reproduction/actual: Preview rgrwkufllnlijmdtfhxf completed configuration, migrations, seeding and Edge Functions; xvflalqbfdxbelerhtjg failed release_history/014 with SQLSTATE 42P01 and left the PR status context failed.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/raw/pr31-comments.log`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

### REL-BASE-002 — Full Python suite is not hermetic

- Severity: Medium
- Category/classification: baseline_environment
- Status: open
- Reproduction/actual: Tests depend on absent pdc-emails profile files, historical fixtures, and a legacy staging-bootstrap path. Runnable total: 359 passed, 58 skipped, 22 failed, 3 errors, 304 subtests passed; three additional files fail collection before this runnable pass.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/raw/python-full-runnable.log`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

### REL-BASE-003 — Three legacy immutable digest assertions drift

- Severity: Low
- Category/classification: baseline_test_drift
- Status: open
- Reproduction/actual: Digest assertions fail in final email-AI remediation, email-monitor planner trust binding, and monitor successor 504 migration. These predate the current PDC-14 release and are outside its changed paths.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/raw/python-full-runnable.log`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

### REL-BASE-004 — Large intentional SECURITY DEFINER surface requires inventory

- Severity: Medium
- Category/classification: baseline_security_debt
- Status: open
- Reproduction/actual: Current advisor result contains 455 authenticated SECURITY DEFINER warnings. The provenance/lifecycle cache keys are unchanged from the prior independent audit and pass the expanded fail-closed matrix; broader inventory remains release debt.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/advisor-results.json`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

### REL-BASE-005 — Explicit Data API grants must be standardized before 2026-10-30

- Severity: Low
- Category/classification: forward_compatibility
- Status: open
- Reproduction/actual: STAGING still has broad public-schema default ACL rows. The 14 RLS-disabled public tables currently expose no SELECT to anon/authenticated, but future migrations must declare grants explicitly before Supabase's existing-project rollout.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/advisor-results.json`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

### REL-BASE-006 — PDC-14 role-history RLS policy uses per-row auth evaluation

- Severity: Low
- Category/classification: baseline_performance
- Status: open
- Reproduction/actual: Performance advisor flags auth_rls_initplan for PDC administrators reading pdc14_parts_coordinator_role_history. WARN total is unchanged from the prior audit.
- Expected: Baseline/debt item remains documented; no release regression was expected.
- Evidence: `lanes/release/advisor-results.json`
- Root cause: Pre-existing environment, test, security-inventory or forward-compatibility debt; not introduced by this remediation.
- Fix: No product-code change in this integration; retained as open baseline/debt.
- Retest: Reclassified against fresh tests/advisors and retained in the final issue register.

## Transaction and invariant summary

The transaction lane passed import/idempotency, identity edits, location movement, workshop booking/rescheduling, admin blocks, Parts/work/Sublet state, overlap behavior, Pit/QC gates, archive/restore, authorization denial, stale-version denial and idempotent replay. Exact assertion records are in `transaction-ledger.json`.

Fresh global STAGING scans found zero `QA-OVERNIGHT-20260904` rows, zero synthetic actor rows, zero synthetic orphan references and no retained fixtures. Real vehicle cardinality is 2 before/after. `[REDACTED_STOCK_A]` remains version 12 at QC with the same identity/update timestamp; `[REDACTED_STOCK_B]` remains version 3 at YH with the same VIN, registration, customer and Job Card.

## Responsive and browser retest

Deleted Vehicles now returns a valid empty snapshot without HTTP 405. Collected Vehicles has the correct global title. Parts and Back End Data expose compact-screen horizontal-scroll cues; Parts preserves a 190px vehicle/customer column. Compact navigation exposes a swipe cue. AI Auditor remains fail-closed for an ordinary administrator and now visibly states that separate approval is required. Three 403 responses are expected from the deliberately unscoped verifier; there are zero 405s, page errors or Production requests.

## Tests, CI, Preview and advisors

- Focused Node 6/6; full Node 189/189.
- Focused Python 16 passed / 5 expected skips.
- Full Python baseline reproduced exactly: 359 passed, 58 skipped, 22 failed, 3 errors and 304 subtests passed; failures remain missing external profile/fixtures and legacy digest/expectation drift.
- Staging Integrity succeeded at `d488f1f18c1058df6d068a467b7347e088e43ef8`; Pages succeeded at `d488f1f18c1058df6d068a467b7347e088e43ef8`.
- Supabase Preview remains split: `drcedvskqppfeiunxkhq` fully green; duplicate `tfxlazlxzsyplmryrtpx` fails the documented release_history/014 missing-relation baseline.
- Fresh advisors: security 911 total / 456 WARN; performance 1014 total / 3 WARN. WARN deltas are zero versus the release lane.

## Untested / blocked / remaining risks

- Outbound email, external communications, uploads, destructive production actions and real-vehicle mutation were intentionally blocked.
- The standalone external-completion SQL mutation test was not run; its static/pglast contracts and Preview migration path were exercised.
- The duplicate Preview integration and non-hermetic Python baseline remain open and are not masked as green.
- Existing SECURITY DEFINER inventory and explicit Data API default-grant forward work remain open; this repair did not weaken RLS or ACLs.
