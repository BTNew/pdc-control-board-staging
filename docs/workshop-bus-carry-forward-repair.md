# Bus 4×4 automatic carry-forward repair

## Cause

A future Coaster booking was allocated to HiAce-only Bay 3 before that restriction was introduced. Its failed compatibility check rolled back the connected bay schedule, including an earlier valid HiAce booking. The minute cron still executed, but the returned clock result reported the failed component.

An independent reproduction with a valid HiAce also exposed a calendar mismatch: the automatic clock calculated a global-workshop finish, while the Bus booking trigger calculated a bay-shift finish. The technician-assignment interval then failed validation. The clock's protected-field check also needed to recognize the narrowly validated migration to Bus calendar version 1.

## Changes

- Automatic rollover uses the existing Department 138 bay calendar for starts, finishes, accumulated delays, live-work floors and obstacle avoidance. Other workshops retain their existing calendar.
- Every saved booking is checked against the accepted plan before its technician assignments are updated. The calendar marker can only remain at 1 or change from null to 1 for an eligible Bus booking.
- Bay compatibility, parts readiness, actual start/finish history, durations and work progress retain their existing protections. A failed connected component remains atomic; independent components can advance.
- Station planners and the Control Board clip migrated Bus bookings to the same bay shifts and refresh from saved schedule revisions. The browser does not invent a later planned start.
- The canonical Return to Unallocated action now supports a planned booking through its existing one-use authorization. A version conflict clears any unused authorization, and direct status updates remain prohibited.

## Operational correction

The user approved returning the incorrectly allocated Coaster to Unallocated because mechanical parts have not yet been physically confirmed. Stock 12311152 was returned through the canonical action with its 10,354-minute duration and all other booking fields preserved; parts readiness remains unconfirmed. This operational correction is separate from the schema migrations.

## Verification

The original clock failed a valid-HiAce regression with `Assignment interval must equal booking interval`. The repaired clock passed 160 rollback assertions covering legacy/current Bus calendars, shift ends, breaks, closures, weekends, live/stopped/admin/queued obstacles, same-vehicle handover, assignment parity, repeat-tick idempotence and incompatible linked-booking failure isolation. Existing customer records and imported operations were unchanged by the tests.

The website suite passed 1,210 checks, including nine new persisted-snapshot and calendar-rendering scenarios. Browser visual inspection was unavailable in this execution environment; no screenshot-based verification is claimed.

The Return to Unallocated repair passed 67 independent rollback assertions, including rejected direct changes and cleanup after stale-version requests. A dry run against the affected customer arrangement also passed: stock 12771601 moved forward with its 3,542-minute duration intact, and its active technician assignment exactly matched the booking. The preview and applied plan agreed and unrelated bookings were unchanged. All dry-run changes were rolled back before the separate authorized correction.

Applied staging migrations: `20260921012441_workshop_bus_clock_calendar` and `20260921012445_workshop_planned_return_to_queue`.

Two consecutive live minute-clock updates at 09:26 and 09:27 Perth on 21 September succeeded. The HiAce advanced from 09:27 to 09:28 with unchanged duration, no actual start recorded, and matching active mechanic-assignment times. No bay had a remaining clock error. The Coaster remained Unallocated with parts unconfirmed. Deployed function bodies matched the reviewed migration, existing execution permissions were preserved, and security advisors reported no new findings.
