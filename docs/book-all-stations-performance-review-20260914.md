# Book all stations performance review

The staging API history recorded 38 Book all calls averaging 7.22 seconds, with a maximum of 25.47 seconds. A rolled-back test reproduced the delay with a synthetic vehicle requiring 57 hours of Bus 4x4 work, 8.5 hours of Fitting and 3 hours of Electrical work: the booking action took 23,664.9 ms.

The canonical duration helper was inspecting every elapsed minute, including nights and weekends, and repeating JSON calendar checks for each minute. It now consumes each interval whose availability is unchanged. Regular hours, overtime and break boundaries divide those intervals; closed days are skipped. This preserves the existing minute rounding, Perth timezone, exact endpoint and 90-day limit. The existing function's signature, volatility, security settings and privileges remain unchanged.

The individual vehicle eligibility gate also previously constructed the entire station queue and calculated every vehicle's estimated hours before selecting the requested vehicle. It now reads that vehicle with the same membership and existing-booking predicates. The rest of the gate's return ordering, Sublet checks and ETA rules are unchanged.

With the calendar improvement alone, the same Book all scenario took 4,906.4 ms and 4,854.4 ms. With both improvements, independent runs took 3,518.5 ms and 3,531.7 ms, about 85% below the reproduced baseline. Every run selected the same three bays and the same starts and finishes. These timings measure the database booking action with synthetic records against the staging schedule; they exclude browser rendering, network latency and page refreshes.

Verification:

- 278 exact comparisons against the previous calendar function, including Saturday 08:00–12:00, Sunday closure, irregular breaks, overlapping overtime, date-specific settings, second-valued boundaries, invalid inputs and exact/overflow 90-day durations.
- 32 gate checks, including 28 comparisons against the previous gate response and unchanged authorization/privileges and existing data.
- 80 existing operation-approval, cascade, override and resource-conflict cases. These cover started/stopped work, assignments, leave, Admin blocks, Sublet absence, exact durations, protected conflicts, stale requests and atomic failures.
- 14 Book all checks covering the long multi-station job, ETA plus seven, five-hour elapsed gaps, existing-booking skips, retries, stale versions, missing hours, a failure after the first station, Sublet absence and a combined vehicle/bay/Admin conflict. All pre-existing bookings and vehicles remained unchanged.

All mutation verification uses synthetic fixtures inside transactions ending in ROLLBACK. The Book all write function, resource locking, stage ordering and all-or-none transaction behavior were not changed. Book all continues to create unassigned bookings, as before; this work does not add automatic technician assignments.

The browser now sends the uniquely matched, already-loaded vehicle version directly. The server still locks and validates that version before booking. Missing or mismatched local data requires a guarded refresh. An explicit version conflict refreshes the board without retrying automatically; uncertain network or timeout outcomes never claim success or rollback.

Confirmed results enable Close immediately. Vehicle and planner refreshes run together in the background, with failures reported as saved bookings needing a refresh. Request/session ownership prevents old responses from affecting another vehicle or a new sign-in. The booking request and refreshes have bounded waits; late completions cannot repaint an expired request.

All 531 other website regression checks and 28 Book all browser-behavior checks passed (559 total). The latter cover immediate cached dispatch, canonical identity reconciliation, raw eligibility, double-clicks, parallel refresh, server rejection, uncertain network/JSON outcomes, bounded timeouts and same-actor session replacement. They also check offline or permission-denied planner refreshes that resolve with retained data rather than throwing.

Both guarded migrations were applied to staging and read back: `20260913222020_workshop_operational_calendar_intervals` and `20260913222324_workshop_candidate_gate_point_lookup`. A fresh post-apply run passed all 14 Book all checks and completed the long booking in 3,586.0 ms. Function privileges and the Book all transaction function are unchanged. Security and performance advisor findings are identical to the pre-change baseline, excluding observation timestamps.
