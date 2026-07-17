# Workshop Planner Fix — Handover / Progress Log

Branch: `feature/workshop-shared-realtime-v2`
Staging project: `cdsmnqxtyyoeoznmbidd`
Production (untouched): `vjdtsswhroyguxyfjdkt` / `btnew.github.io/pdc-control-board/`

## Latest commits (this segment, newest last)
- `691dffa` — docs: workshop planner fix handover/progress log (committed the previous handover)
- `5f30f40` — feat: QC-complete -> RFT atomic transition + notification outbox + RFT Collected -> Completed (staging)
- `a7c5cea` — fix: Parts screen - give Jita its own dedicated column, separate from Status

All pushed to `origin/feature/workshop-shared-realtime-v2`.

## Status vs the requested order of work
1. ✅ **QC Complete → RFT atomic RPC-backed transition.**
   - Migration `016_qc_rft_collected_notifications.sql`: `qc_complete_vehicle()`
     and `rft_transfer_vehicle()` protected RPCs.
   - `qc_complete_vehicle` atomically marks the vehicle + named work item
     complete, requires optimistic version match, is idempotent (second
     call returns `already_qc_complete`, never double-processes), and
     enqueues the salesperson notification via the outbox (never sends
     inline).
   - `rft_transfer_vehicle` enforces QC-complete as a precondition and moves
     `lifecycle_state` `active -> rft` atomically with full
     `vehicle_movements`/`audit_events` history.
   - Frontend: `completeVehicleQualityControl()` and
     `transferVehiclesToRft()` in `app.js` are now guarded by
     `vehicleLifecycleSharedModeActive()` and route through the new
     `vehicle-lifecycle-actions.js` bridge when enabled; legacy
     localStorage-only behaviour is unchanged and remains the default.
2. ✅ **Notification outbox with idempotency and retry handling.**
   - Table `vehicle_notifications` (status enum
     pending/sent/failed/cancelled, `idempotency_key` unique constraint,
     `attempts`/`max_attempts`, `last_error`, `sent_at`).
   - `queue_vehicle_notification()` is idempotent-safe under a race
     (`on conflict (idempotency_key) do nothing` + re-select).
   - `claim_pending_vehicle_notifications()` / `mark_vehicle_notification_result()`
     are service-role-only (never granted to `authenticated`) - the actual
     send happens outside the DB transaction, per the brief's "do not send
     email inside the main transaction" requirement.
   - `retry_vehicle_notification()` is administrator-only and can correct a
     wrong/missing recipient email before resetting status to `pending`.
   - `backend/vehicle_notification_worker.py`: claims + "sends" (dry-run by
     default - logs what would be sent, never contacts a real provider) and
     records success/failure. A real provider only needs
     `send_via_provider()` implemented later; no other code changes.
   - Missing salesperson email does **not** block the QC/RFT state change -
     `qc_complete_vehicle` returns `notification_has_recipient: false` and
     the frontend visibly alerts the operator so an administrator can
     correct the salesperson and retry.
3. ✅ **RFT Collected → Completed Vehicles shared workflow.**
   - `rft_collect_vehicle()` RPC: requires `lifecycle_state = 'rft'`,
     moves to `completed`, sets `visible_on_board = false`, records
     `rft_collected_at`/`rft_collected_by`, full movement/audit history.
     Rejects a second collection attempt (`already_collected`) instead of
     double-processing.
   - Frontend: `markRftVehicleCollected()` now requires a deliberate
     `window.confirm()` before collecting (brief requirement), then routes
     through the shared RPC when enabled; legacy path unchanged otherwise.
4. ✅ **Parts screen ETA/calendar/Jita layout fix.**
   - Root cause found: ETA date field + calendar icon were **already**
     correctly in the same cell (native `<input type="date">` combines
     them) - no defect found there on inspection/screenshot.
   - Real defect: Jita's tick/cross indicator was rendered *inside* the
     Status table cell (`.parts-queue-status-cell`), not in its own column.
   - Fix: added a dedicated `Jita` `<th>`/`<td>` column
     (`parts-queue-jita-cell`) between "Parts ETA" and "Blocker"; removed
     the old inline span from the Status cell. Same `jitaIndicator()` logic,
     only the layout moved. Rows remain one clean horizontal row per
     vehicle (verified this was already true - no vertical-stacking defect
     existed).
   - Verified live: screenshot shows the Jita column rendering with ✓/✕
     cleanly separated from Status, zero console errors.
5. ✅ **Full regression tests.**
   - `node test_all.js`: **37 passed, 0 failed, 2 skipped** (was 36 before
     this segment; new suites `test_vehicle_lifecycle_actions.js` added).
   - Backend `python -m unittest test_email_board_publisher
     test_email_intake_security test_static_publication_gate
     test_vehicle_intelligence_fixtures.py`: **22 passed**.
   - Staging PostgreSQL/PostgREST integration (all real, no mocks, all
     gitignored under `_staging_test_tools/`):
     - `test_workshop_staging_integration.py`: **34 passed, 0 failed**
       (after clearing stale fixture rows from earlier manual runs - a
       recurring pre-existing test-data hygiene issue, not a regression).
     - `test_qc_rft_collected_staging.py` (new, this segment): **28 passed,
       0 failed** - covers viewer/administrator role gating, atomic
       QC→work-item→notification, double-click idempotency, RFT-requires-QC
       gating, RFT→Completed transition, double-collection rejection, stale
       version rejection, worker claim/mark-result lifecycle, failed
       delivery + admin retry with corrected recipient, and the
       missing-salesperson-email visible-flag path.
     - `test_vehicle_notification_worker_staging.py` (new, this segment):
       **5 passed, 0 failed** - runs the actual worker module against
       staging, not a mock.
   - `git diff --check`: clean after every commit.
6. 🟡 **Staging-only frontend deployment and two-user test — partially done.**
   - Browser smoke test performed against local `test-75.html` (not a
     deployed staging URL - see "Known limitation" below): Vehicle
     Locations, Control Board, Parts, and RFT views all loaded with **zero
     console errors** after every change in this segment.
   - Two-user **realtime** test against the real staging Supabase project
     was **not** performed this segment. It requires either (a) the
     previously-stalled `staging.html` frontend entry point (see prior
     session's stash `wip-staging-shell-auth-glue-before-ai-email-intelligence`,
     still unresolved), or (b) two authenticated browser sessions against
     `index.html` with real staging credentials and
     `window.PDC_SUPABASE_CONFIG.vehicleLifecycle.sharedData = true` +
     `window.PDC_SUPABASE_CONFIG.workshop.sharedData = true` set locally.
     Neither was set up in this segment - this remains the single largest
     open item before a full staging acceptance report can be produced.

## Real bugs caught and fixed this segment
- `mark_vehicle_notification_result()` initially failed with
  `DatatypeMismatch: column "status" is of type notification_status but
  expression is of type text` - the `CASE` expression's string literals
  needed explicit `::public.notification_status` casts. Fixed and
  re-verified against staging.
- Stale test-data interference in `test_workshop_staging_integration.py`
  (leftover parts/booking rows from prior manual staging tests) caused
  false failures in tests 8/9/11 unrelated to any code change; confirmed
  via direct SQL inspection and cleaned before re-running - documented here
  because this is a recurring pattern across sessions and future agents
  should clean `workshop_bookings`/`vehicle_parts_updates` for
  `VEH_1`/`VEH_2` before re-running that suite.

## Known limitations / not yet done
- **No staging-only frontend URL exists yet.** This blocks:
  - A genuine two-browser realtime acceptance test against the real
    staging Supabase project (as opposed to the local dry-run/simulated
    smoke test performed this segment).
  - Producing the final staging URL / test-account / two-user-checklist
    deliverable requested in the original AI-email-monitoring brief and
    implied by "Staging-only frontend deployment" in this segment's
    instructions.
  - This is the same open item flagged at the end of the immediately prior
    session (stashed `staging.html` work). It was not addressed this
    segment because the explicit instruction order placed it last, after
    QC/RFT/Collected/Parts/regression, and the iteration budget was
    reached during regression + Parts-layout completion.
- The notification worker's `send_via_provider()` is intentionally
  unimplemented (`NotImplementedError`) - no real email provider is
  configured or approved for staging, matching the brief's "do not process
  real operational emails/sends without explicit approval" instruction.
  `--dry-run` (the default) is safe to run repeatedly for acceptance
  testing.
- AI Email Monitoring feature: **explicitly not started** this segment,
  per instruction. (A separate `docs/ai-email-vehicle-intelligence-stage1-plan.md`
  and its Stage 1 schema/RPC foundation exist from an earlier, unrelated
  session and remain untouched.)
- Cross-department/exact-time planner fixes from the prior segment
  (`857c9b6`) were not re-tested for regressions against the new
  vehicle-lifecycle code paths beyond the full JS/staging suites already
  passing - no interaction between the two feature areas was found or
  expected (different tables/RPCs entirely).

## Next step (in priority order)
1. Resolve the staging-only frontend deployment blocker: either finish the
   stashed `staging.html` (staging-CSP copy of `index.html` with its own
   `pdc-supabase-config.staging.js`), or get explicit direction on a
   different safe staging publication path (e.g. a separate GitHub Pages
   branch/repo). Must not touch `btnew.github.io/pdc-control-board/`.
2. Once a staging URL exists, enable
   `window.PDC_SUPABASE_CONFIG.workshop.sharedData` and
   `window.PDC_SUPABASE_CONFIG.vehicleLifecycle.sharedData` there only
   (never on production config), and perform the real two-browser
   realtime acceptance test: QC-complete in browser A, confirm RFT
   transition + notification-outbox row appear correctly, confirm browser
   B sees the same vehicle move to RFT without a manual refresh; then
   Collected in browser A, confirm browser B sees Completed Vehicles
   update.
3. Produce the final staging report per the outstanding brief items:
   staging URL, branch, commit hashes, files changed, migrations added,
   RPCs added, test accounts/roles, exact automatic actions enabled vs
   requiring approval, confidence/permission model as it applies here
   (role gating is already enforced at the RPC layer), full test results,
   browser smoke result, two-user realtime result, security review, known
   limitations, rollback procedure, two-user acceptance checklist.
4. Stop and wait for explicit approval before any production change.
