# Final contained Stage 2A verification

Date: 2026-07-18

## Identity and safety

- Source branch: `fix/stage2a-independent-review-findings`
- Immutable correction base: `f2c44a09a7ceeb9b9838d9b0dd00eb0b5285f519`
- Runtime correction commit: `099fa1e92c3bef7c8d27dade76a95c582b8312ed`
- Staging-window test correction commit: `293563db8f01f0f3cea5874a4d474aa3a99d4018`
- Final package source HEAD is generated from the final clean commit and recorded in `FINAL-SOURCE-HEAD.txt` and `REVIEW-MANIFEST.json` inside the ZIP.
- Staging deployment commit: `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`
- Staging URL: <https://btnew.github.io/pdc-control-board-staging/>
- Linked database project during migration: `cdsmnqxtyyoeoznmbidd` only.
- Production project `vjdtsswhroyguxyfjdkt` was not linked, queried, migrated, deployed, or contacted by either browser acceptance.
- No merge occurred. Stage 2B, AI, Admin planner blocks, current-time work, unrelated planner redesign, and production deployment were not started.

## Migration 027

`027_stage2a_assignment_interval_enforcement.sql` was applied to staging after an explicit project-ref guard and verified encrypted pre-change backup.

- Backup run: `da03db06-2670-4ba8-af1f-9d7d799c81ac`.
- Backup size: 137,400 bytes.
- Backup SHA-256: `3499ce5ae0dee5c5e3f0b8f1d3f8b837e755c259afd432401c6961b28b3a3890`.
- Decrypted backup migration version: `026`; 40 table exports, manifest hash, and row counts verified.
- Pre-apply dry run named only migration 027.
- Local/remote ledgers aligned through 027 after apply.
- Post-apply dry run: `Remote database is up to date.`
- A local Docker-unavailable pg-delta catalog-cache warning did not affect the remote apply; CLI exited 0 and independent SQL/ledger/function/grant checks passed.
- Migration 027 staging suite: **22 passed, 0 failed**.
- Migration 026 direct REST/RPC suite remained **24 passed, 0 failed**.
- Configuration values were restored exactly; synthetic rows remaining: zero.

Migration 027 preserves the existing transactional and optimistic-conflict behavior while enforcing active-technician and technician-leave checks on schedule, assigned move, assigned resize, and resume/reschedule interval mutation paths. Configuration-window RPC validation now rejects invalid exact dates, unknown scope/day values, and conflicting scope/day values with structured errors.

## Frontend correction

The shared planner now:

- resolves a selected technician from the stable reference UUID before the defensive snapshot fallback;
- normalizes a blank selection to `null`;
- blocks unresolved, inactive, and leave-conflicting selections before dispatch;
- retains selected technician name and UUID after authoritative snapshot reconciliation;
- validates the full proposed interval for closures, non-working days, breaks, configured overtime, working boundaries, and technician leave;
- applies equivalent validation to shared planned/live move, resize, and extension paths.

Focused shared scheduling regression: **7 passed, 0 failed**.

## Test totals

### Cross-platform CI

GitHub Actions run: <https://github.com/BTNew/pdc-control-board/actions/runs/29627634599>

At source `293563db8f01f0f3cea5874a4d474aa3a99d4018`, Windows, Ubuntu, and macOS all passed the Stage 2A review workflow, including the JavaScript aggregate, exact documented backend command, planner-focused checks, reference-data service checks, and platform-native lock behavior.

Machine-readable result: `review-evidence/final-contained/cross-platform-ci-run.json`.

### Local credential-free

- JavaScript aggregate: **40 passed, 0 failed, 2 skipped**.
- Reference-data service internal assertions: **44 passed, 0 failed**.
- Exact documented backend module set: **60 passed, 0 failed**.
- Planner configuration, planner shared mode, shared actions, shared assignment, migration static checks, syntax/compile, package-builder tests, and `git diff --check`: passed.

### Staging

The complete documented staging command set passed:

- Migration 027 focused suite: **22 passed, 0 failed**.
- Migration 026 direct REST/RPC suite: **24 passed, 0 failed**.
- Reference-data live suite: **34 passed, 0 failed**.
- Workshop live integration: **34 passed, 0 failed**.
- Account approval, own-row lockout, user-role lockdown, privilege hardening, QC/RFT/collected, role matrix, backup/restore, Stage 2A importer, notification worker, and fixture-reset checks: passed.

## Two-browser acceptance

Two independently authenticated browser contexts completed both focused acceptance flows.

Configuration/realtime flow:

1. Administrator changed `day_start_time` to `07:30`.
2. Browser B rendered `7:30 am` through Realtime.
3. Administrator added synthetic closure `2099-01-05`.
4. Browser B rendered that day as closed and non-droppable.
5. Both settings were restored and Browser B observed the restorations.

Assignment flow:

1. Administrator created a uniquely tagged active synthetic technician.
2. Operator selected that technician in the real scheduling form and created a controlled synthetic booking.
3. Both browsers observed the same booking ID and retained the same technician name and UUID after authoritative Realtime reconciliation.
4. Administrator added leave for the technician.
5. Operator attempted a real planner-form move onto the leave date; the move was blocked before the move RPC and the authoritative booking interval remained unchanged.
6. Leave, controlled booking/history, and technician rows were cleaned in `finally`; independent SQL verification found zero synthetic rows.

Both flows recorded:

- console errors: 0;
- CSP errors: 0;
- page errors: 0;
- failed requests: 0;
- HTTP errors: 0;
- production requests: 0;
- contacted hosts: `btnew.github.io` and `cdsmnqxtyyoeoznmbidd.supabase.co` only.

Machine-readable results:

- `review-evidence/final-contained/two-browser-planner-acceptance.json`
- `review-evidence/final-contained/two-browser-assignment-acceptance.json`

## Staging deployment parity

Only the explicit allow-list was deployed: `index.html`, `app.js`, and `workshop-planner.js`. The staging-specific CSP, zero-data source, and staging Supabase config reference were preserved.

GitHub Pages reported deployment commit `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6` as built. Live `index.html`, `app.js`, and `workshop-planner.js` each matched the corresponding deployment Git blob byte-for-byte. The live version is `2026.07.18.02-stage2a-final-approval`.

## Clean-build availability

The account contained only staging and production projects. Production was prohibited, and staging was the reviewed target; therefore no free isolated Supabase project was available for a new 001–027 clean build. Docker was unavailable locally. The previously completed isolated 001–025 clean build remains valid evidence for those immutable migrations. Migrations 026 and 027 were instead verified by static tests, linked dry runs, real staging application, ledger parity, function/grant inspection, role/RLS tests, focused mutation tests, full staging regression, and two-browser acceptance. This limitation is stated rather than substituting a production or staging reset.
