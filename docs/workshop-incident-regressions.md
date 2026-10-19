# Workshop incident prevention

Craig requires every reported problem to retain its symptom, verified cause,
repair, release, regression coverage and remaining verification gaps.
Keep customer evidence and detailed logs in the private issue register outside Git.
Do not infer a historical cause without evidence. Reopen an issue if it recurs.

## Returned and accepted jobs

- A queued reservation without a bay is Unallocated. Its retained historical
  dates must not remove it from the station candidate lane or reserve capacity.
- Reallocating a returned job must reuse its reservation identity and hours.
- Station search includes only that station and Bus category. Control Board
  search may cross stations.
- Approved PMG records without dealer mappings require exact accepted job
  evidence before scoped reads. No client fallback grants write authority.
- Permission denials and read failures must not be displayed as an empty queue.
- Combining the Board, station and eligibility projections must retain the
  canonical read identity even when a vehicle is absent from this station.
  Eligibility can explain missing hours but cannot grant station scheduling
  authority. Cover that combined path, not just the separate API adapter.

Regression coverage: `test_workshop_search_station_scope.js`,
`test_workshop_booking_search_service.js`, `test_workshop_pmg_read_scope.js`,
`test_workshop_search_projection_identity.js`,
`tests/planner_search_returned_visibility_rollback.sql`.

## Estimates and running work

- Saving estimated hours and editing source-line hours must reconcile the
  affected booking. Running work keeps its start, status and progress.
- Extend later reservations forward through workshop opening hours, handovers,
  staff availability and supplier conflicts.
- Unallocated historical intervals cannot block this reconciliation.
- Keep active reservation overlap constraints, source-hour minimums, stale
  version checks, idempotent retries and the audit history.
- Never claim that a database rollback proves a real browser drag.

Regression coverage: `tests/running_booking_estimate_rollback.sql`.
This scenario checks save, automatic line editing, a following reservation,
Unallocated preservation, retry and source-hour guards.

## Dragging from search

- A draggable result uses the same candidate or reservation identity as its
  station lane. Recheck trusted state when dragging begins.
- Cancelled or completed dragging clears preview and scrolling state.
- Test real browser input with synthetic records only. Record tool limitations
  separately from application defects.

Regression coverage: `test_workshop_search_drag.js` and the private browser
fixture using the same event handlers.
