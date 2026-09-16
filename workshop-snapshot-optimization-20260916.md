# Workshop eligibility snapshot optimization

The snapshot was spending most of its time inside seven per-station eligibility
calls. Each call repeatedly resolved stage aliases for outstanding work-item rows
and calculated minutes even though this read path only returned an hours-present
boolean.

The migration joins the existing primary-keyed alias table directly and calls the
same canonical approved-hours helper once per eligible vehicle/station. It retains
the required/uncompleted-work filters, board visibility, lifecycle, location
overrides, Yard Hold/PMB/IT eligibility, ETA requirement, existing-booking detection,
source adjustments and QC rework authority. Actual booking duration and calendar
commands remain unchanged. No caching or delayed data is introduced.

## Verified rollback measurement (staging, 16 September 2026)

Three paired measurements with complete JSON parity:

- Before: 1059.165, 1035.933, 1075.915 ms; average 1057.00 ms.
- After: 466.975, 493.461, 460.733 ms; average 473.72 ms.
- About 55% less database time in this measurement.
- Full snapshot remained identical: 180 candidates, 147 bookings, plus bay,
  calendar, pipeline and fitter-progress data.
- Unauthenticated and disabled accounts remained denied.
- All 38 station aliases, plus unknown and null inputs, returned identical
  eligibility rows in a separate read-only rollback check.
- The separate synthetic edge suite passed all 25 assertions: PMB, Yard Hold,
  IT with/missing ETA, location overrides, completed/not-required/hidden/QC
  exclusions, positive/sub-minute/zero/missing hours, complete JSON parity,
  unchanged existing vehicle/booking/fitter data, and denied access checks.
- All verification transactions rolled back; no permanent migration applied by
  this verification step.

These timings measure the database snapshot, not browser rendering/network time.
The historical pg_stat_statements average supplied by the parent investigation
was ~2963 ms, under different workload/cache conditions, so it is not used as the
before/after performance comparison.

Files:

- supabase/migrations/20260916004616_workshop_eligibility_snapshot_optimization.sql
- tests/workshop_eligibility_snapshot_rollback.sql
- tests/workshop_eligibility_edge_cases_rollback.sql

To review the candidate before deployment, insert its SQL at the explicitly marked
candidate-migration location inside each rollback test. Tests never commit.
