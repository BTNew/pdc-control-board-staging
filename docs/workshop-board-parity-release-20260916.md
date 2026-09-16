# Control Board and station planner parity

The all-bay Control Board previously clipped booking pills at their original scheduled end. Individual station planners extended running jobs through the current working minute and retained carried-over work. The two views therefore showed different occupancy for the same canonical booking.

Both views now share the effective-end calculation. The Control Board retains multi-day continuations, uses the configured 06:00–16:30 weekday envelope, and shows displayed times and continuation details in booking tooltips. Stoppages retain the station planner’s recorded-stop and scheduling-increment rules. This projection does not alter booking allocations or claim that work has completed.

Display-only key and job-card supplements come from uniquely matched, authenticated vehicle UUIDs and their active operation lines. Stock-number guesses, local records and ambiguous identities are excluded. Canonical fields keep precedence.

The Control Board also reconciles missed live updates and advances its display clock while open. Authoritative changes continue to use existing protected workshop commands.

## Start-job investigation

The current canonical Start path was exercised against stock 13021292's actual dependency graph using a synthetic operator inside a mandatory rollback. It successfully proposed and applied the start and moved nine affected bookings in approximately four seconds. Both the successful operation and the test actor were rolled back. Booking rows, assignments, audit/history, command receipts and revisions were checked for restoration. No real job was left started by this diagnostic.

An additional failure was reproduced when the automatic workshop clock advanced a planned booking version after a fitter loaded it. The narrow Start repair accepts only a continuous, recent chain of proven clock-only changes. Bay, assignment, vehicle, work-scope, and catalog changes still fail closed. Other commands retain their original version checks and command retries retain their original receipt identity.

The repaired stale-version request was also exercised against the same real dependency graph: it returned a confirmed running state and shifted nine planned bookings in approximately four seconds. This second diagnostic was fully rolled back.

## Verification

- 939 JavaScript checks passed, covering shared timing, working-day continuation, progress, search ranges, identities, refresh races, permission failures, and existing workshop/fitter regressions.
- 20 overview database checks passed. All 146 active bookings matched the seven individual station snapshots by identity, status, version and timing over the same 15-day range.
- The overview revision endpoint is limited to already-approved overview viewers. Existing direct-table row policies are unchanged. Anonymous and missing-identity requests were denied.
- Synthetic visual fixture checked running overtime, previous-day carry-over, planned multi-day work, recorded stoppage, progress bars and the 4:30 pm boundary.

- 29 Start rollback checks passed both before and after deployment: fitter confirmation, same-request replay, UTC/Perth clock chains, protected manual/version/assignment/scope changes, expired evidence, catalog mismatch, strict non-Start versions and private helper access.
- Independent review caught concurrent bay-default/line-adjustment races. Nonblocking locks now protect the proof and reject a rebase when edits are in progress, avoiding reversed-order waits.
- Security advisors retain the 980 existing findings plus one expected finding for the new intentionally authenticated revision RPC. Its viewer-role gate and anonymous denial were verified; no existing permissions were widened.

## Staging database deployment

- Overview migration: 20260916065145, SHA256 c8ee479cc09d5352364486b1dc6f6f0da0ec5bc3911cf9bed9d12334204b5c4a.
- Start migration: 20260916065517, SHA256 13298e980e2852b30b57f0eca35f4e30e431ce9e2907e168c55affd9f41331f2.
- Installed assertions passed, migration bytes matched, and all synthetic users, bays, vehicles and technicians were absent after rollback.

Real Start remains a user action. No operational job was left started by verification.

The concurrent Controller vehicle-move release (#205) is preserved, including its permissions, cache version and migration record. The final939-check suite includes its regression tests.
