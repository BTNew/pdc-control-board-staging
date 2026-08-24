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
- Consecutive final clean journeys: 3 / 3
- Board/chip movements: 8 / 100
- Booking movements/adjustments: 6 / 50
- Invalid movement attempts: 17 / 20
- Duplicate-submit tests: 20 / 20
- Parts changes: 18 / 25
- Sublet changes: 21 / 20
- QC/RFT out-of-order attempts: 12 / 10
- Two-session scenarios: 11 / 10
- Field/validation scenarios: 59 / 30

## Bugs
### Discovered
- The first wrapper candidate exposed three runtime contract defects before any synthetic write committed: PostgREST could not invoke unnamed façade parameters; Sublet history was ordered by nonexistent `id` instead of `history_id`; and `SELECT r INTO` attempted to cast the composite registry row into its first UUID field.

### Fixed
- Migration 363 was hardened through two independent review rounds: fail-closed singleton containment, conflicting locks/revalidation, exact catalog/identity collision closure, same-set protected digest, canonical readback drift rejection, truthful durable replay, two set-based authoritative inserts and receipt-bound shared revision delta `+2`.
- Migration 364 repaired the authenticated Vehicle Locations projection without changing vehicle data or privileges: the established snapshot now also admits only exact migration-363 registry-bound rows whose static identities and synthetic source contract still match. Authenticated UI readback is now `173 of 173`, including all 20 synthetic vehicles, while the 153 protected-row digest remains unchanged.
- Migrations 365-368 installed exact registry-bound mutation façades, actor/idempotency/version receipts, exact-target route guards, cross-relation protected/sibling digests, zero-notification QC/RFT handling, PostgREST argument names, canonical Sublet-history ordering and correct registry rowtype assignment. Scenario 001 Apply/replay/negative probes then passed live.
- Migrations 369-372 commissioned exact synthetic estimate authority and closed three independent established 60-minute floors (canonical estimate projection, validator and booking constraint) only for exact registry-bound migration-369 rows. All protected/non-test canonical and validation behavior remains unchanged; exact 47/59-minute bookings now pass while ordinary sub-hour bookings remain fail-closed.
- The Workshop 005-007 harness was repaired to model the authoritative contract correctly: scheduling does not increment vehicle version; restarts consume immutable receipts idempotently; database-trigger conflict rejection is accepted only with exact HTTP 400 conflict evidence and authoritative no-change readback.

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

### Checkpoint 010 — 2026-08-24T15:29:08Z (elapsed 04:34)
- Git commit at apply: `3698fe4d4fd667e19af20de94d1c22ac1de8ac39`; exact migration 369 applied to staging with ledger readback and secret-free deployment receipt.
- Areas tested: live migration commissioning; exact 005/006 estimate Apply; exact replay; changed-payload rejection; scenario-007 sub-hour canonical-duration negative case.
- Synthetic records mutated: only registered `HERMES-TEST-005` and `HERMES-TEST-006`. Dedicated explicit estimates are now 1.22h/73m Fitting and 1.02h/61m Electrical, each with one immutable receipt. No booking was created. Scenario 007/Fitting failed atomically and committed no estimate or receipt.
- Bug discovered: the established canonical duration function applies `greatest(60, round(hours*60))`. It correctly returns 73 and 61 minutes for scenarios 005/006 but clamps explicit scenario-007 values 0.78h and 0.98h to 60 minutes instead of 47 and 59. Migration 369 therefore rejected scenario 007 at its authoritative exact-minute postcondition rather than weakening or bypassing the existing rule.
- Bugs fixed: migration 369 itself commissioned successfully; generic migration-361 writes to registry targets are now route-guarded and all new estimate/receipt state remains isolated.
- Tests passing: live 369 ledger readback; 005/006 Apply/readback; two exact replays; two changed-payload rejections; post-failure environment proof; notifications/mailboxes/writers remain zero/stopped.
- Tests failing: scenario 007/Fitting at `PDC_369_DIGEST_NOTIFICATION_OR_READBACK_POSTCONDITION`, narrowed by rollback probe to canonical `0.78h → 60m` clamping. Workshop bookings remain unstarted.
- Authoritative post-state: migration head 369; estimates 2; estimate receipts 2; synthetic bookings 0; 173 vehicles / 20 synthetic / 153 protected; notifications 0; Monitor stopped; active mailboxes/writers 0.
- Blockers: no human blocker. A staging-only successor must preserve the 60-minute rule for all protected/non-test vehicles while returning exact positive rounded minutes only for registry-bound migration-369 synthetic estimates, then rebind the exact dependency guard.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 0/50; invalid attempts 9/20; duplicate submits 6/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 10/30.
- Exact next action: implement independently reviewed migration 370 with an exact registry-only canonical-minute exception (protected/non-test behavior byte-for-byte preserved), update dependency hashes, rollback-test/apply it, then resume scenario-007 estimates and the six-action exact-minute booking/conflict harness.

### Checkpoint 011 — 2026-08-24T16:37:23Z (elapsed 05:43)
- Git commits: migration-370 final approval `7ff9012ee388a18e63a4bd500128a4ff3120d5d6`; migration-371 approval `1b988c0e17b1175c65eee11e390a2926ae6bad3a`; migration-372 final approval `2beaae552af7bc828d9e598072e885410dd34c5a` (all pushed before apply). Live staging migration head is 372.
- Areas tested: exact canonical 73/61/47/59-minute estimates; protected canonical-minute parity; booking validator parity; ordinary 60-minute floor preservation; exact-minute booking creation at arbitrary minute starts; bay overlap; same-vehicle cross-station overlap; exact end/start adjacency; idempotent replay; changed-payload rejection; receipt/readback and zero-notification containment.
- Synthetic records mutated: only registered `HERMES-TEST-005` through `007`. Four exact estimates now exist. Planned bookings: 005 Fitting 73m, 006 Electrical 61m, 007 Fitting 47m and Electrical 59m. No physical work or completion was recorded.
- Bugs discovered and fixed: canonical duration clamped sub-hour estimates; validator independently rejected sub-hour requests; table constraint independently required 60 minutes; harness incorrectly expected vehicle-version increments and could not resume from committed receipts or model trigger-aborted conflict rejection. Migrations 370-372 and the restart-safe harness closed each defect without broadening non-test behavior.
- Tests passing: migrations 370-372 focused static/model contracts; Python compile; repeated explicit live rollback execution; four independent exact-commit approvals after hostile review repairs; guarded migration apply/ledger readback; final six-action Workshop harness (`4` successful bookings, `2` authoritative conflicts); exact replay for five receipted actions; changed-payload estimate rejection; protected digest unchanged at `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` protected relation rows; notifications 0.
- Conflict evidence: bay overlap is receipt `6dc751ad-25ac-50c9-a21a-402ffb342e76`; vehicle overlap is authoritative HTTP 400 with exact `vehicle_overlap`/conflict-booking evidence and no target/receipt change because PostgreSQL aborts the rejected transaction.
- Authoritative receipts: estimates `70697068-b1f2-5176-a024-b7e068d9b578`, `fea22d42-bb57-50bb-908a-a50bf02c4b27`, `f0de15f9-c17d-537c-bfc0-9f6e66182bf1`, `8d5f3997-125d-5593-b7e4-4d1f30f9d962`; successful bookings `23cec83f-437f-5e85-aa26-ba7f332faa0a`, `fd3d76ad-7959-578f-ac76-3528d99ea9c4`, `46d59358-f265-5c24-9281-0ddc4f0191ae`, `aca84a26-7dab-5e07-9c15-df80c4d8e6b7`.
- Blockers: none. Monitor stopped; active mailboxes/writers 0; notifications 0; Production was structurally blocked and untouched.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 6/50; invalid attempts 11/20; duplicate submits 15/20; Parts 0/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 14/30.
- Exact next action: execute guarded Parts lifecycle/stoppage/recovery stress on `HERMES-TEST-008` and `009`, preserving receipt/readback, protected digest and zero-notification evidence after every action.

### Checkpoint 012 — 2026-08-24T16:50:24Z (elapsed 05:55)
- Git commit: `2d63933` (pushed to the overnight branch).
- Areas tested: registry-bound Parts ETA, ordered and received lifecycle; direct authenticated receipt semantics; invalid post-receipt ordering; Parts stoppage and recovery; exact replay; changed-payload rejection; stale vehicle-version rejection; authoritative receipt/readback after every action.
- Synthetic records mutated: only registered `HERMES-TEST-008` and `009`. Scenario 008 now has the planned ETA→ordered→received history. Scenario 009 proved the canonical direct-receipt path, then a synthetic stoppage/recovery cycle; final authoritative state is received with stoppage cleared. No physical work was claimed.
- Interrupted-run recovery: the first harness intentionally stopped when its expectation that completion required a prior order proved false. Source inspection confirmed migration 259 deliberately supports direct authenticated Parts receipt, so the harness resumed only after matching the exact committed rows and deterministic receipts; it did not undo, overwrite or reinterpret them.
- Invalid ordering evidence: ordering after direct receipt was rejected as `parts_already_ordered`; completion while the synthetic received/stoppage state was active was rejected as `parts_already_received`. Both produced immutable rejection receipts and no target change.
- Tests passing: live authenticated Parts harness; six exact replays across the complete sequence; two changed-payload rejections; two stale-version rejections; nine focused Parts JavaScript contracts; Python compile; final environment proof.
- Authoritative containment: protected digest unchanged at `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` protected relation rows; notifications 0; Monitor stopped; active mailboxes/writers 0; migration head 372.
- Bugs discovered/fixed: no application defect. The harness's ordering assumption was corrected to the documented receipt-driven Parts contract and made interruption-aware. Direct receipt is valid evidence; unknown or invented receipt evidence remains forbidden.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 6/50; invalid attempts 17/20; duplicate submits 20/20; Parts changes/attempts 18/25; Sublet 0/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 20/30.
- Blockers: none. Production was structurally blocked and untouched.
- Exact next action: run guarded Sublet queued/booked/update/returned and multi-provider isolation stress on `HERMES-TEST-010` and `011`, including provider inventory readback, invalid date/order, idempotent replay, changed payload, stale version and final returned-state verification.

### Checkpoint 013 — 2026-08-24T17:14:34Z (elapsed 06:20)
- Git commit before checkpoint: `31371daa1b09bcd7e3ec7f2213faa30b40fa0ced`; this checkpoint, harness and evidence are committed together immediately below.
- Areas tested: authenticated provider inventory; queued Sublet work evidence; create/date ordering; update; explicit synthetic return; multi-provider non-overlap; overlap rejection; provider-row isolation; stale subject version; changed-payload idempotency; wrong/cross-vehicle subject isolation; exact replay; history/work-item separation.
- Synthetic records mutated: only registered `HERMES-TEST-010` and `011`. Scenario 010 has one returned synthetic booking after explicit create/update/return actions. Scenario 011 has two distinct, non-overlapping provider bookings; provider A was updated without changing provider B. No physical fitting or real-world return was inferred or claimed.
- Authoritative evidence: nine actor/idempotency/request-hash-bound receipts; nine exact replays each with full-fleet before/after equality; two changed-payload rejections with full-fleet no-change; one cross-vehicle subject rejection with both source and presented vehicles plus the full fleet unchanged; exact history action/actor/booking/provider binding; provider inventory digest unchanged.
- Invalid cases: reversed create dates returned `invalid_input`; overlapping second-provider booking returned `sublet_booking_overlap`; stale update returned `version_conflict`; cross-vehicle subject failed before receipt; changed payloads failed closed under the original idempotency keys.
- Tests passing: Sublet harness; strengthened readback/replay verifier; Python compile; synthetic wrapper Node contract; Sublet-history primary-key Node contract; final environment proof; final independent review `APPROVE` after three review-driven evidence-strengthening rounds.
- Review-driven fixes: the first evidence candidate proved the business states but under-specified cross-target readback, per-replay state stability, receipt identity/hash binding, provider inventory stability and history/provider binding. The verifier now recomputes PostgreSQL-jsonb request hashes, proves full-state no-change around every replay/hostile probe, and binds each history row to its exact booking/provider.
- Authoritative containment: protected digest unchanged at `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` protected relation rows; Monitor stopped; active mailboxes/writers 0; notifications 0; migration head 372.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 2/100; booking movements/adjustments 6/50; invalid movement attempts 17/20; duplicate submits 20/20; Parts changes/attempts 18/25; Sublet changes/attempts 21/20; QC/RFT out-of-order 0/10; two-session 0/10; field/validation 26/30.
- Bugs discovered/fixed: no application defect. Evidence-harness weaknesses found by independent review were repaired and rerun; no business control was weakened.
- Blockers: none. Production was structurally blocked and untouched.
- Exact next action: execute guarded QC/RFT/Completed ordering and separation scenarios on `HERMES-TEST-012` through `014`, including out-of-order negatives, zero-notification proof, exact replay/stale/changed-payload checks and authoritative final-state separation.

### Checkpoint 014 — 2026-08-24T17:55:55Z (elapsed 07:01)
- Git commits before live acceptance: guarded completion façade `0450a1c`, evidence hardening `5ed61b0`, registry-assignment successor `4080117`, interruption-evidence hardening `92995fc` (all independently reviewed; final exact review `APPROVE`). Migration 373 SHA-256 `8c723c22...` and migration 374 SHA-256 `d20c2bf0...` are both applied with ledger readback; the evidence/checkpoint commit follows immediately below.
- Areas tested: QC-before-work; QC-to-RFT before QC; collection before RFT and from QC; repeated Ready-QC/QC-to-RFT/collection; explicit synthetic completion evidence; QC/RFT/Completed state separation; exact replay; changed-payload rejection; stale version; operator/viewer/unapproved role boundaries; zero-notification containment.
- Synthetic records mutated: only registered `HERMES-TEST-012` through `014`. Scenario 012 ends active in `QC` without QC sign-off/RFT evidence; scenario 013 ends in `RFT` with QC sign-off but no collection; scenario 014 alone ends hidden at `Completed` with ordered QC, RFT and collection evidence. All work completion evidence is explicitly `HERMES-TEST`; no physical work was claimed.
- Bugs discovered: the generic ten-key work-state façade failed atomically because canonical no-state row churn exceeded its wrapper revision bound; the first narrow migration-373 call then failed atomically because `SELECT r INTO` attempted to cast the composite registry row into its first UUID field. No completion state committed in either failed attempt.
- Bugs fixed: migration 373 adds an exact registry/scenario/work-key-bound single-row synthetic completion façade with actor/idempotency/version receipts, protected/sibling digests, route-trigger compatibility, bounded revisions and no notification path. Append-only migration 374 corrects the registry row assignment to `SELECT r.* INTO` without changing the approved function contract. The harness now accepts only the exact three deterministic interrupted rejection receipts and binds every exposed target relation around replay and hostile probes.
- Tests passing: live 012-014 acceptance (`9` successful actions, `12` ordered rejections, `21` exact replays, `5` changed-payload rejections, `3` stale-version rejections, `3` role checks); `15/15` focused overnight Node contracts; Python compile; explicit live rollback execution for migrations 373 and 374; four independent review rounds ending `APPROVE`; final environment proof.
- Authoritative final separation: 012=`QC`/active/version 3; 013=`RFT`/rft/version 5; 014=`Completed`/completed/version 6 and hidden. Protected digest remains `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` protected relation rows. Monitor stopped; active mailboxes/writers 0; notifications 0; migration head 374.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 8/100; booking movements/adjustments 6/50; invalid movement attempts 17/20; duplicate submits 20/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session 0/10; field/validation 37/30.
- Blockers: none. Production was structurally blocked and untouched.
- Exact next action: execute duplicate/concurrency scenarios `HERMES-TEST-015` through `017`, including duplicate submit, same-key changed payload, stale expected version and two authenticated session races with authoritative winner/loser receipts and full protected/sibling no-change proof.

### Checkpoint 015 — 2026-08-24T18:21:11Z (elapsed 07:26)
- Git commits: original live acceptance and immutable evidence `eceade4ff64b8b53ef77aca829fb863c2bdf9ea6`; the repaired verifier, two timed mutation races, independent approval and this checkpoint follow in the next commit.
- Areas tested: concurrent exact duplicate submit; one-Apply/one-replay serialization; same actor/key changed-payload rejection; stale expected version; two original and two additional timed competing same-record races through separately authenticated sessions; authoritative winner/conflict-loser receipts; receipt semantic uniqueness; version/audit/revision deltas; full target, sibling and protected containment; zero notifications.
- Synthetic records mutated: only registry-bound `HERMES-TEST-015` and `017`; `016` received only one immutable stale-version rejection receipt and its complete target relation state remained unchanged. Scenario 015 changed its synthetic key tag once at version `1→2`. Scenario 017 had four serialized race winners across the original and timed pairs and is now version `5`; every loser is an immutable `vehicle_version_conflict`. No physical work or completion was claimed.
- Concurrency evidence: the two final competing mutation pairs had overlapping isolated-session request windows of `626,076,300ns` and `693,729,500ns`. Each pair produced exactly one winner, one conflict loser, two unique `(actor,idempotency)` receipts, one audit event, one PDC revision and no unrelated revision or relation delta. Authoritative final tags matched each winner; lost updates `0`; duplicate semantic receipt rows `0`.
- Review-driven hardening: the first two independent reviews blocked weak URL pinning, incomplete executable/evidence binding, partial stale-state comparison, missing original request timing and superficial receipt counters. The harness/verifier now require the exact HTTPS staging hostname, exact migration head `{20260825110000,374_overnight_qc_fixture_registry_assignment}`, exact live Apply/Edit function hashes, exact committed harness/evidence digests, complete target replay stability, independent changed-payload no-change, full sibling no-change, and actor/idempotency uniqueness. Two fresh timed mutations replaced the retrospective timing gap. Final independent review: `APPROVE`, with `28/28` offline structural/evidence checks.
- Tests passing: live 015-017 acceptance; timed mutation-race harness; repaired independent live verifier; Python compilation; all `15/15` overnight Node contracts; final environment proof. Migration head remains 374; Monitor stopped; active mailboxes/writers `0`; notifications `0`; protected digest unchanged at `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` rows.
- Tests failing: none after review remediation.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 8/100; booking movements/adjustments 6/50; invalid movement attempts 17/20; duplicate-submit tests 21/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session scenarios 5/10; field/validation 39/30.
- Blockers: none. Production was structurally blocked and untouched.
- Exact next action: execute role/permission scenario `HERMES-TEST-018` across Administrator, Operator, authenticated-unapproved and fail-closed Viewer boundaries, including cross-role idempotency/actor isolation, then continue browser navigation/mobile/accessibility on `019`.

### Checkpoint 016 — 2026-08-24T18:44:26Z (elapsed 07:50)
- Git commit at verified execution: `4064f3f` (the evidence and this checkpoint follow in the next commit).
- Areas tested: authoritative Administrator and Operator role/read/write boundaries; authenticated Auth-user with no PDC role; actor-scoped idempotency isolation under the same UUID across two roles; exact replay; same-actor changed payload; actual protected-row rejection; cross-vehicle booking-subject rejection; configured historical Viewer credential state.
- Synthetic records mutated: only registry-bound `HERMES-TEST-018`. Administrator changed its synthetic key tag at vehicle version `1→2`; Operator reused the same idempotency UUID under its distinct actor and changed the tag at version `2→3`. The interrupted first run stopped after those two committed receipts because the harness used an incorrect registry table name in a read-only protected-row inventory query; the repaired harness recovered and replayed both exact receipts without another write.
- Authoritative role evidence: Administrator=`administrator/active/approved`; Operator=`operator/active/approved`; the separately authenticated unapproved identity has no PDC role row and was denied both read and write. Two distinct `(actor,idempotency)` receipts exist for the shared UUID, with no duplicate semantic key and final authoritative tag matching the Operator action.
- Negative evidence: unapproved read/write rejected; two same-actor changed-payload probes rejected; two actual protected-row write probes rejected; one scenario-005 booking presented against scenario 018 rejected as a cross-vehicle subject. Every probe had full target/sibling/protected no-change readback; protected digest remains `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11` across `1413` rows; notifications remain `0`.
- Viewer limitation discovered: the credential configured under the historical Viewer environment keys fails authentication, but its authoritative current role row is `importer/active/approved`, not Viewer. The harness now reports this truthfully as credential fail-closed and does **not** claim an authenticated Viewer-role test. No credential or role was changed.
- Tests passing: live interruption-safe role harness; exact committed-harness SHA binding at `4064f3f`; exact live edit/read/booking function hashes; `15/15` overnight Node contracts; Python compile; final environment proof.
- Tests failing: none in the proven Administrator, Operator, unapproved, idempotency, protected-row or cross-vehicle scope. An authenticated Viewer-role boundary remains unproven because no valid Viewer session is available within this profile's existing credentials.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 8/100; booking movements/adjustments 6/50; invalid movement attempts 17/20; duplicate submits 23/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session scenarios 7/10; field/validation 47/30.
- Blockers: no blocker to browser/mobile/accessibility work. Viewer-role execution is credential-bound; this run did not create, rotate, copy or broaden credentials.
- Exact next action: commit/push this evidence checkpoint, then exercise live staging hash-route navigation, refresh/second-session behavior, mobile layouts, keyboard/focus order and accessibility on `HERMES-TEST-019`, capturing screenshots plus console/network evidence without mutating protected rows.

### Checkpoint 017 — 2026-08-24T19:10:40Z (elapsed 08:16)
- Source commits: `50542c5` (browser evidence, modal repair and regression) and `a5ea341` (release marker alignment), both pushed to the overnight branch. Isolated staging Pages deploy commit: `12f6b00c5f8f6194d968b56a00525bcd84cfa58e` on `main`.
- Areas tested: Administrator-authenticated hash routes and reload/deep links for Vehicle Locations, Control Board, Fitting planner, Parts, Sublet, QC and RFT; two independently authenticated browser contexts; 1440×1000 desktop and 390×844 touch/mobile viewports; 30-step keyboard order sample; HERMES-TEST-019 vehicle dialog initial focus, forward-tab containment, Escape close and focus return; labels/duplicate IDs/basic touch sizes/horizontal overflow; console, page exceptions, failed requests and HTTP errors.
- Synthetic records mutated: none. Browser reads and dialog opening targeted only `HERMES-TEST-019`; both contexts loaded the exact synthetic record. Protected/pre-existing rows were not mutated and no physical work was claimed.
- Bug discovered: the vehicle dialog allowed keyboard focus to escape after 30 Tabs and Escape left focus on `body` instead of returning to the HERMES-TEST-019 stock control. Source inspection showed the same missing focus containment/return in the add-vehicle dialog.
- Bug fixed: vehicle and add-vehicle dialogs now remember the invoking control, wrap forward/reverse Tab within the active dialog, close only the active dialog on Escape and restore focus after close. The asset version was advanced to `2026.08.25.01-modal-keyboard-focus`; a focused source contract prevents regression.
- Live acceptance after deploy: all seven route/deep-link pairs survived reload with the correct active navigation item; both isolated sessions were approved and loaded 019; the vehicle dialog kept focus inside for 80 Tabs, Escape closed it and focus returned to the exact `data-open-stock="HERMES-TEST-019"` control. Desktop and mobile had zero document-level horizontal overflow and no duplicate IDs or visibly unlabeled form controls. Touch controls were at least 32px high in the sampled mobile workflow, exceeding the WCAG 2.5.8 24px minimum, though several remain below the older 44px enhanced target.
- Tests passing: `49/49` source Node tests; `33/33` isolated deploy Node tests; JavaScript/Python syntax; staging-integrity CI; Pages build/report/deploy CI; exact live-byte equality for `index.html`, `app.js` and `deployment-identity.json`; authenticated post-deploy browser acceptance with `0` console errors, `0` page exceptions, `0` failed requests and `0` HTTP errors.
- Secret-free evidence: `_overnight_evidence/browser-019/evidence.json`, `desktop-dashboard.png` and `mobile-workflow.png`. Screenshots were filtered to HERMES-TEST-019 and the signed-in label was locally redacted to `HERMES STAGING ADMIN`; visual inspection confirmed no real customer/stock/email/credential/secret was captured.
- Authoritative containment: live Pages/build/main all resolve to `12f6b00c...`; migration head remains 374; 173 vehicles / 20 synthetic / 153 protected; Monitor stopped; active mailboxes/writers `0`; notifications `0`; Production remained structurally blocked and untouched.
- Quantitative counters: synthetic 20/20; journeys 0/5; board movements 8/100; booking movements/adjustments 6/50; invalid movement attempts 17/20; duplicate submits 23/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session scenarios 8/10; field/validation 59/30.
- Blockers: none. The prior authenticated Viewer-role credential limitation remains unchanged and was not repaired by credential or role changes.
- Exact next action: extend the browser evidence with authoritative accessibility-tree names and a focused contrast sample, then begin the read-only/full final regression journey on `HERMES-TEST-020` and the aggregate source/browser suite while time remains.

### Checkpoint 018 — 2026-08-24T19:33:46Z (elapsed 08:39)
- Source commit before this checkpoint: `70ad1b4c2d321e9645277ef6d2b0a5256df03716` (pushed). Isolated staging Pages deploy commit: `a2f76381c85c91cc155b705ae91e46f727663be8` on `main`; both staging integrity and Pages deployment workflows passed.
- Areas tested: Chromium's authoritative accessibility tree; focused WCAG computed-contrast sampling; asynchronous modal rerender focus containment; all live routes/reloads; three consecutive two-session read-only final regression journeys; authoritative lifecycle, exact-minute Workshop, Parts, Sublet and QC/RFT/Completed readback; duplicate inventory; final aggregate source/deploy suites and exact deployed-byte identity.
- Synthetic records mutated: none. `HERMES-TEST-020` remained pristine at IT/version 1 with four incomplete synthetic requirements and no Parts, Sublet, booking, receipt, movement, audit or completion evidence. The three final journeys were deliberately read-only because recording physical completion would fabricate evidence.
- Bug discovered: the first extended browser rerun reproduced a narrower focus race after 68 Tabs: an asynchronous detail refresh could replace the focused modal control after the keydown trap completed, allowing focus to fall outside the dialog.
- Bug fixed: the focus trap now performs a post-render containment check and returns focus to the first current modal control if asynchronous rendering replaced the active element. The staging asset marker is `2026.08.25.02-async-modal-focus-containment`; the live dialog then retained focus for all 80 Tabs, closed on Escape and returned focus to the exact 019 stock trigger.
- Accessibility evidence: Chromium `Accessibility.getFullAXTree` exposed 22 relevant nodes with all required navigation names, `SN HERMES-TEST-019`, and zero unnamed interactive nodes in the filtered journey. Six focused foreground/background samples passed WCAG 2.x contrast at ratios `13.45` to `16.29` for normal text and `16.19` for the large heading.
- Final regression evidence: three consecutive clean journeys, each spanning eight routes through two independently authenticated browser contexts (`16` route/reload checks each); exact booking durations remained `47/59/61/73`; final separation remained 012=`QC`, 013=`RFT`, 014=`Completed`; authoritative before/after state was byte-digest equal; browser/console/network/HTTP errors and notifications were all zero.
- Aggregate tests passing: source `49/49` Node tests; isolated deploy `33/33` Node tests; `30/30` Python tests; `77/77` JavaScript syntax checks; Python compileall; live authenticated 019 acceptance; three 020 journeys; staging-integrity CI; Pages build/deploy CI; exact live Git-blob byte equality for `index.html`, `app.js` and `deployment-identity.json`.
- Final inventory: 173 vehicles = 153 protected + 20 registry-bound synthetic. Protected cross-relation state remains exactly `1413` rows / SHA-256 `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11`. Synthetic relations are 26 work items, 4 bookings, 4 booking-history rows, 6 Parts rows, 3 Sublet bookings, 6 Sublet-history rows, 8 movements, 34 audit events and 66 receipts. Duplicate stock identities, receipt IDs and `(actor,idempotency)` receipt keys are all zero.
- Containment: migration head remains 374; Monitor stopped; active mailboxes/writers `0`; outbound/pending notifications `0`; protected records unchanged; Production structurally blocked and untouched.
- Quantitative counters: synthetic 20/20; full Intake/Inception-to-RFT journeys 0/5 (not fabricated); consecutive final clean read-only journeys 3/3; board movements 8/100; booking movements 6/50; invalid attempts 17/20; duplicate submits 23/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session scenarios 11/10; field/validation 59/30.
- Remaining limitation: authenticated Viewer-role execution remains credential-bound; the configured historical credential is invalid and its current role row is Importer. No credential or role was created, changed or broadened.
- Exact next action: commit/push this checkpoint and evidence, then use remaining run time for read-only final proof/integrity rechecks only. At or after `2026-08-24T20:54:31Z`, mark `READY_FOR_FINAL_REPORT`, run one last environment proof and report the verified staging outcome without any new mutation.

### Checkpoint 019 — 2026-08-24T19:43:00Z (elapsed 08:48)
- Git commit at start: `5a546a72c41b3ad8ba6556add5043885358fed96` / tree `3d53b507c29202bcbc8b433ffa1592b9b67046ce`; remote overnight branch matched exactly.
- Mode: read-only final proof only. No application, schema, synthetic-record or reference-data mutation was attempted.
- Areas rechecked: exact staging environment/containment; protected and synthetic inventories; duplicate stock/receipt identities; authenticated two-session 020 route/reload journey; exact live staging Pages bytes; latest staging-integrity and Pages job outcomes; evidence hashes and rollback/containment instructions.
- Read-only acceptance: `173` vehicles = `153` protected + `20` registry-bound synthetic; migration head `374`; protected cross-relation state remains `1413` rows / SHA-256 `28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11`; synthetic state SHA-256 `20758379d26f7ffb4480d2ecb239fade5c7f10410fa23d6138682128256dbe20`; relation counts remain 26 work items, 4 bookings, 4 booking-history rows, 6 Parts rows, 3 Sublet bookings, 6 Sublet-history rows, 8 movements, 34 audit events and 66 receipts. Duplicate stocks, receipt IDs and `(actor,idempotency)` keys remain zero.
- Authenticated 020 proof: two isolated sessions, eight routes each and reloads (`16` route checks); exact Workshop minutes `[47,59,61,73]`; 012=`QC`, 013=`RFT`, 014=`Completed`; 020 remains pristine at IT/version 1 with no fabricated completion evidence; authoritative before/after digests equal; browser console, page, request, HTTP and blocked-host errors all zero.
- Deployment proof: latest Pages build remains `a2f76381c85c91cc155b705ae91e46f727663be8` / `built`. Staging-integrity run `32767835219` and Pages run `32767834347` are completed/success, and every exposed verify/build/report/deploy job succeeded. Fresh cache-busted live bytes exactly equal the Git blobs for `index.html` (`4e3aca2d...`, 67,854 bytes), `app.js` (`241ee716...`, 1,172,114 bytes) and `deployment-identity.json` (`b4dff98c...`, 1,525 bytes).
- Current evidence hashes: environment proof `d80674b02e6b1303cc1a7c65cdf8a806065c056457246b65348c62e8cffc0f7d`; final inventory `0fda2b1a5421f9937181948ce9acd9a1261f72f129c0b40b307eb5afcf1a854a`; 020 journey `122190d71f5b4fb4ddf79c903b0fb3100cb390f1c804769a8ea7316b0d04c8fe`; browser 019 evidence `dcf84b136457946fc0c009b7fb3046cf64414d6c41b9a73846f513472df8d51b`.
- Rollback/containment recheck: keep Monitor, mailboxes, activation writers and outbound delivery disabled. If the staging frontend must be backed out, restore only the staging Pages repository to reviewed predecessor `12f6b00c5f8f6194d968b56a00525bcd84cfa58e` by a normal forward/revert commit and rerun exact-byte/browser gates—never rewrite history. Database migrations are append-only; any later containment must use a separately reviewed staging-only successor, preserving immutable receipts and the 20 registry rows rather than deleting or weakening RLS/route guards.
- Defects/blockers: none newly found. The first large-blob comparison attempt used GitHub's Contents response past its inline-content size limit and therefore returned an empty local comparison operand; the corrected Git Blob API read proved exact equality. This was a verifier invocation issue, not a deployed-byte defect. Authenticated Viewer-role execution remains unproven because the retained credential is invalid and its current role is Importer; no credentials or roles were changed.
- Containment: Monitor stopped; active mailboxes/writers `0`; outbound/pending notifications `0`; Production remained structurally blocked and untouched.
- Quantitative counters unchanged: synthetic 20/20; full physical Intake/Inception-to-RFT journeys 0/5 (not fabricated); consecutive final clean read-only journeys 4/3; board movements 8/100; booking movements 6/50; invalid attempts 17/20; duplicate submits 23/20; Parts 18/25; Sublet 21/20; QC/RFT out-of-order 12/10; two-session scenarios 12/10; field/validation 59/30.
- Exact next action: continue read-only environment, inventory, deployment-byte and authenticated route integrity checks only. At or after `2026-08-24T20:54:31Z`, run the final proof, mark `READY_FOR_FINAL_REPORT`, stop the recurring worker, verify a clean pushed worktree and issue the final staging recommendation.

## Final report
Pending until the ten-hour end time.
