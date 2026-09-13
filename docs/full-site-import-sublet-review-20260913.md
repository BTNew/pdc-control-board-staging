# Import and Sublet workflow review — 13 September 2026

Reviewed the staging main release `288bd699f7adb70a5f6d84614eee7ddbc6a541db` and corrected confirmed frontend concurrency, failure-feedback and rendering problems. No customer approvals, bookings or source records were changed by this audit.

## Corrections

- New Vehicles and updated-operation queues now load concurrently. Failure of the new-vehicle list no longer prevents valid operation updates from loading.
- Background refresh displays busy navigation, captures the requested queue and page, and prevents list switches from assigning a response to the wrong queue. Approval invalidates an older pending read, which otherwise could put just-approved work back on screen.
- New-vehicle approval completion, errors and cleanup belong to their original operator, session, token and request. An old request cannot unlock another operator's save. An uncertain retry retains the original idempotency key and assignments.
- Sublet changes waiting behind an earlier edit cannot run under a replacement operator, token, service or permission. Authentication reset detaches the old queue so a hung request cannot block a new session. Requests time out after 60 seconds without automatic retry.
- Sublet accepts only an explicit successful response. Unknown results are described as unconfirmed; accepted writes followed by a failed list refresh are described as saved with a stale display warning.
- Expanded Sublet controls now match the supported actions: Back records the actual return, shared email status is read-only, and returned booking notes/contact details remain read-only.
- Sublet decoration builds its vehicle/operation lookup once per render instead of rebuilding every vehicle's requirements for each visible row. Pending, active, returned and legacy row identities remain distinct.

## Controlled performance evidence

Three-run medians using the real application `subletRows`, `pending` and `notes` projection functions, with four synthetic requirements per vehicle:

| Requirements | Before | After | Full queue projections |
| --- | ---: | ---: | ---: |
| 100 | 13.088 ms | 0.385 ms | 100 → 1 |
| 500 | 240.970 ms | 1.517 ms | 500 → 1 |
| 1,000 | 941.533 ms | 2.518 ms | 1,000 → 1 |

This measures the Sublet decoration/projection component in an isolated Node VM. It excludes table construction, browser layout and network latency; it is not a live whole-page loading measurement. Raw evidence is retained outside the release tree in `work/sublet-full-review-performance.json`.

## Verification

72 focused import/Sublet tests passed together. Coverage includes source identity and receipt validation, station/hour rules, operation-update busy retries, duplicate clicks, same-request manual retries, stale queue responses, signed-out/replaced sessions, queued Sublet edits and returns, request timeout, malformed responses, accepted-save/readback failure, provider duplicate/inactive/error handling, and separate bookings for each requirement. The historical operation-approval harness now uses the real module's state declarations; its assertions were preserved.

The independent refresh-coordinator review found the new coalescing behavior consistent with runtime routing. Additional tests cover a queued board refresh after switching to New Vehicles/setup, and an old invalidated refresh finishing after a new operator's route request. The supported-route, error and 40-revision burst cases also passed.

Follow-up Control Board layout review confirmed that three identity fields inherited the global four-column template, overflowing into the vehicle description. A local three-column template and narrower responsive row minimums separate identifiers, model and customer. The connection banner now has explicit spacing and wrapping. Header/search/empty-state wording includes eligible Yard Hold and In Transit vehicles. Existing Control Board parity and operational-refresh regressions passed; visual verification remains part of the coordinating staging check.

Live browser measurements, database scheduling/concurrency checks, the complete repository suite and staging publication are recorded by the coordinating review. These scoped checks do not establish that every possible external network, concurrent-user or workshop-data condition is covered.
