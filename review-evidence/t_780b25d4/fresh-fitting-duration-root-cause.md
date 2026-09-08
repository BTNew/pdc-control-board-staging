# Fresh Fitting duration repair — t_780b25d4

## Live symptom

The 09/09/2026 deployed STAGING screenshot shows Fitting candidates 12705177 (IT), 13007660 (YH), and 13015144 (PMB) as `Estimated: Hours unknown` while `Best slot` and `Schedule` remain enabled. The attempted booking was rejected atomically with HTTP 400 / SQLSTATE 22023: `operation_estimate_duration_mismatch`, `expected_minutes: 135`.

## Proved root cause

The scoped station response already supplied the correct canonical candidate duration (`outstanding_candidates[].estimated_hours`; 2.25h/135m for stock 12705177). `workshopPlannerVehiclesForStage()` copied that value into the candidate used to calculate the Best-slot preview. However, every actual schedule path converges on `scheduleWorkshopVehicle()`, which calls `workshopVehicle()` again. That action lookup rebuilt the row from raw `snapshot.vehicles[]` and did not merge the matching outstanding candidate's `estimated_hours`. With scoped operation rows intentionally absent, `workshopCalculatedStageHours()` then fell through to a browser default instead of the canonical 2.25h. The server retained the correct operation-derived 135-minute guard and rejected the mismatch. Independently, `workshopQueueEstimatedLabel()` ignored the authoritative stage-hours map and inspected only operation rows, creating the truthful-looking but incorrect `Hours unknown` display.

The defect was therefore a client projection split between render-time and action-time rows, not missing source hours and not a server duration-validation fault.

## RED evidence

`test_workshop_fitting_authoritative_duration_t780b25d4.js` constructs the real scoped response shape: a raw vehicle, one Fitting outstanding candidate with `estimated_hours: 2.25`, no scoped operation lines, and schedule enabled. Before the fix it failed because the action-path row contained `{}` instead of `{ FITTING: 2.25 }`. Capture: `red-fitting-authoritative-duration.txt`.

The exact test from t_a9b37ed9 commit `38a8124662421ffd44871e3b5c5e707bcc5c166d` was also run unchanged and failed because the detail validator accepted a missing `vehicle_version` and an incomplete booking row.

## Minimal repair

- Merge the one matching authoritative candidate duration into `workshopVehicle()` so manual Schedule, Best slot, and drag/drop all calculate the same exact duration and submit 135 minutes.
- Make the queue label prefer that same authoritative stage duration; it now displays `2.25h` even when operation rows are omitted by the scoped response.
- Fail the shared Workshop detail response closed unless `vehicle_version` is a positive integer and every booking contains identity, stage, status, positive version, and a valid increasing scheduled interval.
- Advance both dynamic planner and app-shell cache identities.

No SQL, schema, RLS, ETA, capacity, or server duration guard was changed. No hours were invented and no blanket one-hour default was added.

## GREEN evidence

The focused Fitting duration regression, exact t_a9b37ed9 contract regression, Job Card live-hours regression, Pilbara projection regression, arrived/ETA regression, and exact-operation-minutes regression pass. The complete Node suite and static syntax checks pass: 199/199. Capture: `green-full-node-suite-final.txt`.

## Safety

This repair has not contacted or written Production, email, or Navision monitor systems. No database migration is required. Live STAGING booking verification must capture the original booking state, commit one authoritative booking, read it back, then restore the exact original state with audit receipts.
