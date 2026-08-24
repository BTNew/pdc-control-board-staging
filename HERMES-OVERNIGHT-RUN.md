# HERMES OVERNIGHT PDC HARDENING RUN

## Run identity
- Status: RUNNING
- Start UTC: 2026-08-24T10:54:31Z
- End UTC: 2026-08-24T20:54:31Z
- Start Perth: 2026-08-24T18:54:31+08:00
- End Perth: 2026-08-25T04:54:31+08:00
- Branch: `hermes/overnight-pdc-hardening-20260824`
- Starting commit: `ac06394736b55220e7425322fc53e9b9dadc3fdd`
- Worktree: `C:\tmp\pdc-overnight-hardening-20260824`
- Live staging hostname: `btnew.github.io/pdc-control-board-staging`
- Live Pages commit at start: `c95e0dec3064eebfb88d8f8367a326ca77fcc6b7` (`built`)
- Staging Supabase project: `cdsmnqxtyyoeoznmbidd`

## Absolute safety boundary
- Production access: BLOCKED. This worktree has no `.env` files; the browser config contains only the staging URL and publishable key; no service-role key or database password is present.
- A worktree sentinel and code guard reject every non-staging Management API endpoint. The Production fingerprint program exits locally with `PDC_OVERNIGHT_PRODUCTION_ACCESS_STRUCTURALLY_BLOCKED` before any request.
- Database identity: exact staging sentinel present; Production sentinel absent.
- Monitor: stopped.
- Active monitored mailboxes: 0.
- Active staging activation writers: 0.
- Outbound notification rows: 0; pending outbound notifications: 0.
- Existing staging vehicles: 153, treated as protected/non-test records. They must never be mutated by this run.
- Existing synthetic fleet at start: 0.
- Mutations are permitted only for synthetic records whose identifying fields begin `HERMES-TEST` and which are recorded below.
- No reset, purge, truncate, irreversible delete, external communication, credential change, Production query/deploy, force-push or history rewrite.
- Environment proof: `_overnight_evidence/environment-proof.json`.

## Synthetic records created
None yet.

## Authorised synthetic fleet (not created yet)
Run ID: `HERMES-TEST-RUN-20260824`. Only these exact stock identities may be created by migration 363; every customer, Job Card, scenario name and description must also begin `HERMES-TEST`.

| No. | Stock | Intended scenario |
|---:|---|---|
| 1 | `HERMES-TEST-001` | baseline intake/editing |
| 2 | `HERMES-TEST-002` | IT ETA/location transition |
| 3 | `HERMES-TEST-003` | YH latch and movement |
| 4 | `HERMES-TEST-004` | PMB bay/chip movement |
| 5 | `HERMES-TEST-005` | exact-minute Fitting booking |
| 6 | `HERMES-TEST-006` | exact-minute Electrical booking |
| 7 | `HERMES-TEST-007` | multi-stage booking/conflict |
| 8 | `HERMES-TEST-008` | Parts lifecycle |
| 9 | `HERMES-TEST-009` | Parts stoppage/recovery |
| 10 | `HERMES-TEST-010` | Sublet queued/booked/returned |
| 11 | `HERMES-TEST-011` | multi-provider Sublet |
| 12 | `HERMES-TEST-012` | QC ordering negative case |
| 13 | `HERMES-TEST-013` | RFT separation |
| 14 | `HERMES-TEST-014` | Completed separation |
| 15 | `HERMES-TEST-015` | duplicate-submit/idempotency |
| 16 | `HERMES-TEST-016` | stale-version conflict |
| 17 | `HERMES-TEST-017` | two-session same-record race |
| 18 | `HERMES-TEST-018` | role/permission negative cases |
| 19 | `HERMES-TEST-019` | navigation/mobile/accessibility |
| 20 | `HERMES-TEST-020` | full final regression journey |

## Quantitative counters
- Synthetic vehicles: 0 / approximately 20
- Full Intake/Inception-to-RFT journeys: 0 / 5
- Consecutive final clean journeys: 0 / 3
- Board/chip movements: 0 / 100
- Booking movements/adjustments: 0 / 50
- Invalid movement attempts: 0 / 20
- Duplicate-submit tests: 0 / 20
- Parts changes: 0 / 25
- Sublet changes: 0 / 20
- QC/RFT out-of-order attempts: 0 / 10
- Two-session scenarios: 0 / 10
- Field/validation scenarios: 0 / 30

## Bugs
### Discovered
None yet.

### Fixed
None yet.

### Open
None yet.

## Checkpoints
### Checkpoint 000 — 2026-08-24T10:54:31Z (elapsed 00:00)
- Git commit: `ac06394736b55220e7425322fc53e9b9dadc3fdd`
- Areas tested: staging identity, repository/deployment identity, database sentinel, Monitor/mailbox/writer containment, outbound notification queue, Production-access guard.
- Synthetic records created: none.
- Bugs discovered: none.
- Bugs fixed: none.
- Tests passing: staging identity proof; Production access guard negative test.
- Tests failing: none in safety proof.
- Blockers: the staging database contains 153 pre-existing protected records, so all mutation testing must use a narrowly isolated `HERMES-TEST` fleet and guarded synthetic-only contracts.
- Exact next action: commit safety harness, run baseline static/automated checks, inventory synthetic-safe RPCs and create a guarded synthetic fleet controller only after its exact scope and rollback/archive path are proven.

### Checkpoint 001 — 2026-08-24T10:59:59Z (elapsed 00:05)
- Git commit: `bfb2047e3c85bfa8b5045e3eb1e3b9ef48f764c2`
- Areas tested: re-proved live staging hostname/banner/Pages commit/project sentinel; verified Production fingerprint execution is structurally blocked before network access; scheduled durable 20-minute worker checkpoints and the end-of-run report.
- Synthetic records created: none.
- Bugs discovered: none yet.
- Bugs fixed: none yet.
- Tests passing: environment proof, non-staging endpoint guard, JavaScript syntax check, all 33 Node regression scripts, and all 30 Python regressions on the project interpreter.
- Baseline runner issue: the background launcher selected Hermes' bundled CPython without `openpyxl`; the project interpreter already had `openpyxl 3.1.5`, and its immediate rerun passed 30/30. No test was weakened or skipped.
- Independent read-only inventories running: synthetic-safe contracts and baseline coverage.
- Blockers: no mutation is permitted until the synthetic bootstrap path is isolated from the 153 protected pre-existing staging vehicles and exact authorised RPCs are established.
- Exact next action: finish baseline aggregation, record failures honestly, inventory authenticated contracts, then design and test a guarded append-only HERMES-TEST fleet bootstrap without touching existing rows.

### Checkpoint 002 — 2026-08-24T11:07:38Z (elapsed 00:13)
- Git commit: `742e1c6a6c4344fe1ac2d6c5c90e405e3c951d74`
- Areas tested: complete route/test/build inventory; source-level audit of authenticated creation, work-state, booking, Parts, Sublet, lifecycle, QC/RFT and archive/restore contracts; read-only deployed schema/constraint/trigger inventory for `vehicles` and `vehicle_work_items`.
- Synthetic records created: none.
- Bugs discovered: direct synthetic bootstrap is safely blocked—both existing creation paths require retained provider/email evidence and an active stage writer, while this run deliberately has zero active writers. Existing generic mutation RPCs also lack a server-side `HERMES-TEST` registry gate, and QC sign-off may enqueue notifications.
- Bugs fixed: none yet; unsafe reuse of production-like intake contracts was rejected rather than bypassed.
- Tests passing: all first-party JavaScript parses; 33/33 Node tests; 30/30 Python tests on the project interpreter.
- Baseline limitations: static GitHub Pages app with no package manifest, bundler, lint configuration, type checker or production-build command. Current tests are mostly source/SQL contract checks; there is no browser E2E, two-session race harness or accessibility runner. Dedicated Sublet and RFT runtime coverage is absent.
- Blockers: safe mutation requires a guarded append-only staging migration that registers this run's synthetic identities, creates only prefix-validated test vehicles, suppresses external notifications, and exposes synthetic-only wrappers/readback before any lifecycle testing.
- Exact next action: implement and independently review the smallest guarded bootstrap/registry migration, then authenticate through a staging operator/admin account, create the 20 named synthetic scenarios idempotently, and verify that pre-existing vehicle/history/notification counts are unchanged except for the exact registered synthetic scope.

### Checkpoint 003 — 2026-08-24T11:26:09Z (elapsed 00:31)
- Git commit: `114901f7d0e35ae62068ff719e6df13cf7875796` (already pushed to the overnight branch).
- Areas tested: environment proof re-passed against exact staging; source contract and independent least-authority review of migration 363; live read-only schema confirmation for vehicle, Monitor and Workshop stage columns; canonical active work keys inventoried.
- Synthetic records created: none. The exact 20-stock allowlist is now recorded above before any mutation.
- Bugs discovered: migration 363 accepts caller-supplied prefixed scenario details instead of binding the exact logged catalog; bootstrap authority includes Operator rather than Administrator only; runtime containment checks are not locked against mailbox/writer/notification races and omit the four disabled pilot flags; protected pre-existing rows are count-checked but not byte-digest checked. Generic lifecycle RPCs remain unsafe for this run because they accept arbitrary vehicle UUIDs.
- Bugs fixed: no live fix yet; unsafe deployment/bootstrap was stopped. The independent review and exact live schema read prevented commissioning an under-scoped controller.
- Tests passing: environment proof; 34 existing Node source contracts including the new migration contract; 30/30 Python regressions from the last complete baseline; read-only active Workshop key inventory (`PARTS`, `bus4x4`, `tint`, `hoist`, `fitting`, `fabrication`, `electrical`, `tyre`, `pitInspection`, `sublet`).
- Tests failing: no executed test failure; migration 363 is source-only and deliberately not deployed because the review found four containment/authority gaps.
- Blockers: none for local repair. Live mutation remains blocked until the exact catalog, Administrator-only authority, race locks, full pilot containment and protected-row digest are enforced and retested.
- Quantitative counters: synthetic 0/20; journeys 0/5; board movements 0/100; booking movements 0/50; invalid attempts 0/20; duplicates 0/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 0/30.
- Exact next action: harden migration 363 and its regression contract around the exact catalog and race/digest gates, independently review the exact diff, then deploy through the guarded staging migration controller and perform Administrator-authenticated bootstrap/readback only if every proof remains green.

## Final report
Pending until the ten-hour end time.
