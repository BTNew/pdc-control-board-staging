# Workshop clock cascade — STAGING

Applied migration: 20260910213833_workshop_clock_cascade.
Project: cdsmnqxtyyoeoznmbidd. Production is excluded by an environment guard.

Every minute, overdue unstarted planned work moves to the next available workshop minute. Delay propagates through the whole bay queue, including bookings weeks ahead, while preserving gaps in working time. Live work retains its actual start; only newly accrued overrun pushes future planned work. Watermarks prevent repeat runs from adding the same delay again.

The server schedule runs with the browser closed. Existing authenticated planner snapshots also invoke the same worker. Workshop opening hours, breaks, closures and fixed Admin reservations remain authoritative. Existing vehicle, ETA, technician and overlap guards remain active. A guard conflict rolls back that bay and records its reason in workshop_clock_status; other bays can proceed. It does not silently remove conflicts or shift unrelated bays. No approvals, vehicle location changes, new bookings or completions are created.

Internal functions and history/status tables are private to the database owner. Automatic changes have their own audit history and do not impersonate staff.

## Validation

Rollback tests cover a two-hour delay, adjacent work, a booking four weeks ahead, replay, incremental live overrun, weekends, closures, breaks, Admin reservations, private execution, real booking writes and unchanged vehicle/work state. All temporary records were rolled back. Three scheduled live runs succeeded on 10 September at 21:39–21:41 UTC; no active bookings existed and the dry run reported no issues.

Regression SQL is transactional and intended for isolated STAGING validation, not production. Stop the clock if needed with SELECT cron.unschedule('staging-workshop-clock-cascade');. Retain audit and watermark records when stopping it.
