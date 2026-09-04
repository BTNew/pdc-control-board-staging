# PDC-14 authenticated deployed STAGING verification

Task: `t_8075c085`  
Completed: 2026-09-05 (AWST)  
STAGING URL: <https://btnew.github.io/pdc-control-board-staging/>  
STAGING project: `cdsmnqxtyyoeoznmbidd`  
Deployed main SHA: `392c55e78b14fea048ee76c2c82b85e299ff271c`

## Verdict

PASS. The authenticated current-head browser harness verified all 14 requested control-board fixes against deployed GitHub Pages and authoritative STAGING database read-back.

The final run returned `all_checks_passed: true`, no execution error, no console error, no page error, no failed request, no HTTP error, and no Production request.

## Repairs found and deployed during verification

The all-items verifier exposed three related defects in the vehicle-card workshop completion path:

1. Its request hash did not match PostgreSQL `jsonb::text` ordering and whitespace.
2. Required camelCase bridge parameters (`vehicleId`, `bookingId`, and `idempotencyKey`) were omitted, producing a PostgREST function-signature 404.
3. A stale Vehicle Detail version could be sent after Parts mutations; the action now selects the newest authoritative detail/email/local version.

The action now refreshes authoritative work state before rerendering the completed tile. The `app.js` asset URL was also bumped so Pages/CDN clients load the repairs.

Merged PRs: #37, #39, #40, and #42.

## Evidence

- `pdc14-deployed-authenticated.json`: complete authenticated browser, mutation, 14-item matrix, authoritative read-back, and cleanup record.
- `09-completion-green.png`: all workshop-bookable required-work tiles shown green/completed after the deployed vehicle-card action.
- `08-parts-complete.png` and `07-parts-stoppage.png`: Parts received and STOPPAGE behavior.
- `06-planner-refresh.png`: deployed Workshop Planner refresh.
- `05-booked-orange-matrix.png`: all workshop-bookable work types in booked/orange state.
- `04-location-pmb-and-detail.png`, `03-save-all-hours.png`, and `02-copy-stock-feedback.png`: Vehicle Detail behavior.

Final deployed `app.js` SHA-256 matched `origin/main`: `617be8a52f07b6f596f6fbc99cb7b83d25e0e9ca42754ca7079e83a492ea7367`.

## Cleanup and safety

The bounded fixture was archived and cleaned. Final counts were zero for Auth user, role, vehicle, work items, Parts, scope, Sublet, workshop bookings, operation lines, Navision batch/record, and schedule-recovery rows. Cleanup errors were empty. The STAGING sentinel remained present and the Production sentinel remained absent.

No credentials or password were retained. No email was sent. Production was not contacted, written, or deployed.
