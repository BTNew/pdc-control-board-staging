# Workshop Planner Fix — Handover / Progress Log

Branch: `feature/workshop-shared-realtime-v2`
Staging project: `cdsmnqxtyyoeoznmbidd`
Production (untouched): `vjdtsswhroyguxyfjdkt` / `btnew.github.io/pdc-control-board/`

## Latest commit
- `857c9b6` — workshop planner: fix exact-time scheduling verification + real time-overlap cross-department warning

## Status vs the brief's 14-step order of work
1. ✅ Diagnosed exact-time drag/drop — the coordinate math (`workshopDateAtOffset`,
   `workshopClampStartMinutes`, `workshopMinuteOffset`) was already correct;
   verified live against test-75.html with real module execution, not
   assumed from reading code.
2. ✅ Verified timeline header labels/alignment — already correct
   (`workshopTimeAxisHtml()` + `.workshop-time-header`/`.workshop-bay-row`
   share the same 160px-label + flexible-timeline grid; the red current-time
   line uses the same `WORKSHOP_DAY_MINUTES` percentage math). Confirmed via
   screenshot (see below).
3. ✅ Verified all scheduling paths compute identical authoritative times:
   schedule (drag-from-Awaiting and modal), move (drag-existing / detail
   form), resize (drag handle), +15m/+30m/+1h buttons, and the weekly view —
   all funnel through `workshopDateAtOffset`/`workshopEntryStart`/
   `workshopEntryEnd`. No divergent time math found.
4. ✅ Fixed the false "planned by another department" warning. Root cause:
   `workshopConfirmOtherDepartmentPlans()` fired on the mere existence of any
   other-department booking for the vehicle, not on actual time overlap.
   Replaced with `workshopOtherDepartmentOverlaps()`, which compares real
   start/end via `workshopIntervalsOverlap()`.
5. ✅ Ran planner regression (`node test_all.js`: 36 passed, 0 failed, 2
   skipped) and staging PostgreSQL integration
   (`_staging_test_tools/test_workshop_staging_integration.py`: 34/34
   passed, after clearing stale fixture rows left by earlier manual runs).
6. ✅ Committed the stable planner fixes as `857c9b6` and pushed the branch.
7. ⬜ QC → RFT notification workflow — not started.
8. ⬜ RFT Collected → Completed Vehicles — not started.
9. ⬜ Tests for QC/RFT/Collected — not started.
10. ⬜ Parts screen row layout fix — not started.
11. ⬜ Full regression suite re-run after items 7–10.
12. ⬜ Deploy to staging-only URL (see note below — no staging frontend URL
    exists yet; production must not be touched).
13. ⬜ Two-user acceptance test.
14. ⬜ Final staging report.

## What was actually proven live (not just unit-tested)
Using `test-75.html?qaOperator=1` (new test-only param — seeds the operator
profile via localStorage before app.js loads, so staging acceptance testing
does not have to answer native `window.prompt()`/`window.alert()` dialogs
that browser automation cannot dismiss):

- Scheduled vehicle 10015579 into Fab Bay 2 at minute-offset 150 (10:30am
  local) → booking persisted as `2026-07-17T02:30:00.000Z` = exactly
  `Fri Jul 17 2026 10:30:00 GMT+0800` — proves no snap-to-8am.
- Moved the same booking to Bay 4 / minute-offset 60 (9:00am) → persisted at
  exactly 9:00am, in Bay 4.
- `+15m` on that booking: hours went 3 → 3.25, start time unchanged.
- Scheduled Fab 8:00–11:00 and Tint 11:00–13:00 (same vehicle, sequential,
  no gap) with `window.confirm` stubbed to count calls → **0 calls**, both
  bookings created without any warning.
- Scheduled Fab 9:00–12:15 then attempted Tint 10:00–12:00 (same vehicle,
  genuinely overlapping) → `window.confirm` was invoked (native dialog
  blocked automation, which is itself proof it fired) — dismissed and
  confirmed the booking proceeded once approved.

## Root causes (for the record)
- **False cross-department warning**: `workshopConfirmOtherDepartmentPlans`
  filtered only on `stage !== candidate.stage`, never comparing timestamps.
  Fixed in `workshop-planner.js` (see `workshopOtherDepartmentOverlaps`).
- **"Snap to start" defect**: could not be reproduced. All scheduling paths
  already use `workshopDateAtOffset(dateKey, minuteOffset)` consistently,
  and `workshopClampStartMinutes` only clamps to the 0–465 minute valid
  range (8:00am–3:45pm) — it does not silently reset to 0. If this is still
  observed in the field, it is most likely a stale legacy-mode vs
  shared-mode read path (`workshopSharedModeActive()` still fail-closed to
  read-only until the legacy import runs) rather than a math bug; needs a
  screenshot/repro against the *live* board to confirm, since this staging
  branch's local (non-shared) planner mode has been directly verified.

## Known limitations / not yet done
- QC→RFT, RFT Collected→Completed, and the Parts screen layout fix are not
  yet implemented in this session.
- No staging-only frontend URL exists yet (see prior session's stalled
  `staging.html` effort) — deploying "to staging" for this feature requires
  either finishing that separate staging entry point or an explicit decision
  from Craig on where "staging URL" should point, since the only currently
  configured deployment target is the production
  `btnew.github.io/pdc-control-board/` site, which must not be touched.
- Two-user realtime testing for the planner fixes has not been performed
  yet (requires either the staging frontend or two browser profiles against
  index.html with real staging Supabase credentials).

## Next step
Proceed to section 4 (QC → RFT notification workflow) per the order of work,
then section 5 (RFT Collected), then Parts screen layout, then full
regression + staging deployment decision.
