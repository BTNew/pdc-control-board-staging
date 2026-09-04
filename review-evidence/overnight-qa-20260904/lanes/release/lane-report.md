# Release/security diagnostic lane — t_95939b14

Classification: PASS_WITH_BASELINE_DEBT
Environment: STAGING cdsmnqxtyyoeoznmbidd only
Authoritative main/deployed SHA: `85bdc68513e0c1c6efee110712731e9be958374b`
Completed: 2026-09-04T21:53:00+08:00

## Release

- `origin/main`, GitHub Pages deployment 6265162696, Pages run 33877381280, and the live deployment all resolve to `85bdc68513e0c1c6efee110712731e9be958374b`.
- Pages build/deploy/status and Staging Integrity run 33877383599 succeeded.
- Six release-critical assets match Git blobs byte-for-byte: index.html, app.js, STAGING config, styles.css, vehicle-requirements-guard.js, and workshop-planner.js.
- PR #31 is merged. Staging Integrity and CodeRabbit passed. The Supabase Preview status is a disclosed split baseline result: one preview project fully bootstrapped, while a duplicate preview failed at release_history/014 because `public.vehicle_intelligence_summaries` was absent.
- Main has no branch protection and no branch rules; four current main checks succeeded and the main-branch Supabase Preview check was skipped.

## Tests

- Focused PDC-14 Node: 6/6 passed.
- Full Node: 184/184 passed.
- Focused Python/SQL contracts: 16 passed, 5 expected live skips.
- Transactional STAGING authorization matrix: 8/8 passed; seven denied identities/scopes returned no data, the approved target succeeded, and the U158318 row fingerprint remained unchanged.
- Full runnable Python baseline: 359 passed, 58 skipped, 22 failed, 3 errors, 304 subtests passed. Failures are separated in `issue-register.json`: missing external profile/bootstrap/fixture dependencies, three stale digest assertions, and one legacy historical-adapter expectation mismatch. No failure touches the PR #31 paths or reproduces in the focused/full Node release loops.
- The sole standalone SQL test mutates external-completion business state and was intentionally not run under this read-only lane. SQL contracts were exercised by pglast-backed tests and Supabase Preview migrations.

## STAGING security

- Migration head: `20260904011400 / pdc14_location_replay_partial_cleanup_identifier_repair`.
- Provenance RPC remains SECURITY DEFINER with fixed `search_path=pg_catalog, public`; EXECUTE is authenticated-only. Anon/service-role EXECUTE are denied and the obsolete two-argument overload is absent.
- Lifecycle-history table has RLS and FORCE RLS; anon/authenticated have no direct SELECT.
- Authorization outcomes: no role/inactive/pending/UUID-email mismatch = forbidden; wrong dealer = dealer_scope_denied; unauthenticated = unauthorized; invalid target = vehicle_not_found; approved target = ok. No denied result contained `data`.
- U158318 remained version 3, VIN JTFHB8CP806024409, registration 1HJX697, YH, customer/salesperson/job-card identity unchanged before/after probes. Fresh read-back confirmed 18 operation rows / 58.90 hours, zero-hour OP9/OP14/OP15, seven required and zero completed work groups, and zero workshop bookings.

## Advisors and current Supabase guidance

- Security: 909 total (456 WARN, 453 INFO). WARN count is unchanged from t_59b62999; +2 INFO are RLS-enabled/no-policy cleanup-history tables.
- Performance: 1016 total (3 WARN, 1013 INFO). WARN count is unchanged; INFO is -1.
- Current advisor docs include authenticated SECURITY DEFINER and RLS checks. The April 2026 changelog requires explicit Data API grants for newly created public tables on existing projects from 2026-10-30. Current STAGING has 14 RLS-disabled public tables but zero with anon/authenticated SELECT; broad default ACLs remain forward-compatibility debt.

## Containment and verdict

No code, migration, merge, deployment, Production request, email request, or persistent STAGING mutation was performed. Transactional role probes were rolled back and exact before/after U158318 fingerprints match. No introduced product regression was found. Release baseline passes with six documented baseline/environment/forward-debt issues for downstream integration.

Machine evidence: `test-results.json`, `deployment-verification.json`, `advisor-results.json`, `issue-register.json`, and bounded logs under `raw/`.
