# TODO

## Completed — Email job lines and ARB provisional hours (14 July 2026)
- [x] Email job-card/PO attachments import bounded structured work lines onto the matched vehicle card.
- [x] ARB February 2026 catalogue fitting charges are converted to hours only when one exact product code has one unambiguous catalogue fitting time.
- [x] Catalogue provenance shows product code, catalogue page, fitting charge, and the $160/hour rate from catalogue page 6.
- [x] Ambiguous vehicle-dependent codes, multiple product codes on one line, and unmatched work are never guessed; they remain orange and require review.
- [x] Vehicle cards show editable hours beside every imported job line; confirmation records operator, time, adjusted hours, and an audit event atomically.
- [x] Release version `2026.07.14.16-job-line-hours`.

## Completed — Workshop Planner hard-block release (14 July 2026)
- [x] Same-bay overlapping bookings are rejected; exact back-to-back bookings remain allowed.
- [x] Collision checks cover daily drag/drop, detail edits, resize, weekly moves, starting work, and job-allocation duration recalculation.
- [x] Mechanic overlaps across different bays are rejected separately from same-bay conflicts.
- [x] Conflict alerts identify the occupied bay/vehicle and direct staff to choose another bay or time.
- [x] Automatic cascade was removed; existing booking start times are never silently shifted.
- [x] Overtime live jobs continue to occupy their physical bay until their effective live end, preventing unsafe bookings against a still-occupied bay.
- [x] Detail edits and resize changes commit planner, vehicle estimate and audit state atomically; failed operator gating or persistence writes nothing.
- [x] Parts-entry protection, planner blocker ownership, operator attribution, and atomic planner/vehicle/audit rollback remain covered by safety regressions.
- [x] Full verification: Node 24 passed / 0 failed / 1 optional fixture skipped; backend 15 passed; local browser QA passed with no console errors.
- [x] Release version `2026.07.14.15-workshop-overtime-atomic`; hard-block code commit `aa840d99b7ce2cd500f4f3ab35a193e3819e4d40`.

## High priority
- Add browser-level import → PMB → Parts → RFT and backup/restore failure-path coverage at the supported desktop sizes.
- Plan permanent canonical vehicle IDs and alias-conflict migration as part of the shared backend rather than changing live identities piecemeal.
- Remove operational data from unauthenticated public hosting and complete the requirements/ownership decisions in `BACKEND_MIGRATION_PLAN.md`.
- Re-test Navision upload/paste workflow after every production-board change.
- Validate the new **Fix First** cards with the workshop team using real active vehicles.
- Confirm whether every imported stock vehicle should continue to require Parts sign-off by default.
- Keep Parts, RFT, and PMB screens role-focused so each team sees only fields and actions they can act on.

## Next visual improvements
- Tune the Control Board card density after live review on the actual workshop screen.
- Add stronger ageing bands on PMB and Parts views.
- Keep layout work focused on the desktop and workshop-monitor sizes in use; mobile/tablet support is out of scope.
- Add print-friendly views only after the browser workflow stays stable.

## Keep stable
- Missing or ambiguous vehicle lookup fails closed and never selects the first row.
- Multi-key imports/restores use the recovery journal and roll back on failure.
- `test_all.js` auto-discovers the regression suite.
- PMB transfer lands in Unallocated.
- Job ticks do not auto-allocate PMB production buckets or bays.
- Manual PMB `pmbStage` remains the only production bucket assignment.
- Current marker/job order remains T, H, F, Fa, E, Ty, PI, P.
- Parts must stay production-focused: no salesperson or finance fields in Parts views/exports.
