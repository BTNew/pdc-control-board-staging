# Workshop start, mechanic stoppage and progress repair

Applied to the existing staging database on 16 September 2026. The website update uses fitter asset version 2026.09.16.02.

## Changes

- Starting a job uses the database clock and moves only conflicting planned jobs forward. Unrelated later work keeps its dates. Downtime, running or stopped jobs, mechanic assignments, vehicle order and the one-hour handover remain protected.
- Start writes its new interval and started status together, avoiding the minute-boundary overdue-planned race. Conflicts return useful explanations and leave no partial changes.
- Stopping an already-running job preserves its unchanged historical interval when that interval was valid under former opening hours. New starts and moves still follow the current 06:00–16:30 weekday calendar.
- Admin preflight, move, resize and nearest-slot paths use the same effective booking end as the database conflict guard; completed booking history no longer blocks a new admin interval.
- Workshop pills keep their existing height. Stoppage/Complete controls sit above a visible 10-pixel green progress strip with a percentage.
- Fitter polling reuses roster data for one minute, avoids rebuilding unchanged screens, and does not swallow taps during a background refresh. A rejected stoppage retains its typed reason.
- Eligibility snapshots remove repeated alias queries and unnecessary duration conversions. Paired database measurements decreased from 1057.00 ms to 473.72 ms (about 55%); full output matched. This measures the database, not end-to-end page load time.

## Verification

- Full JavaScript suite: 844 passed, zero failed. The19 fitter/error-message checks were rerun after the final wording adjustment.
- Start rollback suite: 28 assertions passed, including early/late starts, downtime, cross-station cascade, secondary mechanic assignments, occupied/stopped bays, authorization and stale retries.
- Historical stoppage/admin rollback suite: 14 checks passed, including fitter stop, controller resume, stale requests and preserving actual start/history.
- Snapshot output/access checks and all 38 aliases matched; synthetic edge suite: 25 assertions passed.
- Existing vehicles, bookings, assignments and fitter progress were unchanged by the rollback test suites. Browser verification used synthetic jobs for Start, Stoppage and Resume.
- Browser layout checks at 62,194 and400-pixel pill widths: height96pixels unchanged, progress10pixels high,3pixels clear of action buttons.

A job cannot start through protected downtime or another running/stopped occupant. A cyclic booking swap that cannot be written with database constraints active is rejected atomically for controller review.

## Deployment verification

All four migrations were applied to staging and read back. The three existing jobs affected by the old calendar now pass stoppage validation without changing their status. Security advisor counts are unchanged from the pre-deployment baseline.

- 20260916004559 — workshop_admin_fixed_conflict_consistency
- 20260916004611 — workshop_start_conflict_safe_schedule
- 20260916004616 — workshop_eligibility_snapshot_optimization
- 20260916004621 — workshop_historical_job_stoppage
