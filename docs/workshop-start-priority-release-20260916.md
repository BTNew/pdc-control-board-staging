# Workshop Start takes physical-vehicle priority

Previously, an earlier unstarted booking for the same vehicle could reject Start in another department. Start from the workshop planner or Fitters bay now starts the selected booking at the database clock and moves the vehicle’s other unstarted bookings later, preserving their relative order. Affected bay queues and their vehicle dependencies move as one transaction.

The one-hour vehicle handover, weekday workshop hours, breaks, bay efficiency, technician assignments and leave remain enforced. Running and stopped work, admin downtime and other protected records are not displaced. Cyclic schedule changes use validated temporary reservations within the same transaction; only original-to-final movements enter booking history. Any failed write rolls back the entire start and cascade.

Planner Start no longer rejects a request based on a stale cached bay conflict. Both screens display pending feedback, ignore repeated taps while saving and report the server-confirmed count of moved bookings. The fitter timer begins only after canonical start confirmation. The current-job/next-job iPad layout is retained.

This supersedes the earlier planned-order restriction recorded in the fitter timer release. The existing blocker test now uses an already-started Tint booking. No actual operational vehicle was started or rescheduled for verification.

## Verification

- 894 JavaScript tests passed after merging the concurrent fitter-only account update.
- 51 database rollback assertions passed: long-job booking reversal, dependent queues, slower bay efficiency, downtime, default and explicit mechanics, leave, fixed-work rejection and failure after a temporary reservation and attempted start.
- 16 installed-migration confirmation checks passed; the canonical planner snapshot reflected the fitter Start.
- 15 protected-work and timer checks passed on the installed migration.
- 18 additional rollback checks verified priority Start under the restricted fitter-only account role, including denied direct planner access.
- Isolated browser checks confirmed pending Start, running timer, stoppage, resume and mobile layout without horizontal overflow.
- Security advisor baseline unchanged: 980 existing findings, zero additions. Function access grants remain unchanged.

Staging migration: 20260916021045_workshop_start_priority_for_unstarted_vehicle_jobs.

Frontend cache revision: fitter JavaScript 2026.09.16.05; planner and app start-priority 2026.09.16.05.
