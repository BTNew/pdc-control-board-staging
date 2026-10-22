# Parts ETA booking warning (r482, F95)

Craig, 22 Oct 2026: when a vehicle is booked into bays and it has a parts ETA after the booking date, warn first, but
still allow the booking. No ETA, no warning.

## What staff see
A "Parts not due yet" box before the booking is saved:

- the parts ETA (Perth date, e.g. "Thu 29/10/26"; "latest of N parts" when several parts are due),
- each station / bay / start time that is before the ETA,
- **Cancel** (default; Escape does the same) makes no booking and changes nothing,
- **Book anyway** books exactly as before.

A booking counts as "before the ETA" when its start, as a Perth calendar date, is earlier than the vehicle's latest active
parts ETA (`get_pdc_parts_eta_board_v2`: not superseded, open parts job). A booking on the ETA day or later is not warned.

## Where it asks
| Path | How |
|---|---|
| Planner: drag from Unallocated, search / Find a booking result, chip drag (same or another bay), the Schedule window, Best slot / Schedule next, the booking detail form (when the start or bay changes), weekly view moves, the vehicle card's station Schedule button | All go through `workshopDispatchSharedAction` (`workshop-planner.js`), which asks before the command is sent |
| Planner: bay re-order (Move ahead of / Swap) | Asked at Apply, using the bookings its preview moves |
| Book all stations (Vehicle Locations table, drop-down and board rows; one button) | The server picks bays and times and has no dry run, so it asks first when the ETA is after today ("the earliest start is today"). The result table then marks each booking that starts before the ETA |
| Emergency vehicle priority (Prioritise vehicle & move bookings) | Asked at apply, using the preview's bookings for the vehicle |

Not asked: extend / resize (start unchanged), a detail save that keeps the start and bay, undo of a move or re-order,
cancel / return to queue, the capacity re-plan (moves every vehicle; not a staff booking), tune operation approval
(re-times an existing booking after an hours change), the local (non-shared) planner fallback.

## Record of the acknowledgement
Planner commands that take `p_metadata` get `parts_eta_warning: { acknowledged: true, eta_date, bookings_before_eta,
release: 'r482' }`, which the booking RPCs keep in their audit / receipt metadata (jsonb; no schema change).
`book_all_vehicle_stations` and `prioritise_workshop_vehicle` take no metadata, so nothing is recorded for those.

## Not changed
No SQL. Booking RPCs, the clock tick and the parts ETA data are unchanged. If `pdc-parts-eta.js` fails to load, bookings
work exactly as before (warning only, never a gate).

## Tests
`test_parts_eta_booking_warning_482.js` (12 tests; 10 fail on main 2b1c320). `test_parts_eta_email_source_475.js` now allows
later release tags after `r475=` on the parts ETA script (its exact-end match would otherwise fail on the r482 tag).
