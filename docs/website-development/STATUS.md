# Website work status

## Current

- QC mobile reliability implementation is independently reviewed, fully gated and finalized locally on parent `015aa0a0ef3c5d26ee4310959a749d5c24957f78` for the Website Development Lead commit. No push, merge, staging or deployment is authorized.
- No backend, authority, package, release, staging or production interface changed.
- Product-dependent QC workflow/identifier/label choices remain blocked; implemented changes preserve the current action path and semantics.

## Completed in the QC reliability tranche

- Replaced the forced desktop Vehicle Locations row with contained task cards through 1100px while retaining all existing information and action order.
- Kept desktop station alignment and made the action track reachable without row panning.
- Added vehicle-specific station accessible names, 44px mobile controls, stable vehicle-plus-action duplicate protection across board rerenders and accurate post-save print-failure copy.
- Added Vehicle Details focus trap, Escape, background inertness and exact opener focus return for ordinary frontend operation. Auth-refresh inert ownership remains blocked by BCR-001 and is not claimed complete.
- Added deterministic source contracts and an isolated Chrome runner covering 360x800, 390x844, 768x1024, 820x1180, 1024x768 and 1440x900.
- Browser evidence: zero body overflow, page/console/resource failures or non-local requests; mobile/tablet list overflow 0; fixture render remained below 3ms in the latest run; a replacement button for the same vehicle/action remained single-dispatch.

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

- Final WD-001 QC information architecture/copy: Craig decisions CD-001, CD-002, CD-003, CD-007 and CD-010.
- Label retry/acknowledgement after a committed QC save: CD-004.
- WD-002/WD-007 workshop mobile: Craig decisions CD-005 and CD-006.
- Cross-browser support matrix: Craig decision CD-008.
- Any security/data/Realtime/release integration: exact reviewed Hermes contract/SHA has not been supplied beyond the approved baseline.
- Vehicle Details isolation across auth lock/unlock/refresh/role transitions: BCR-001 pending Hermes review; `pdc-auth.js` remains untouched.
- Live two-user, role and offline acceptance: staging/live access is prohibited in this task; use local simulated fixtures until separately authorized.
- Existing `scripts/test_operational_ui_regression.js` failure needs triage before it can become a release gate.
- Work & Bookings freshness and any new revision subscription must use the exact existing/reviewed Hermes Realtime interface (WD-019).

## Not started

Workshop schedule implementation, Work & Bookings freshness, cross-browser gate, full state/role/two-user fixture matrix and remaining dialog standardisation.
