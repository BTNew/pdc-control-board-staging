# Stage 2A — Shared Reference Data (Workshop Technicians, Salespeople, Sublet Providers, Bays, Settings) — Handover

## STAGE 2A: COMPLETE
## STAGE 2B: NOT STARTED

**Branch:** `fix/stage2a-independent-review-findings`
**Final source HEAD:** recorded by the clean exporter in
`FINAL-SOURCE-HEAD.txt` and `REVIEW-MANIFEST.json`
**Runtime correction commit:** `099fa1e92c3bef7c8d27dade76a95c582b8312ed`
**Staging-window test correction commit:** `293563db8f01f0f3cea5874a4d474aa3a99d4018`
**Historical Stage 2A baseline range:** `096eb5f..4606f36`
**Staging deployment repo:** `BTNew/pdc-control-board-staging`
**Staging deployment commit:** `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`
**Staging URL:** https://btnew.github.io/pdc-control-board-staging/
**Staging Supabase project:** `cdsmnqxtyyoeoznmbidd`
**Production Supabase project (untouched):** `vjdtsswhroyguxyfjdkt`
**Production site (untouched):** `btnew.github.io/pdc-control-board-login/`
**APP_VERSION:** `2026.07.18.02-stage2a-final-approval`
**Migration ledger:** aligned through 027
**Cross-platform CI:** run `29627634599` passed

---

## Final contained and assignment remediation (migrations 026–027)

This section supersedes earlier release-identity and test-total statements
below while preserving them as historical evidence.

- `026_stage2a_final_review_remediation.sql` replaces broad viewer SELECT
  policies for technicians, salespeople, providers, and bays. Viewers receive
  active rows only through list RPCs and direct REST/Realtime RLS;
  operator/administrator hierarchy can read inactive rows; pending, disabled,
  and rejected identities read none.
- `update_workshop_configuration` now validates technician UUID text before
  casting and requires exact, round-tripping `YYYY-MM-DD` closure/leave dates.
  Validation failures remain structured JSON and do not bypass version locks
  or audit behavior.
- Protected create/reassignment RPCs reject a new active technician assignment
  during configured leave with `technician_on_leave` and safe date/technician
  context.
- Planner authority is one adapter containing integer minute values and
  validated collections. `07:30` is `450`, never `7.5`; `workshopSetClock()` is
  the only helper that applies minute-of-day values to Date clock fields.
- Closures block/skip new scheduling while historical bookings remain visible;
  breaks split work and cannot receive a start; overtime is valid only inside
  configured windows and is visibly marked; configured working weeks produce
  exactly their configured number/date columns.
- Loading/missing/invalid shared configuration fails closed after valid shared
  authority has been active; stale boot defaults are never silently restored.
- The email monitor lock is portable: `msvcrt` on Windows, `fcntl` on
  Linux/macOS. The exact backend command passed on all three platforms.
- Migration 027 enforces the complete configured interval plus active
  technician and leave rules for schedule, assigned move, assigned resize, and
  resume/reschedule RPC paths while preserving transaction/conflict behavior.
- Shared frontend create/move/resize/extension paths resolve technician UUIDs,
  fail closed for invalid assignments, and retain assignment identity after
  authoritative Realtime reconciliation.
- CI run `29627634599` passed at test-correction commit
  `293563db8f01f0f3cea5874a4d474aa3a99d4018`; staging ledgers align through
  027 and final deployment commit is
  `38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`.

Final results and rollback evidence:
`review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md`.

Migration-026/027 rollback must be a separately reviewed forward migration. Do not
drop the active-only viewer policies or restore direct writes. Frontend staging
rollback is a normal `git revert 38f5404b50e0b447f2390a5ef7b2cdbe2112dae6`
in the staging deployment repository, followed by source-branch consistency
verification. Never use production as a rollback target.

---

## 1. What this stage delivers

Workshop technicians, salespeople, sublet providers, workshop bays, and
workshop configuration/settings move from browser-`localStorage` to
Supabase as the sole authority, with:
- Protected server-side RPCs for every mutation (list/add/edit/
  set_active, plus bay-specific and settings-specific RPCs).
- Full audit trail (`reference_change` audit action) for every change.
- Live Realtime propagation across independently authenticated
  browser sessions, with no page refresh required.
- A staging-only browser-data importer for migrating a given staff
  computer's pre-migration local roster into Supabase once.
- Backup/restore coverage for all five tables.
- Bay active-state/default-technician behaviour wired into the
  workshop planner.

## 2. Commits (source repo)

| Commit | Contents |
|---|---|
| `5d689ba` | Migrations 022-024: schema extensions, 17 protected RPCs, Realtime publication fix |
| `3602b09` | `workshop-reference-data-service.js`, app.js/pdc-auth.js wiring, three real bug fixes |
| `4f8b0af` | Browser-data importer, backup/restore coverage tests, localStorage retirement list |
| `7e2a77d` | Bay behaviour hardening, standalone Realtime diagnostic client |
| `e2b177a` | Version-string propagation, `.gitignore` cleanup |

## 3. Database migrations added

- `022_stage2a_workshop_reference_data.sql` — adds `code`,
  `sort_order`, `created_by`/`updated_by`, `version` columns where
  missing on the five reference tables; revokes remaining direct-write
  grants on `salespeople`/`sublet_providers`.
- `023_stage2a_workshop_reference_rpcs.sql` — 17 protected RPCs:
  `list/add/edit/set_active` for technicians, salespeople, sublet
  providers; `list/set_active/set_bay_default_technician` for bays;
  `get/update_workshop_configuration`.
- `024_stage2a_realtime_publication_fix.sql` — `REPLICA IDENTITY FULL`
  on all five tables; adds `salespeople`/`sublet_providers` to the
  `supabase_realtime` publication (the real root-cause fix for a
  genuine two-browser Realtime gap — see Section 6).

Historical note: migrations 022–024 were initially applied directly to
staging and checked for idempotency. This is not the final migration-ledger,
clean-build, or rollback authority. For the accepted Stage 2A state, defer to
`STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md` and
`review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md`.
Missing ledger entries 018–025 were reconciled through the supported Supabase
CLI repair workflow after object verification; migrations 026 and 027 were
then applied normally. Local and staging ledgers align through 027, as recorded
in `review-evidence/final-contained/MIGRATION-LEDGER-027.txt`.

## 4. Protected RPCs added (staging, migration 023)

`list_technicians`, `add_technician`, `edit_technician`,
`set_technician_active`, `list_salespeople`, `add_salesperson`,
`edit_salesperson`, `set_salesperson_active`, `list_sublet_providers`,
`add_sublet_provider`, `edit_sublet_provider`,
`set_sublet_provider_active`, `list_workshop_bays`,
`set_workshop_bay_active`, `set_bay_default_technician`,
`get_workshop_configuration`, `update_workshop_configuration`.

All require at least `administrator` role for writes (viewer+ for
reads), enforce optimistic version checks, and record every mutation
under `reference_change` in the audit log.

## 5. Test accounts (staging only)

| Role | Email | Password |
|---|---|---|
| retired administrator | administrator@staging.pdc-workshop.example.com | `DISABLED — credential permanently compromised` |
| administrator | administrator2@staging.pdc-workshop.example.com | `[SECRET-MANAGED — local ignored environment only]` |
| retired controllerA | controllerA@staging.pdc-workshop.example.com | `DISABLED — credential permanently compromised` |
| controllerB | controllerB@staging.pdc-workshop.example.com | `[SECRET-MANAGED — local ignored environment only]` |
| viewer | viewer@staging.pdc-workshop.example.com | `[REDACTED]` |
| unapproved | unapproved@staging.pdc-workshop.example.com | `[REDACTED]` |

(Active fixture passwords are stored only in the gitignored
`_staging_test_tools/.env` environment and are never reproduced in source.)

## 6. Root cause of the Realtime issue, and the exact fix

Three distinct, real, independently-verified bugs were found through
genuine live two-browser acceptance testing (not assumed fixed —
each reproduced, diagnosed with concrete before/after evidence, then
fixed and re-verified):

**Bug 1 — Missing publication membership.** `salespeople` and
`sublet_providers` were never added to the `supabase_realtime`
publication. Confirmed via an independent Node.js diagnostic client
(`scripts/stage2a_realtime_diagnostic.js`, bypasses the browser/app
entirely) that received **zero** events for these two tables before
the fix, and correct INSERT/UPDATE events immediately after adding
them to the publication (migration 024).

**Bug 2 — Render-ordering race.** In
`workshop-reference-data-service.js`'s `loadResource()`, `setState()`
(which synchronously fires `onStateChange` — the frontend's render
trigger) was called **before** the fresh rows were written into the
cache. Every render triggered by a realtime event or mutation resync
read the cache one fetch-cycle too early, showing stale data even
though the fetch had already succeeded. Reproduced live: editing a
technician's name showed the OLD name in the UI even though
`getCachedTechnicians()` already returned the NEW name. **Fix:** write
`cache[resourceKey]` first, then call `setState()`.

**Bug 3 — No reconcile-on-reconnect.** A change made by another
session while a given browser's realtime socket was disconnected
produces no `postgres_changes` event on that dead channel — there was
no live channel to deliver it to. Reproduced live: disconnected the
socket, mutated a technician via REST, reconnected, and the change
never appeared. **Fix:** `subscribeToResource()`/
`subscribeWorkshopSettings()` now trigger a fresh resync when a
channel reports `SUBSCRIBED` after a genuine reconnect
(`reconnectAttempt > 0`), not on the initial subscribe. Re-verified
live: the same disconnect/mutate/reconnect cycle now correctly shows
the change with zero duplicate channels.

A fourth, related gap was also found and closed: `workshop_settings`
had no Realtime subscription wiring at all (not even a resource entry)
despite the RPCs existing. Added a dedicated cache-then-notify
subscription path for the settings object.

A fifth, tooling-level issue (not an app bug, but a real source of
wasted debugging time) was also found: the shared `APP_VERSION`
cache-busting string was not bumped across several edits, causing the
browser to silently serve stale cached copies of `app.js`/
`workshop-reference-data-service.js` (`transferSize: 0` in the Network
panel). Fixed by bumping `APP_VERSION` and propagating it to every
hardcoded reference; `test_version_consistency.js` now enforces this
stays in sync going forward.

## 7. Generation/race-condition fix (detail)

A monotonic per-resource generation counter
(`loadGeneration[resourceKey]`) is claimed **before** the `await`
inside `loadResource()`, so any concurrently-started request for the
same resource can tell it is now stale the moment a newer one begins
(not just when the newer one's response arrives). Combined with the
cache-write-before-setState ordering fix (Bug 2 above), this
guarantees: (a) a stale, later-resolving response can never overwrite
fresher data already in the cache, and (b) every render triggered by
`onStateChange` sees the freshest data available at that moment.
Covered by `test 9a` (stale-response discard) and `test 10a`
(cache-before-notify ordering) in
`test_workshop_reference_data_service.js`.

## 8. Importer results

`scripts/import_stage2a_reference_data.py` — dry-run by default,
`--apply` required, `--conflicts-out` for a dry-run conflict export.
Real staging test run this session:
- 2 clean records → correctly created.
- 1 case-variant name → correctly flagged as a conflict (stale-import
  timestamp vs. newer live data), not silently overwritten.
- Idempotent re-run: 0 new records created, all reported as
  `already_matched`.
- Update path (editing an existing matched record with a genuinely
  newer/unambiguous import) verified live: version incremented
  correctly, `edit_technician` RPC invoked, real name change applied.

18/18 real staging tests passing
(`_staging_test_tools/test_stage2a_importer_staging.py`).

## 9. Backup/restore results

27/27 real staging tests passing
(`_staging_test_tools/test_stage2a_backup_restore_staging.py`),
including:
- Byte-for-byte preservation of IDs, codes, sort order, active status,
  version, `default_technician_id`, and creator/updater metadata
  across a real backup → restore cycle.
- Zero notifications triggered by restore.
- Restore succeeds with an inactive referenced technician still
  present (historical `workshop_booking_assignments` references
  remain valid — deactivating a technician never breaks history).
- All FKs (68 discovered, 68 added, 0 skipped) validate on restore.

## 10. Bay behaviour

- `workshopSharedBayRef()` reads from the shared reference service and
  returns no reference while data is unavailable or unmatched. New
  scheduling fails closed unless `workshopBayAvailabilityStatus()` confirms
  the bay is active; only existing/historical rendering remains lenient via
  `workshopBayIsActive()` / `workshopBayDefaultTechnicianName()`.
- `scheduleWorkshopVehicle()` refuses a **brand-new** booking into an
  inactive, unavailable, or unknown bay; `moveWorkshopLivePlan()` refuses
  moving into a **different** bay unless that bay is confirmed active.
  Neither blocks an existing booking
  already in that bay — historical bookings continue to display
  correctly even after their bay is later deactivated (verified live:
  deactivated a bay with a real assignment, confirmed the historical
  record was untouched).
- `workshopBayMechanic()` prefers the Supabase `default_technician_id`
  for a bay, falling back to the legacy local bay-setup mapping only
  when no Supabase default exists — never overwrites an explicitly
  selected technician on an existing booking.
- Full bay-management UI remains deferred (not built this stage) —
  only the behavioural guards above were added, per the approved scope.

## 11. Retired localStorage keys

See `docs/stage2a-localstorage-retirement-list.md` for the full,
authoritative list. Summary:
- **Retired (Supabase-authoritative):**
  `vehicleTrackingCorePdcMechanics:v1`,
  `vehicleTrackingCorePdcMechanicsRosterSeed:v1`,
  `vehicleTrackingCorePdcSubletProviders:v1`,
  `vehicleTrackingCorePdcSubletProvidersSeed:v2`,
  `vehicleTrackingCoreSalespersons:v1`,
  `vehicleTrackingCoreSalespersonsSeed:v1`. Left untouched on disk
  (not deleted) so the importer above can still read pre-migration
  local rosters; no other code path treats them as authoritative.
- **Retained harmless UI-preference keys:** column order, layout
  width preferences, legacy operator-name convenience keys.
- **Not yet retired (Stage 2B scope):** vehicle master data, vehicle-side
  workshop fields in `vehicleTrackingCoreNavisionOnlyEdits:v1`, manually
  added vehicles in `vehicleTrackingCoreNavisionOnlyVehicles:v1`, and
  legacy workshop-plan rows in `vehicleTrackingCoreWorkshopPlan:v1`.
  The current adapter selects either the shared snapshot or the local plan
  store according to the explicit shared-mode flag; it must never merge or
  write both authorities. Shared booking rendering and new-booking lookup
  still bridge through legacy vehicle keys, so Stage 2B must reconcile each
  local stock/order/id key to exactly one stable Supabase vehicle UUID before
  cutover. Until that reconciliation is approved, mixed local/shared
  operational use is prohibited.
- Verified: `loadMechanics()`/`loadSalespersons()`/
  `loadSubletProviders()` never read `localStorage` under any code
  path; clearing browser storage cannot affect technicians/
  salespeople/sublet providers/bays/workshop configuration because the
  running application never reads those keys once loaded.

## 12. Full test results (final freeze run)

| Suite | Result |
|---|---|
| `node --check` (app.js, pdc-auth.js, workshop-planner.js, workshop-reference-data-service.js, scripts/stage2a_realtime_diagnostic.js) | **all pass** |
| `node test_all.js` | **38 passed, 0 failed, 2 skipped** |
| `test_workshop_reference_data_service.js` internal checks | **31/31** |
| Backend `python -m unittest` (6 modules) | **41/41** |
| `test_stage2a_workshop_reference_data_staging.py` | **34/34** |
| `test_stage2a_importer_staging.py` | **18/18** |
| `test_stage2a_backup_restore_staging.py` | **27/27** |
| `test_workshop_staging_integration.py` (fresh fixture) | **34/34** |
| `test_account_approval_staging.py` | **passed** |
| `test_backup_restore_fk_hardening_staging.py` | **7/7** |
| `test_own_row_lockout_staging.py` | **8/8** |
| `test_pdc_user_roles_lockdown_staging.py` | **6/6** |
| `test_privilege_hardening_staging.py` | **4/4** |
| `test_qc_rft_collected_staging.py` | **28/28** |
| `test_role_access_matrix_staging.py` | **passed** |
| `test_vehicle_notification_worker_staging.py` | **5/5** |
| `git diff --check` | **clean** (line-ending warnings only, zero whitespace errors) |

## 13. Browser smoke-test / two-browser Realtime acceptance evidence (final freeze run — against the deployed staging site)

Performed live against the **actual deployed staging site**
(`https://btnew.github.io/pdc-control-board-staging/`, commit
`091ff31`) — one open, authenticated administrator browser session
+ one independent authenticated REST session simulating a second
browser/staff member. Screenshot evidence captured at every step.

**Full create/edit/deactivate/reactivate cycles (all four states,
all three roster entities):**
- **Technician**: create ("Acceptance Cycle Tech") → live, 0 refresh
  → edit ("...EDITED") → live → deactivate → removed from active list
  live → reactivate → reappeared live. All four states confirmed with
  screenshots.
- **Salesperson**: create ("ACT — Acceptance Cycle Salesperson") →
  live → edit → live → deactivate → live → reactivate → live. All
  four states confirmed with screenshots.
- **Sublet provider**: create ("Acceptance Cycle Provider") → live →
  edit → live → deactivate → live → reactivate → live. All four
  states confirmed with screenshots.

**Workshop settings:**
- Updated `default_booking_duration_minutes` (210 → 165) via an
  independent authenticated session; confirmed via
  `getCachedWorkshopConfiguration()` in the open browser session:
  `{value: 165, version: 7}` — correct, zero refresh. Reverted to 210
  afterward.

**Workshop bays:**
- Deactivated `HOIST-BAY-01` → confirmed live (`is_active: false`).
- Changed its default technician → confirmed live
  (`default_technician_id` updated).
- Reactivated it → confirmed live (`is_active: true`). All three
  changes verified via `getCachedWorkshopBays()` in the open session
  immediately after each mutation, with zero refresh.

**Duplicate-subscription / stale-data checks:**
- `window.PDC_SUPABASE.getChannels().length` checked after every
  cycle: consistently **6** (5 reference-data channels + 1 own-role
  channel) — never more, never fewer, throughout the entire test run.
- Zero console errors (`browser_console` returned
  `{"js_errors": [], "total_messages": 0}`) at every checkpoint.

## 13a. Reconnect verification (final freeze run — against the deployed staging site)

Four distinct reconnect scenarios were tested live against the
deployed staging site, each with a genuine before/after state check
(not merely assumed):

1. **Browser refresh** (`location.reload()` from inside the page,
   not a fresh navigation): session persisted (still signed in as
   administrator), exactly 6 Realtime channels re-subscribed after
   reload (no duplicates, no leaked stale channels), zero console
   errors.
2. **Network interruption**: `realtime.disconnect()` called, then a
   technician was edited via an independent session while
   disconnected. Confirmed the change was **not** delivered during
   the outage (cache still showed the old name). Called
   `realtime.connect()` to reconnect; confirmed the missed change
   ("Network Interruption Test Name") appeared automatically within
   seconds with **zero duplicate channels** (6 before, 6 after) —
   this exercises the reconcile-on-reconnect fix directly.
3. **Automatic reconnect**: covered by the same disconnect/connect
   cycle above — Supabase's realtime client reports `SUBSCRIBED`
   again on reconnect, which triggers the fresh resync per the fix in
   `subscribeToResource()`/`subscribeWorkshopSettings()`.
4. **Browser sleep/resume simulation**: simulated via
   `document.visibilityState` forced to `'hidden'` +
   `visibilitychange` dispatch, combined with a longer disconnect
   window (8s) during which another edit was made
   ("Sleep Resume Test Name"), then visibility forced back to
   `'visible'` + reconnect. Confirmed the change caught up correctly,
   6 channels (no duplicates), zero stale data, zero console errors.

**Result across all four scenarios: Realtime reconnects correctly, no
duplicate subscriptions are ever created, no stale cache persists
after reconnect, and the latest database state always wins** — this
directly validates the three previously-fixed root causes (missing
publication membership, request-generation race, cache/render-order
bug) hold up under real reconnect churn, not just a single
disconnect/reconnect pass.

All test-created rows (technicians, salesperson, provider, bay/
settings overrides) were cleaned up / reverted to original state
after verification; final staging state contains only the two genuine
seed technicians and pre-existing fixture rows, zero test bookings —
confirmed by direct SQL query immediately before and after this test
run.

**Only staging Supabase contacted**: all REST/Realtime traffic
confirmed against `cdsmnqxtyyoeoznmbidd.supabase.co` throughout; the
production project (`vjdtsswhroyguxyfjdkt`) was never referenced in
any request during this or any prior Stage 2A testing segment.

## 14. Exact automatic actions enabled vs. requiring approval

No AI/automated-decision actions are introduced by Stage 2A — every
mutation here is a direct, explicit staff action through the Setup
screen UI (add/edit/deactivate a technician, salesperson, sublet
provider, bay setting) via a protected RPC. There is no "automatic"
vs. "requires approval" distinction for this stage; that distinction
belongs to the separately-scoped AI Email Monitoring feature (not
part of Stage 2A).

## 15. Confidence thresholds

Not applicable to this stage (no AI confidence scoring is introduced
here).

## 16. Known limitations

- Full bay-management UI (creating/renaming bays, changing structural
  bay counts per stage) remains deferred — only active-state and
  default-technician behaviour were wired this stage, per approved
  scope.
- The periodic reconciliation timer (2-minute interval) is a
  deliberately low-frequency backstop, not the primary update path —
  Realtime remains the primary mechanism.
- `test_workshop_staging_integration.py` is not idempotent across
  repeated runs without a fixture reset in between (it creates real
  bookings and does not clean them up on its own) — this is a
  pre-existing characteristic of that test file, not a Stage 2A
  regression; documented here so it is not mistaken for a new issue.
- Historical migration-ledger wording in earlier Stage 2A evidence is
  superseded. Missing staging ledger entries 018–025 were repaired through
  the supported Supabase CLI workflow after object verification; migrations
  026–027 were subsequently applied normally. The accepted local/staging
  ledger aligns through 027. See
  `STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md` and
  `review-evidence/final-contained/MIGRATION-LEDGER-027.txt` for the final
  authority.

## 17. Rollback procedure (historical; superseded)

Do not use the earlier 022–024-only drop, reset, force-push, or branch-reset
instructions. The accepted Stage 2A baseline includes migrations 018–027,
including security, RLS, validation, and assignment enforcement. Database
rollback must be a separately reviewed forward migration or an approved
staging-only recovery plan. Do not drop active-only viewer policies, restore
direct browser writes, rewrite applied migrations, or use production as a
rollback or recovery target.

For the authoritative frontend, source-branch, database-recovery, backup, and
approval procedure, defer to the “Rollback procedure” in
`STAGE-2A-INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md` and the final evidence in
`review-evidence/final-contained/FINAL-STAGE2A-CONTAINED-VERIFICATION.md`.

## 18. Recommended Stage 2B design checkpoint

Stage 2B must begin with an inventory and reconciliation checkpoint, not an
immediate write-path change. It must cover:

1. vehicle master records and vehicle-side workshop fields currently held in
   `vehicleTrackingCoreNavisionOnlyEdits:v1` and
   `vehicleTrackingCoreNavisionOnlyVehicles:v1`;
2. legacy workshop bookings in
   `vehicleTrackingCoreWorkshopPlan:v1`;
3. every booking-to-vehicle dependency on the browser-local stock/order/id key
   and its one-to-one mapping to a stable Supabase `vehicles.id`;
4. missing, ambiguous, duplicate, changed, or orphaned vehicle-key mappings;
5. per-browser extraction, dry-run validation, conflict reports, import-run
   audit records, before/after counts, representative record comparison, and
   preservation of raw legacy rows for recovery;
6. a coordinated cutover that never leaves local and shared booking stores
   writable in parallel.

Legacy browser data must remain untouched until the shared import and
representative samples reconcile. Rollback after database migration must use a
separately reviewed forward remediation or isolated recovery plan; it must not
restore browser-local writes as a competing system of record. Stage 2B remains
explicitly not started by this historical Stage 2A handover.

## 19. Two-user acceptance checklist (for manual re-verification)

1. Log in as `administrator` in Browser A.
2. Log in as `controllerA` in Browser B (or use an independent REST
   session per this session's testing pattern).
3. Open the Setup screen in both.
4. Add a technician in A → confirm it appears in B without refresh.
5. Edit that technician's name in B → confirm A updates without
   refresh.
6. Deactivate it in A → confirm it disappears from B's active list;
   confirm a historical booking (if any) still shows the technician
   name.
7. Repeat steps 4-6 for salesperson and sublet provider.
8. Change a workshop setting value in A → confirm B's cached
   configuration reflects it (no dedicated settings UI exists yet;
   verify via the shared service's cached state).
9. Change a bay's active state and default technician in A → confirm
   B's cached bay data reflects it.
10. Disconnect Browser B's network/Realtime socket, make a change in
    A, reconnect B, confirm B catches up automatically within a few
    seconds.
11. Confirm no duplicate records/rows appear after reconnect.
12. Confirm zero console errors and zero CSP violations throughout.
13. Confirm only `cdsmnqxtyyoeoznmbidd.supabase.co` traffic appears in
    both sessions' network activity — never the production project.

---

## STAGE 2A: COMPLETE
## STAGE 2B: NOT STARTED

Stage 2A (shared workshop reference data — technicians, salespeople,
sublet providers, workshop bays, workshop settings) is now frozen:
all three independently-verified Realtime root causes (missing
publication membership, request-generation race condition,
cache/render-order bug) are fixed and re-confirmed under live
disconnect/reconnect/refresh/sleep-resume churn against the actual
deployed staging site; every roster entity's full create/edit/
deactivate/reactivate cycle is confirmed live with zero refresh and
zero console errors; the localStorage retirement report is finalized
at `docs/localstorage-retirement-stage2a.md`; and the full regression
suite (JS, backend, staging PostgreSQL, importer, backup/restore,
RLS, version-consistency, `git diff --check`) is green. No Stage 2B
work (vehicle/booking master-data migration), AI Operations
Supervisor, AI Email Import, or planner UI improvements (Admin
blocks, current-time line, etc.) have been started.

**Stop here for review.** Production remains untouched throughout.
Do not begin any new feature work until Stage 2A has been
independently reviewed and approved.
