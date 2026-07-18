# Stage 2A Independent-Review Remediation Handover

## Release identity

- **Status:** **STAGE 2A REMEDIATION COMPLETE — STAGE 2B NOT STARTED**
- **Source branch:** `fix/stage2a-independent-review-findings`
- **Final source HEAD:** the commit containing this handover; the complete
  40-character SHA is generated from the clean committed branch tip into
  `FINAL-SOURCE-HEAD.txt` and `REVIEW-MANIFEST.json` in the review ZIP.
- **Runtime correction commit:**
  `099fa1e92c3bef7c8d27dade76a95c582b8312ed`
- **Staging-window test correction commit:**
  `293563db8f01f0f3cea5874a4d474aa3a99d4018`
- **Staging deployment repository:** `BTNew/pdc-control-board-staging`
- **Staging deployment commit:**
  `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`
- **Staging URL:** <https://btnew.github.io/pdc-control-board-staging/>
- **Staging project:** `cdsmnqxtyyoeoznmbidd`
- **Production project:** `vjdtsswhroyguxyfjdkt` — untouched
- **APP_VERSION:** `2026.07.18.02-stage2a-final-approval`
- **Migration ledger:** local/staging aligned through 027
- **Cross-platform CI:** run `29627634599` passed on Windows, Ubuntu, and macOS

The final source commit cannot literally contain its own SHA because changing
that file would create a different commit. The exporter therefore resolves the
clean branch tip after this handover has been committed and records the exact
immutable value in both package metadata files named above.

## Scope and safety boundary

Stage 2A makes workshop technicians, salespeople, sublet providers, workshop
bays, and workshop configuration authoritative in Supabase, with protected
RPCs, optimistic locking, audit events, Realtime reconciliation, controlled
browser-data import, and backup/restore coverage. It does not implement Stage
2B vehicle/booking master-data migration, AI email/oversight features, planner
Admin blocks, current-time planner changes, or a production deployment.

Production was never used as a link target, test target, recovery target,
request host, migration target, or deployment target during this remediation.

## Final contained and assignment remediation (2026-07-18)

Migrations 026–027 and the minute-based planner adapter close the final
contained review findings without changing the Stage 2A boundary:

- one authoritative planner configuration object stores integer minute clocks,
  integer durations/increments, and validated working-week, closure, break,
  overtime, and technician-leave collections;
- every planner clock Date is created through `workshopSetClock`; no fractional
  clock hour is stored or passed to Date APIs;
- closures, breaks, overtime, leave, and configurable three-to-six-day weeks
  alter real scheduling outcomes, not only mutable constants;
- historical bookings remain renderable after later closure/leave changes;
- viewer list/direct REST/Realtime reads are active-only, while
  operator/administrator hierarchy retains required inactive-row reads;
- protected assignment RPCs reject technician leave server-side;
- schedule, assigned move, assigned resize, and resume/reschedule enforce the
  complete configured interval and active-technician/leave rules;
- shared frontend create/move/resize/extension paths resolve technicians by
  stable UUID, fail closed, and retain assignment identity after Realtime
  reconciliation;
- malformed UUID and non-exact/non-round-tripping dates return structured JSON;
- email-monitor discovery and locking are portable across Windows, Linux, and
  macOS.

Final current evidence is authoritative over historical totals later in this
handover:
`review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md`.

Cross-platform CI run `29627634599` passed on Windows, Ubuntu, and macOS at
test-correction commit `293563db8f01f0f3cea5874a4d474aa3a99d4018`.
Current credential-free totals are JavaScript 40/0/2, reference-data service
44/0, and the exact backend command 60/0. Staging migration-027 checks passed
22/0; migration-026 direct REST/RPC checks remained 24/0; reference-data checks
passed 34/0; workshop live integration passed 34/0. Both preserved two-browser
flows passed with cleanup/restoration complete and zero console, CSP, page,
network, HTTP, or production-request errors.

A new isolated 001–027 clean build was not run because the account contained
only staging and prohibited production, and Docker was unavailable locally.
The prior isolated 001–025 clean build remains valid for those immutable
migrations; 026–027 were verified by staging apply, ledger parity, post-apply
dry run, static tests, direct role/RLS and mutation suites, strict validation,
function/grant inspection, protected RPC behavior, and browser acceptance.

## Independent-review findings and disposition

The original review contained 12 numbered findings. The disposition below is
explicit about what Stage 2A resolves and what remains outside this stage.

| # | Finding | Fix/disposition |
|---:|---|---|
| 1 | Production artifact omitted registration and User Management | Production artifact builder was hardened to generate/require the production-safe registration module and required UI/assets. No production artifact was deployed. |
| 2 | Shared workshop/lifecycle flags absent from production artifact | Builder validation now requires both shared-data flags in a generated production artifact. Flags were not enabled against or deployed to production. |
| 3 | Complete vehicle board remained browser-local | **Partially remediated by the approved Stage 2A boundary:** technicians, salespeople, sublet providers, bays and workshop settings are now Supabase-authoritative; their legacy localStorage keys are retired as authority. Vehicle/booking master data remains Stage 2B and is explicitly not started. |
| 4 | Administrators could bypass protected user-management RPCs | Migrations 020, 021 and 025 remove direct role-table mutation paths, revoke excess DML/TRUNCATE and function execution, preserve protected Security Definer RPCs, and add direct denial tests. |
| 5 | Disabled users were not immediately locked out | Migration 019 plus Auth/application Realtime lifecycle code subscribe each signed-in browser to its own role row; pending/disabled/rejected transitions clear operational state, unsubscribe and lock the shell immediately. |
| 6 | Review ZIP contained operational email artifacts | Export is now Git-tracked/explicit allow-list only, refuses runtime attachments/logs/backups/env/private keys/temporary folders/dependencies, scans staged content, and is independently re-extracted and scanned. |
| 7 | Production-artifact validator could pass despite failures | Validator failures are fatal for missing/referenced assets, missing registration/User Management, missing shared flags, staging/localhost leftovers, secret patterns, env/runtime/test content and staging-only files. Production deployment remains prohibited. |
| 8 | Operational export was not full Supabase disaster recovery | `docs/backup-and-disaster-recovery.md` now documents two layers: native Supabase/Postgres backup/PITR for complete recovery plus the encrypted operational export as secondary evidence. Clean-build migrations and schema/project reports prove reconstruction components. Managed PITR availability/retention still requires a production-plan decision and was not changed. |
| 9 | Restore verification overstated FK coverage | Restore derives the FK graph from the database catalog, restores applicable constraints, runs `VALIDATE CONSTRAINT`, and fails on skipped/invalid constraints, orphans, count/schema/migration mismatch. Isolated restore coverage passed. |
| 10 | Database privilege hardening incomplete | Migrations 021 and 025 revoke unnecessary table/function privileges, including browser-role TRUNCATE and default execution, then grant only intended operations. Grants/RLS report and direct API suites verify the result. |
| 11 | Account lifecycle consistency not fully constrained | Migration 020 and migration 025 validation enforce valid role/status/active combinations and ensure role helpers require an approved active identity while preserving last-active-administrator protection. |
| 12 | Important staging tests not independently reproducible | All safe staging Python tests, credential-free helpers, `.env.example`, pinned Python/npm dependency files, exact commands, fixture-reset helper and browser harness are included. Real credentials remain excluded. |

Finding 3 is intentionally not misrepresented as a complete vehicle-board
cutover: that remaining work is Stage 2B and requires a separate approval.
This handover certifies Stage 2A, not production readiness for Stage 2B scope.

## Migrations and migration-ledger repair

Migrations involved:

1. `018_account_registration_and_approval.sql`
2. `019_pdc_user_roles_realtime.sql`
3. `020_lock_down_pdc_user_roles_direct_writes.sql`
4. `021_database_privilege_hardening.sql`
5. `022_stage2a_workshop_reference_data.sql`
6. `023_stage2a_workshop_reference_rpcs.sql`
7. `024_stage2a_realtime_publication_fix.sql`
8. `025_stage2a_review_remediation_grants_rls_validation.sql`
9. `026_stage2a_final_review_remediation.sql`
10. `027_stage2a_assignment_interval_enforcement.sql`

Staging already contained the objects for 018–025, but its Supabase migration
ledger ended at 017. After object-by-object schema verification, only missing
ledger records 018–025 were marked applied using the supported Supabase CLI
`migration repair --status applied --linked` workflow. The migration table was
never edited manually and application DDL was not replayed. Post-repair local
and remote ledgers align exactly through 025, and the linked dry run returned:

```text
Remote database is up to date.
```

Migration 026 was subsequently applied normally with `supabase db push` to the
explicitly linked staging project after an encrypted pre-change backup. Local
and staging ledgers aligned through 026. Migration 027 was then applied once to
the same guarded staging project after a new verified encrypted backup. Local
and staging ledgers now align through 027; the post-apply dry run returned
`Remote database is up to date.`

Evidence:

- `review-evidence/MIGRATION-LEDGER-REPAIR-EVIDENCE.md`
- `review-evidence/post-resume/migration-ledger.txt`
- `review-evidence/post-resume/migration-dry-run.txt`

## Clean-build verification

Migrations 001–025 were applied in filename order to an isolated empty
Supabase project. The resulting application schema was compared with the
pre-pause staging schema across columns/defaults/nullability, constraints,
foreign keys, indexes, triggers, views, functions/signatures/owners/security,
grants, RLS, Realtime publication, replica identity, migration ledger and cron
state.

Result:

```text
UNEXPECTED_DIFFERENCE_COUNT=0
RESULT=PASS
```

Clean-build behavior/security totals:

- reference data: 33 passed, 0 failed;
- migration-025 behavior/security: 25 passed, 0 failed;
- privilege hardening: 4 passed, 0 failed;
- role-table lockdown: 6 passed, 0 failed;
- access matrix: 6 cells passed, 0 failed.

The isolated project `psnnswebuhnvjgghdpvt` was deleted afterward. Production
was not linked or queried. Full report:
`review-evidence/clean-build/CLEAN-BUILD-VERIFICATION-REPORT.md`.

## Pause/resume verification

Before pause, staging had an encrypted operational backup and full schema
snapshot. The backup was directly re-hashed during finalization:

- file size: 113,956 bytes;
- SHA-256:
  `86528d0d18a4ecad9aa03a991c7ef8a72de01a959bc17b6f9999c39e7b43df9b`;
- decryption/manifest verification: passed;
- migration version: 025.

After the user manually resumed staging:

- database connectivity/select health passed;
- staging status was `ACTIVE_HEALTHY`;
- application schema comparison returned zero unexpected differences;
- local/remote migrations remained aligned 001–025;
- Auth user count, IDs and email identities were unchanged (values excluded);
- Auth site URL/redirect settings were unchanged;
- Storage retained one private attachment bucket and zero objects;
- Realtime retained 22 publication tables and expected replica identity;
- project Storage/Realtime settings remained correct;
- PostgreSQL remained version 17.6; no project/Postgres version change was
  confirmed as caused by pause/resume.

Row-count deltas were zero except documented controlled-test effects:

- one synthetic workshop booking and history row present in the encrypted
  backup had been intentionally removed during final pre-pause cleanup;
- append-only audit count increased by expected remediation/test records.

Schema evidence:

- `review-evidence/post-resume/full-schema-report.json`
- `review-evidence/post-resume/schema-comparison.txt`
- `review-evidence/post-resume/grants-rls-report.json`
- `review-evidence/post-resume/realtime-publication-replica-identity-report.json`
- `review-evidence/post-resume/health-rowcount-auth-storage-continuity-safe.json`
- `review-evidence/post-resume/auth-redirect-settings-safe.json`
- `review-evidence/post-resume/project-storage-realtime-config-safe.json`

## Earlier 001–025 regression totals (historical)

| Suite | Final result |
|---|---:|
| JavaScript aggregate | **38 passed, 0 failed, 2 skipped** |
| Workshop reference-data service | **44 passed, 0 failed** |
| Backend | **48 passed, 0 failed** |
| Backup retention | **7 passed, 0 failed** |
| Scheduled backup logging | **3 passed, 0 failed** |
| Complete staging suite | **191 passed, 0 failed** |
| Workshop integration (included above) | **34 passed, 0 failed** |
| Two-browser Realtime acceptance | **passed** |
| Console errors | **0** |
| CSP errors | **0** |
| Page errors | **0** |
| Failed requests / HTTP errors | **0 / 0** |
| Production requests | **0** |

The staging aggregate is 157 successful non-workshop assertions plus 34
workshop integration assertions. Controlled workshop fixtures were cleaned
after the final run. Final packaging/documentation changes did not alter
application runtime behavior; only affected exporter/package tests and syntax
checks were rerun.

## Earlier two-browser acceptance and exact hosts (historical)

Two independently authenticated Chromium contexts joined all five Stage 2A
reference-data channels. The administrator changed
`default_booking_duration_minutes`; the controller observed it via Realtime
without refresh. The administrator restored the original value (`180`), and
the controller observed the restoration without refresh.

Exact contacted hosts:

1. `btnew.github.io`
2. `cdsmnqxtyyoeoznmbidd.supabase.co`

No request contacted `vjdtsswhroyguxyfjdkt` or any production host. Exact
machine-readable evidence:
`review-evidence/post-resume/two-browser-realtime-acceptance.json`.

## Live-state bug and fix

The reference service's successful live states are
`connected_read_only` and `connected_editable`. The planner incorrectly
required a nonexistent `ready` state, which caused valid shared workshop
settings to be ignored. The planner now accepts both real connected states as
authoritative and fails closed for unknown, loading, unavailable, inactive or
permission-denied state. Focused tests cover both success states and all
fail-closed behavior.

## CSP issue and fix

The planner legitimately generates dynamic inline layout/position styles, but
`style-src 'self'` blocked those styles. Source `index.html` and `staging.html`
now use `style-src 'self' 'unsafe-inline'`. `script-src` remains `self` only,
and the staging `connect-src` remains restricted to the staging project. Final
browser acceptance recorded zero CSP and console errors.

## Independently runnable review package

The final allow-list package contains:

- complete tracked frontend source required by Stage 2A tests;
- `test_all.js`, all Stage 2A JavaScript tests and `workshop-planner.css`;
- backend source and tests;
- all credential-free staging Python tests and safe `.env.example`;
- pinned dependency files and exact test commands;
- exact staging deployment Git archive at commit
  `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`, including deployed
  `index.html`, JavaScript and CSS assets;
- final source/deployment commit records;
- full schema, grants/RLS, Realtime/replica-identity, migration-ledger,
  post-resume and two-browser evidence;
- this handover and checksum manifest.

It excludes `.env`, service-role keys, passwords, test-user passwords,
operational backups, backup keys, real customer/email/attachment data, browser
sessions, logs, temporary directories, `node_modules` and virtual environments.

## Known limitations

1. Stage 2B vehicle/booking master-data cutover remains unimplemented and
   unstarted.
2. No production deployment or production database verification was performed;
   production readiness remains subject to separate independent approval.
3. Native Supabase managed backup/PITR availability and retention depend on
   project plan and were not changed; the custom encrypted public-table export
   remains secondary rather than full project disaster recovery.
4. Live staging and browser suites require reviewer-supplied staging
   credentials. The package contains only placeholders.
5. `test_workshop_staging_integration.py` is historically non-idempotent; the
   exported ID-scoped reset helper must run before and after it.
6. Current dynamic planner layout requires `style-src 'unsafe-inline'` for
   styles. Scripts remain protected by `script-src 'self'`.
7. Python `unittest discover` in the original active environment discovered
   zero script-style staging tests and pytest was not installed; therefore the
   exact staging commands run each script directly. The package now provides
   pinned dependencies and explicit commands.

## Rollback procedure

### Frontend staging deployment

Do not force-push. In the staging deployment repository, revert the final
compatibility commits in reverse order, review the diff, push only staging
`main`, and wait for GitHub Pages to report the resulting commit built:

```bash
git revert 38f5404b50e0b447f2390a5ef7b2cdbe2112dae6
git push origin main
```

This removes the CSP compatibility and live-state deployment fixes. The
application source branch must be reverted consistently; never leave staging
and reviewed source at mismatched runtime versions.

### Source branch

Revert the logical finalization commits on
`fix/stage2a-independent-review-findings` in reverse order. Do not merge or
push to production branches. The preserved pre-finalization status/diff is in
`C:\tmp\stage2a-finalization-evidence\` on the review workstation.

### Database

Migrations 018–027 are additive or security-hardening changes. Do not
mechanically reverse grants/RLS/constraints because that would reopen reviewed
security findings. For a staging-only recovery:

1. pause writes and verify the exact linked project is staging;
2. preserve a new schema snapshot and encrypted backup;
3. restore the verified pre-pause backup/schema into an isolated recovery
   project first;
4. compare migration/schema/count manifests;
5. only after independent approval, apply a reviewed staging-only inverse or
   restore plan.

Never use production as a rollback test or recovery target.

## Final declaration

**STAGE 2A REMEDIATION COMPLETE — STAGE 2B NOT STARTED**

Production remains untouched. Stop here for independent review. Do not begin
Stage 2B, AI features, planner Admin blocks, current-time changes or production
deployment without separate explicit approval.
