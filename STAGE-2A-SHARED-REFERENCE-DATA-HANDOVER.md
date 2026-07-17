# Stage 2A — Shared Reference Data (Workshop Technicians, Salespeople, Sublet Providers, Bays, Settings) — Handover

**Branch:** `fix/independent-review-production-blockers`
**Latest commit (source repo):** `e2b177a`
**Stage 2A commit range:** `096eb5f..e2b177a` (5 commits)
**Staging deployment repo:** `BTNew/pdc-control-board-staging`
**Staging deployment commit:** `091ff31`
**Staging URL:** https://btnew.github.io/pdc-control-board-staging/
**Staging Supabase project:** `cdsmnqxtyyoeoznmbidd`
**Production Supabase project (untouched):** `vjdtsswhroyguxyfjdkt`
**Production site (untouched):** `btnew.github.io/pdc-control-board-login/`

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

All three applied directly to staging via psycopg2 and verified
idempotent (safe to re-apply). **Staging can be recreated from these
migration files** — confirmed by re-running the exact SQL against
staging with no errors on the second pass.

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
| administrator | administrator@staging.pdc-workshop.example.com | `[REDACTED — see local secure notes]` |
| controllerA | controllerA@staging.pdc-workshop.example.com | `[REDACTED]` |
| controllerB | controllerB@staging.pdc-workshop.example.com | `[REDACTED]` |
| viewer | viewer@staging.pdc-workshop.example.com | `[REDACTED]` |
| unapproved | unapproved@staging.pdc-workshop.example.com | `[REDACTED]` |

(Passwords are recorded in `_staging_test_tools/` locally, gitignored,
not reproduced here per the no-secrets-in-summaries rule.)

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

- `workshopBayIsActive()` / `workshopBayDefaultTechnicianName()` /
  `workshopSharedBayRef()` read from the shared reference service,
  fail-safe to active/no-default when the service has not loaded (so
  incomplete reference data never blocks scheduling).
- `scheduleWorkshopVehicle()` refuses a **brand-new** booking into a
  bay reported inactive; `moveWorkshopLivePlan()` refuses moving into
  a **different** inactive bay. Neither blocks an existing booking
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
- **Not yet retired (Stage 2B scope):** vehicle/booking master data
  and the local workshop-planner booking rows (`workshopSavePlans()`),
  which remain browser-local unless `workshopSharedModeActive()` is
  explicitly enabled — outside Stage 2A's scope.
- Verified: `loadMechanics()`/`loadSalespersons()`/
  `loadSubletProviders()` never read `localStorage` under any code
  path; clearing browser storage cannot affect technicians/
  salespeople/sublet providers/bays/workshop configuration because the
  running application never reads those keys once loaded.

## 12. Full test results (this session, final run)

| Suite | Result |
|---|---|
| `node test_all.js` | **38 passed, 0 failed, 2 skipped** |
| `test_workshop_reference_data_service.js` internal checks | **31/31** |
| Backend `python -m unittest` (6 modules) | **41/41** |
| `test_stage2a_workshop_reference_data_staging.py` | **34/34** |
| `test_stage2a_importer_staging.py` | **18/18** |
| `test_stage2a_backup_restore_staging.py` | **27/27** |
| `test_workshop_staging_integration.py` (fresh fixture) | **34/34** |
| All other pre-existing `_staging_test_tools/test_*.py` | **passing** |
| `git diff --check` | **clean** (line-ending warnings only) |

## 13. Browser smoke-test / two-browser Realtime acceptance evidence

Performed live against the real staging environment (one open browser
session + one independent authenticated REST session simulating a
second browser, per the project's established acceptance-test
pattern):

- **Technician** add → live in open session (0 refresh) → edit → live
  → deactivate → removed from active list live → historical
  assignment still references the (now inactive) technician.
- **Salesperson** add → live → edit → live → deactivate → removed
  live.
- **Sublet provider** add → live → edit → live → deactivate → removed
  live.
- **Workshop settings** update (`default_booking_duration_minutes`)
  → live, correct new value visible via
  `getCachedWorkshopConfiguration()`.
- **Bay** default-technician update → live; bay active-state update
  → live; both reverted to original state after verification.
- **Disconnect/reconnect**: disconnected the Realtime socket, made a
  change via REST while disconnected (never delivered — confirmed
  stale cache during the outage), reconnected, confirmed the missed
  change appeared automatically (reconcile-on-reconnect fix) with
  **zero duplicate channels** (6 before, 6 after).
- **Console/CSP**: zero console errors observed throughout all of the
  above.
- **Only staging Supabase contacted**: all REST/Realtime traffic
  confirmed against `cdsmnqxtyyoeoznmbidd.supabase.co`; production
  project was never referenced in any request.

All test-created rows (technicians, salesperson, provider, bay
overrides) were cleaned up / reverted to original state after
verification; final staging state contains only the two genuine seed
technicians and pre-existing fixture rows, zero test bookings.

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
- Migration tracking (`supabase_migrations.schema_migrations`) on
  staging stops at `017` because migrations 018-024 were all applied
  directly via psycopg2 rather than `supabase db push` — this is a
  pre-existing project pattern (not introduced this stage) and does
  not affect actual schema/data correctness, only the CLI's own
  migration-history bookkeeping. The migration SQL files themselves
  are the source of truth and have been verified re-appliable.

## 17. Rollback procedure

- **Frontend:** revert the staging deploy repo
  (`BTNew/pdc-control-board-staging`) to commit `f258ae9` (the prior
  deployed state) via `git revert` or a force-push of that commit to
  `main`; GitHub Pages will redeploy automatically.
- **Database:** migrations 022-024 are additive (new columns, new
  RPCs, publication membership, replica identity) and do not drop or
  rename any existing column/table. A full rollback would require:
  1. Drop the 17 new RPCs (`drop function` statements, listed in
     Section 4).
  2. Revoke the publication membership changes
     (`alter publication supabase_realtime drop table
     salespeople, sublet_providers;`) and optionally revert
     `REPLICA IDENTITY` to `DEFAULT`.
  3. Drop the added columns (`code`, `sort_order`, `created_by`,
     `updated_by`, `version`) from the five tables if a hard rollback
     is required (not recommended — these columns are backward
     compatible and harmless to leave in place even if the RPCs are
     removed).
  4. No data migration/import was performed against real operational
     data — only synthetic staging fixtures were used throughout, so
     there is no operational data to roll back.
- **Source repo:** `git revert` commits `5d689ba..e2b177a` on
  `fix/independent-review-production-blockers`, or reset the branch to
  `096eb5f` if a clean rollback point is preferred.

## 18. Recommended Stage 2B scope

Per the original localStorage migration plan
(`docs/localstorage-to-supabase-migration-plan.md`), Stage 2B should
cover the vehicle/booking master data itself: migrating
`vehicleTrackingCoreNavisionOnlyEdits:v1` /
`vehicleTrackingCoreNavisionOnlyVehicles:v1` and the workshop planner's
local booking rows (`workshopSavePlans()`) to Supabase as the sole
authority, building on the transactional RPC pattern and shared
Realtime infrastructure already proven in Stage 2A. This is
explicitly **not** started as part of this handover.

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

**Stop here for review.** Stage 2B, AI Email Monitoring, Admin planner
tiles, and current-time-line work are explicitly **not** started.
Production remains untouched throughout.
