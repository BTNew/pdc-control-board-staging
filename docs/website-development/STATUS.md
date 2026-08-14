# Website work status

## Current

- Initial assessment and durable control documents on baseline `2f89fa5e93425ec22babf01065889d0611c6d817`.
- Application behavior remains unchanged.
- Next implementation may start only from an approved backlog item with its Craig decisions resolved.

## Completed in the initial assessment

- Verified branch, commit, tree and clean starting worktree.
- Read the Website Development Lead profile boundary.
- Inventoried QC/Vehicle Locations, workshop planner, Work & Bookings, vehicle identity, responsive CSS, Realtime/data services and local tests.
- Ran the complete safe Node suite: 217 passed, 0 failed, 1 skipped.
- Ran focused workshop/vehicle tests and two local rendered Chrome regressions.
- Ran ad-hoc Chrome fixture checks at 375x812, 768x1024 and 1440x900 with no body overflow, page/console errors or external requests on dashboard/workflow.
- Recorded one existing browser regression failure: `scripts/test_operational_ui_regression.js` did not find the Parts “Email sales” action at row end at 1600px.
- Created prioritized backlog, decision list, shared-file register, test matrix, risk register, integration status and Backend Contract Request log.
- Added no application tests because this assessment changed no application behavior; the required new browser coverage is tracked as WD-004.

## Blocked

- WD-001 QC mobile: Craig decisions CD-001, CD-002, CD-003 and CD-007.
- WD-002/WD-007 workshop mobile: Craig decisions CD-005 and CD-006.
- Cross-browser support matrix: Craig decision CD-008.
- Any security/data/Realtime/release integration: exact reviewed Hermes contract/SHA has not been supplied beyond the approved baseline.
- Live two-user, role and offline acceptance: staging/live access is prohibited in this task; use local simulated fixtures until separately authorized.
- Existing `scripts/test_operational_ui_regression.js` failure needs triage before it can become a release gate.
- Work & Bookings freshness and any new revision subscription must use the exact existing/reviewed Hermes Realtime interface (WD-019).

## Not started

All application backlog implementation. This assessment intentionally changed documentation/instructions only.
