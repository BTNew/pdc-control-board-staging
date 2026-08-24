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
- Run `HERMES-TEST-RUN-20260824` was authenticated as the isolated staging Administrator and created exactly `HERMES-TEST-001` through `HERMES-TEST-020` at 2026-08-24T12:32:15Z.
- Authoritative results: 20 registry rows, 20 immutable bootstrap events, one receipt, 20 synthetic vehicles and 26 incomplete synthetic work items; no bookings, Parts receipts, Sublet bookings, completion/QC/RFT evidence or notifications were created.
- Exact replay returned the same receipt with `replay:true`; changed-payload replay was rejected.
- The 153 protected vehicle rows retain exact digest `3d5ec39d15408cc7443312a5d0974ba1ed8250a5484228bc932bb491f8666875` before and after bootstrap.

## Authorised synthetic fleet (created and registry-bound)
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
- Synthetic vehicles: 20 / 20
- Full Intake/Inception-to-RFT journeys: 0 / 5
- Consecutive final clean journeys: 0 / 3
- Board/chip movements: 0 / 100
- Booking movements/adjustments: 0 / 50
- Invalid movement attempts: 2 / 20
- Duplicate-submit tests: 2 / 20
- Parts changes: 0 / 25
- Sublet changes: 0 / 20
- QC/RFT out-of-order attempts: 0 / 10
- Two-session scenarios: 0 / 10
- Field/validation scenarios: 4 / 30

## Bugs
### Discovered
- The first wrapper candidate exposed three runtime contract defects before any synthetic write committed: PostgREST could not invoke unnamed façade parameters; Sublet history was ordered by nonexistent `id` instead of `history_id`; and `SELECT r INTO` attempted to cast the composite registry row into its first UUID field.

### Fixed
- Migration 363 was hardened through two independent review rounds: fail-closed singleton containment, conflicting locks/revalidation, exact catalog/identity collision closure, same-set protected digest, canonical readback drift rejection, truthful durable replay, two set-based authoritative inserts and receipt-bound shared revision delta `+2`.
- Migration 364 repaired the authenticated Vehicle Locations projection without changing vehicle data or privileges: the established snapshot now also admits only exact migration-363 registry-bound rows whose static identities and synthetic source contract still match. Authenticated UI readback is now `173 of 173`, including all 20 synthetic vehicles, while the 153 protected-row digest remains unchanged.
- Migrations 365-368 installed exact registry-bound mutation façades, actor/idempotency/version receipts, exact-target route guards, cross-relation protected/sibling digests, zero-notification QC/RFT handling, PostgREST argument names, canonical Sublet-history ordering and correct registry rowtype assignment. Scenario 001 Apply/replay/negative probes then passed live.

### Open
None at this checkpoint. Registry-bound synthetic stress mutation is now commissioned; protected/pre-existing records remain outside scope.

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

### Checkpoint 004 — 2026-08-24T11:37:35Z (elapsed 00:43)
- Git commit at review: `4233bd8676e06c350159b8fca3ce48702e04c258` (pushed); truthful replay correction is the current local diff pending this checkpoint commit.
- Areas tested: exact 20-spec catalog binding, Administrator-only bootstrap authority, locked Monitor/pilot/mailbox/writer/notification containment, full protected-vehicle digest, collision closure, immutable RLS registry/receipts/events, idempotency, live SQL parse/execution in an explicit rollback transaction, and independent final source review.
- Synthetic records created: none. Migration head remains 362; rollback validation was followed by a fresh environment proof showing 153 protected vehicles, 0 synthetic vehicles and 0 notifications.
- Bugs discovered: the second independent review found that existing statement-level vehicle/work-item triggers would update the shared Realtime revision singleton 46 times for the current row-by-row bootstrap. That non-synthetic bookkeeping side effect was not explicitly locked, bounded or receipt-verified. The review also found replay responses incorrectly retained `replay:false`.
- Bugs fixed: exact catalog SHA-256 `0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16` is enforced; bootstrap is Administrator-only; all containment surfaces are locked and all four pilot flags checked; protected rows receive full before/after byte-digest proof; replay now returns `replay:true`; source tests forbid any direct pre-existing vehicle UPDATE.
- Tests passing: 34/34 Node contracts; 30/30 Python regressions; targeted migration test after replay fix; exact migration SQL executed successfully inside an explicit staging rollback; post-rollback environment proof unchanged.
- Tests failing: independent final review is `BLOCK` solely on the unbounded/unreceipted shared revision side effect. No migration or synthetic data was committed live.
- Blockers: migration 363 must be refactored to set-based vehicle/work-item inserts and receipt-bind the exact two expected revision bumps before deployment. Generic lifecycle RPCs still require synthetic-registry wrappers before they may be used.
- Quantitative counters: synthetic 0/20; journeys 0/5; board movements 0/100; booking movements 0/50; invalid attempts 0/20; duplicates 0/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 0/30.
- Exact next action: refactor the bootstrap into one set-based vehicle INSERT and one set-based work-item INSERT, lock/read/assert the Realtime revision singleton at exact +2, include its before/after values in the immutable receipt, rerun rollback execution and independent review, then deploy only if approved.

### Checkpoint 005 — 2026-08-24T12:35:27Z (elapsed 01:40)
- Git commit at bootstrap: `09c22953720e3c6135231e9d216d31f5fbec0477`; migration SHA-256 `9b61557dc511bc762ee954ac211fd5bcb00618fa136ae381f244366da8cc6560`.
- Areas tested: final exact-SHA specification and quality/security approvals; guarded staging migration apply and ledger readback; Administrator-authenticated exact-20 bootstrap, canonical readback, exact replay, mismatched replay rejection, protected-row digest, revision delta, notification/evidence isolation and authenticated Vehicle Locations capture.
- Synthetic records created: exact registry-bound `HERMES-TEST-001` through `HERMES-TEST-020`; 26 incomplete work items.
- Bugs discovered: normal authenticated Board projection shows only 156 total vehicles, although authoritative staging has 173 (153 protected + 20 synthetic), so 17 synthetic vehicles are absent from the normal Board snapshot/projection.
- Bugs fixed: all migration-363 review findings, including time-durable replay after ETA expiry.
- Tests passing: 34/34 Node, 30/30 Python, all JavaScript syntax, 35-statement SQL parse, migration ledger readback, authenticated bootstrap/readback/replay, protected digest unchanged, synthetic bookings/Parts/Sublet/notifications all zero.
- Authoritative post-state: vehicles 173; synthetic 20; protected 153; work items 380 (26 synthetic); registry 20; events 20; receipts 1; shared revision 90389→90391; notifications 0; Monitor stopped; active mailboxes/writers 0.
- Blockers: lifecycle stress mutation remains blocked until the Board projection includes all 20 registry-bound synthetic vehicles and synthetic-only wrappers prevent generic lifecycle RPCs from touching protected UUIDs.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 0/100; booking movements 0/50; invalid attempts 0/20; duplicates 1/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 0/30.
- Exact next action: repair and regression-test the staging Board snapshot/projection for registry-bound synthetic rows, add synthetic-only mutation wrappers, then resume lifecycle/workshop/Parts/Sublet/QC/RFT stress testing.

### Checkpoint 006 — 2026-08-24T12:50:04Z (elapsed 01:55)
- Git commit: `9fc1919fe0cfa549071bec93506bdc250e44d4e4`; migration 364 SHA-256 `99b20e7704000789d5597657cf89accb3b533e34321d8cf30881938938ade27d`.
- Areas tested: exact predecessor-function drift binding; staging/Monitor/mailbox/writer/notification containment; rollback SQL execution; independent exact-commit projection/security review; guarded migration apply and ledger readback; authenticated live Vehicle Locations projection; authoritative protected-row digest and post-migration environment proof.
- Synthetic records created: none this checkpoint; exact existing `HERMES-TEST-001` through `HERMES-TEST-020` fleet only.
- Bugs discovered: no new defect. Root cause of the open projection defect was the established pre-168 snapshot predicate, which admitted only email-receipt, required-Sublet or retained-Sublet rows; only three synthetic scenarios met that predicate.
- Bugs fixed: migration 364 adds one exact registry/source-contract-bound read projection branch. It performs no application-data DML and preserves the predecessor function owner/ACL. A first independent review blocked an unnecessary `service_role` revoke; that privilege change was removed before commit, and the exact-commit re-review approved.
- Tests passing: focused Node projection contract; JavaScript syntax for snapshot consumer and app; 17-statement live rollback execution; exact-commit independent `APPROVE`; migration apply/ledger readback; authenticated UI `173 of 173`; authoritative totals 173 vehicles / 20 synthetic; protected digest unchanged at `3d5ec39d15408cc7443312a5d0974ba1ed8250a5484228bc932bb491f8666875`; notifications 0; Monitor stopped; active mailboxes/writers 0.
- Tests failing: none in this focused projection repair. Full aggregate regression was not rerun in this checkpoint.
- Blockers: no projection blocker remains. Mutation stress is intentionally blocked until server-side synthetic-only wrappers prevent generic contracts from accepting protected UUIDs.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 0/100; booking movements 0/50; invalid attempts 0/20; duplicates 1/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 0/30.
- Exact next action: inventory the smallest lifecycle/work-state/booking/Parts/Sublet RPC set needed for the logged scenarios, implement one fail-closed registry guard plus typed synthetic-only wrappers with containment/idempotency/version receipts, independently review and rollback-test them, then begin scenario 001 lifecycle/editing stress.

### Checkpoint 007 — 2026-08-24T14:32:10Z (elapsed 03:37)
- Git commit at final wrapper approval: `bca5f10006b85eea63cd51a84a053d31ab72f0a3`; successor runtime repairs: `e508232a5765b2f82071e48260887a5e49d65360`, `b52163c65068b365d83aa8367697176a8467a695`, `d64a8460bcd63eef42c04b3f0470fdcc9f615312`.
- Areas tested: lifecycle/editing wrapper inventory; exact dependency and registry binding; route-trigger bypass closure; cross-relation protected/sibling digests; success/failure receipts; replay and changed-payload rejection; PostgREST invocation; authenticated readback; direct legacy-core rejection; live UI projection.
- Synthetic records mutated: only registered `HERMES-TEST-001`. `pmb_key_tag` changed from empty to `HERMES-TEST-KEY-001-A`; vehicle version `1→2` under receipt `d7498b62-9e22-50b0-bc2c-2667b39bbb72`.
- Bugs discovered and fixed before successful mutation: unnamed PostgREST façade parameters; nonexistent Sublet-history `id` ordering; composite registry-row assignment. Failed attempts committed no synthetic write.
- Tests passing: 40/40 Node regression files; JavaScript syntax 66/66; migrations 365-368 each executed successfully in staging rollback before independent exact-SHA approval; all four migrations applied with ledger readback; live Apply/readback/replay; changed-payload replay rejection; direct legacy-core bypass rejection; authenticated UI `173 of 173`.
- Authoritative post-state: migration head 368; 173 vehicles / 20 synthetic / 153 protected; mutation receipts 1; notifications 0; Monitor stopped; active mailboxes/writers 0; protected digest unchanged at `3d5ec39d15408cc7443312a5d0974ba1ed8250a5484228bc932bb491f8666875`; 11 exact route triggers enabled.
- Tests failing: none in this wrapper commissioning and scenario-001 slice.
- Blockers: none. Production was not contacted or changed.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 0/100; booking movements 0/50; invalid attempts 2/20; duplicate submits 2/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 4/30.
- Exact next action: use `HERMES-TEST-002` and `003` for guarded IT→PMB and YH-latch lifecycle transitions, then begin exact-minute Workshop booking/conflict tests on `005`-`007`, preserving authoritative receipts/readback after every action.

### Checkpoint 008 — 2026-08-24T14:49:45Z (elapsed 03:55)
- Git commit: `4cf61c898d6c5a80d5808799a38c205f896c9c9a` contains the lifecycle evidence and Workshop reproducer; this checkpoint log follows in the next commit. Migration head remains 368.
- Areas tested: guarded IT→PMB and YH→PMB lifecycle transitions; exact replay; changed-payload replay rejection; stale vehicle-version rejection; authoritative movement/audit/receipt readback; Workshop 005-007 eligibility, station/bay inventory and first exact-minute schedule attempt.
- Synthetic records mutated: only registered `HERMES-TEST-002` and `HERMES-TEST-003`. Both moved explicitly to PMB with `manual_location_authority=PMB`, vehicle version `1→2`, one movement each and receipts `8cc4bb9d-47b6-57a3-9857-1a63b0c837eb` / `0b4bf63f-91ea-5db1-8acd-e7b15bfc5af1`. Two stale-version probes produced immutable rejection receipts without target change.
- Bugs discovered: the commissioned synthetic Workshop schedule wrapper cannot yet exercise scenarios 005-007. The normal eligibility snapshot correctly reports `estimated_duration_missing`; an explicit 73-minute Fitting attempt at 09:07 Perth was rejected by authoritative trigger `PDC_317_ESTIMATED_DURATION_REQUIRED` before any booking or receipt committed. The synthetic bootstrap deliberately contains no operation-hour evidence, and inventing hours or bypassing migration 317 is forbidden.
- Bugs fixed: none in Workshop yet. Lifecycle/YH-latch behavior required no repair and passed as implemented.
- Tests passing: lifecycle harness and authoritative receipt readback; exact replay for both transitions; two changed-payload and two stale-version negative cases; focused Node wrapper contract; Python compile for all three new harnesses; final environment proof.
- Tests failing: the Workshop reproducer is intentionally red at the first schedule action on `HERMES-TEST-005` with `PDC_317_ESTIMATED_DURATION_REQUIRED`; no booking mutation occurred.
- Authoritative post-state: 173 vehicles / 20 synthetic / 153 protected; notifications 0; Monitor stopped; active mailboxes/writers 0; migration head 368; protected cross-relation digest unchanged at `5e55bba95f78eb99878fca9098e15277747d22d064d76617c857d8ab3ccf6a5f` (716 protected relation rows).
- Blockers: no human blocker. Workshop stress needs a successor staging-only, registry-bound synthetic estimate mechanism that adds explicit `HERMES-TEST` test estimates without weakening the migration-317 positive-estimate rule, expands protected/sibling containment to the estimate relations, and remains receipt/idempotency/version guarded.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 0/50; invalid attempts 6/20; duplicate submits 4/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 8/30.
- Exact next action: implement and independently review migration 369 for synthetic-only estimated-hour setup with expanded cross-relation digests/route guards and immutable receipts, rollback-test/apply it, then rerun the exact-minute schedules and bay/vehicle conflict sequence on 005-007.

### Checkpoint 009 — 2026-08-24T15:24:11Z (elapsed 04:29)
- Git commit: `2375dada71a5bc5b4dbe57e340a198d73454e847`; migration 369 SHA-256 `152f101c80f8eec420f7d9c06de1570a81ede41620d8e5fc0ed8e479143c7f5c` (pushed).
- Areas tested: exact migration-368 predecessor and installed-function hashes; synthetic estimate provenance; target-based generic-RPC bypass closure; route/ACL/owner/dependency drift; protected/sibling and receipt-relation containment; runtime race locks; replay/readback truthfulness; migration-317 positive-estimate preservation.
- Synthetic records mutated: none. Migration 369 was executed only inside explicit staging rollback transactions; live migration head remains 368 and scenarios 005-007 still have no estimates or bookings.
- Bugs discovered: the first candidate had incomplete runtime containment, raceable cross-relation digests, a bootstrap-actor rather than registry-target route boundary, receipts outside route/digest containment, a misleading replay-containment label and readback without dependency/registry drift gates.
- Bugs fixed locally: migration 369 now admits only the four explicit test values (005 Fitting 1.22h/73m; 006 Electrical 1.02h/61m; 007 Fitting 0.78h/47m and Electrical 0.98h/59m), stores them as a dedicated synthetic authority rather than counterfeit source evidence, preserves migration 317, closes the generic migration-361 path for every registry target, exact-hash binds the route/canonical/predecessor functions, serializes every protected/sibling digest relation, and uses private append-only receipts plus truthful replay/readback.
- Tests passing: focused static contract; executable model; Node syntax; repeated exact live staging rollback execution; post-rollback environment proof unchanged; final independent exact-source `APPROVE` on SHA `152f101c...`.
- Tests failing: none in the approved source/rollback slice. Migration 369 has deliberately not yet been committed live and the exact-minute schedule sequence has not yet rerun.
- Authoritative post-state: migration head 368; 173 vehicles / 20 synthetic / 153 protected; notifications 0; Monitor stopped; active mailboxes/writers 0; no synthetic estimate or booking mutation this checkpoint.
- Blockers: none. Production was not contacted or changed.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 0/50; invalid attempts 6/20; duplicate submits 4/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 8/30.
- Exact next action: re-prove staging, apply exact reviewed migration 369 through the guarded staging controller with ledger readback, perform Administrator-authenticated four-estimate Apply/replay/negative acceptance, then rerun exact-minute schedules and bay/vehicle conflict tests on 005-007 with authoritative receipts/readback.

## Final report
Pending until the ten-hour end time.
