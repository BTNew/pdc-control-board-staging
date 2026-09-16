# Fitter workflow and workshop hours — 16 September 2026

The new Fitters bay screen uses active mechanic and bay/booking assignments, shared booking lifecycle controls, separate fitter operation records and approved-hour-weighted progress. QC inspection records are not changed by fitter item completion.

## Verified
- 833 JavaScript checks pass.
- Database rollback verification covers assignment routing, canonical start, controller-already-started behavior, 10% then 30% progress, per-item notes, retries, stale versions, changes to operation hours, stopping/resuming, incomplete completion rejection, station completion, QC isolation and both planner snapshot surfaces.
- Synthetic test records and changes roll back. Existing operational bookings and vehicles remain unchanged by fitter verification.
- iPad browser workflow checked: select mechanic, start, tick lines, save note, parts stoppage, resume, interrupted-save retry, complete and show next job.
- 834px iPad and 390px phone layout checks; long descriptions wrap. No content overflow in measured work cards.
- Proposed 06:00–16:30 weekday hours tested against the staging schedule inside a rolled-back transaction. No invalid planned intervals remained after recalculation. The live change is applied through the signed-in administrator’s Setup action.
- Security review: private tables have no API grants and deny access through RLS; authenticated RPC grants are intentional, with database role checks and assignment checks before writes. No anonymous grants or QC authorization expansion.

## Behavior
- Select a mechanic; a booking-specific assignment overrides the bay default.
- Current / next / following jobs are visible. The operation list edits only the selected station; other vehicle items remain visible as read-only context.
- A 1-hour completed item out of 10 hours = 10%; completing another 2-hour item = 30%.
- Imported description, station, job-card or hour changes invalidate the affected saved tick.
- Save success is confirmed by the database; interrupted writes can retry the same idempotency key. A stale client must refresh.
- The fitter view refreshes every ten seconds while visible, except while typing a note. Planner updates use the existing shared booking revision mechanism.
- Finish marks the bay booking/work requirement complete, not the independent QC inspection.
- No live vehicle was started, ticked, stopped or completed as a browser test.

## Scope
This deployment adds a fitter workflow and a specific administrator action for the requested 06:00–16:30 weekday hours. Saturdays and Sundays remain closed; existing breaks, closures and overtime rules are retained. Planned jobs are recalculated; already-started work is retained.
