# Website review — 13 September 2026

The review reproduced and repaired slow database reads, repeated Sublet rendering, background refresh bursts and several actions that could continue under a replacement session. It also corrected workshop location overrides, Yard Hold overview counts and search dates for jobs spanning several days.

Scope: the PDC Control Board staging website and its staging database, based on commit `288bd699f7adb70a5f6d84614eee7ddbc6a541db`. Production was not changed. Tests that exercise database writes use synthetic records inside transactions that roll back; no real customer import, booking, Parts change, QC signoff or transport action was submitted just to test the site.

## Performance measurements

| Measured component | Before | After | Meaning |
| --- | ---: | ---: | --- |
| Workshop eligibility overview database function | 15,595.6 ms | 2,892.9 ms | Three-run median; repeated eligibility and hours calculations removed |
| Sublet requirement projection, 1,000 synthetic items | 941.5 ms | 2.5 ms | Three-run median; one lookup per render instead of rebuilding it for every row |
| Best slot calculation, 57-hour job behind a 40-hour booking | 19,152.7 ms | 18.4 ms | Three-run median in an isolated planner runtime; both choose Friday 18 September at 07:00 |
| Background revision burst, 40 notifications during a read | Potential overlapping superseded reads | One active read plus one trailing read | Deterministic request-count test; the trailing read obtains the latest revision |

The time measurements cover the named components, not total page loading or a guarantee about every device and connection. Intake and operation-update queues now load concurrently, and one failed queue does not hide the other.

Best slot validation now visits each occupied working interval rather than restarting the calendar calculation for every minute. It also checks the selected mechanic's leave and conflicts in the loaded schedule, matching the assignment used for the proposed booking. The shared database remains the final authority for conflicts beyond the currently loaded planner scope.

## Workflow coverage and repairs

| Area | Scenarios checked and resulting behaviour |
| --- | --- |
| Imports and operation updates | New versus existing vehicles, missing station/hours, concurrent queue loads, stale refreshes, repeated approval, busy scheduling, uncertain replies and session replacement. Approval retains its request identity and updates the station estimate and affected bookings together. |
| Workshop calendar | Monday–Friday 07:00–17:00, Saturday 08:00–12:00, Sunday closed; long jobs continue through working intervals; five-hour gaps between one vehicle's jobs. |
| Booking interactions | Multi-bay cascades, Admin blocks, technician assignments, started/stopped work, protected conflicts, stale versions, idempotent retries and rollback on failure. Existing live bookings were checked for bay and vehicle overlaps. |
| Vehicle location | PMB and Yard Hold can book without an ETA; IT requires ETA plus seven days. Overrides now govern workshop eligibility, manual scheduling, moves, Book all and ETA warnings. Clearing an override restores source rules without changing source data or moving existing bookings. |
| Search and navigation | Exact stock identity, duplicate prevention, other-station results and selecting a result to show its day/bay. Multi-day results now show both dates in Perth time. |
| Sublet | Separate requirements, provider selection and new provider entry, pending/booked/returned identity, edits and returns, failed refresh after a confirmed save, unconfirmed results and bounded requests. Unsupported history controls are read-only. |
| Parts | Ordered, received, ETA, STOPPAGE and removal of STOPPAGE; permission/session changes during refresh or identity resolution cannot switch the writer. |
| QC | Checklist queue ownership, version progression, duplicate photo selection, logout during file reading, mobile preparation/rejection, receipt handling and final signoff authority. |
| RFT and transport | Independent actions on separate vehicles, duplicate protection for one vehicle, history and transport prerequisites, replacement sessions and completion ownership. |
| Presentation | Compact coloured import rows, operation descriptions without repeated Parts text, identity-only booking chips, Sublet work column and read-only state, planner navigation, multi-day search dates and Yard Hold overview counts. |

## Verification evidence

All 545 checks in the integrated repository suite passed. All 96 database checks passed: 38 operation/cascade cases, 16 eligibility cases, 25 location-override cases and 17 resource-conflict cases. Calendar validation also matched the prior implementation in 264 comparison cases and 72 additional independent boundary cases. The location migration received an independent review of all nine function changes, their existing permission checks and the ETA trigger.

A read-only snapshot found 93 active bookings with no bay overlaps and no vehicle overlaps. All 88 planned bookings had canonical estimated minutes and valid working-time starts. This is a point-in-time check; concurrent workshop activity can change the schedule later.

The live browser walkthrough covered New Vehicles, Vehicle Locations, the Control Board, all seven workshop planners, Fitting search and booking focus, Sublet lists, Parts and the empty QC queue. The visual review also found and repaired overflowing Control Board job-card text and missing connection-message spacing. Mutation failures and session changes were exercised with isolated fixtures rather than changing real workshop work.

Security advisors returned the same 958 findings before and after the database changes, with no additions. These are predominantly existing permission/configuration advisories and do not constitute a clean security audit. Existing warnings include password-leak protection being disabled and an extension in the public schema; these settings were not changed as part of the performance repairs. Privileged frontend values are checked by the release scanner and CI.

## Remaining limits

The Vehicle Locations response remains approximately 6 MB for 100 vehicles because several established operation projections repeat details. Current profiling measured about 1.39 seconds for its database function. Splitting list and detail responses is a further performance opportunity; removing those fields without migrating all consumers would risk Parts/QC/import behaviour, so this review preserved that contract.

The live QC queue was empty. Device-camera hardware, every possible data combination, every concurrent-user sequence and external email delivery cannot be established by the live read-only walkthrough. Deterministic tests cover the reproduced races and important failure boundaries. A request already submitted to the server may complete after a timeout or sign-out; the UI now distinguishes that uncertainty from a confirmed rollback.

Detailed scoped evidence is recorded in [Import and Sublet review](full-site-import-sublet-review-20260913.md), [Lifecycle, QC and Parts review](full-site-lifecycle-review-20260913.md), and [Workshop eligibility and location review](workshop-eligibility-and-override-review-20260913.md).
