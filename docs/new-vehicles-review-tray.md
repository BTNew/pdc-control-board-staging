# New Vehicles review tray — STAGING

Opening a pending vehicle retains its classified stations. Only uncertain operations appear in the full-width Needs Review tray above the station sections. Dragging or the Move to dropdown assigns each operation locally; dragging back returns it to review. Approval stays disabled while any operation remains unassigned. Department 138 remains assigned and locked to Bus 4×4.

The desktop layout places eight station sections beneath the tray and adapts to smaller screens. The tray scrolls for longer job cards. On phones the approval footer appears after the sections so it does not obscure pills. Polling retains in-progress choices; no database writes occur before explicit approval.

Craig's 2026-09-10 rule sets every pre-delivery operation to 1.00 working hour, including zero, missing and nonzero source estimates. Pre-delivery defaults to Fitting except Department 138; explicit manual station changes remain available. Applied STAGING migration 20260910074821_pre_delivery_one_hour_standard enforces the rule in QC/New Vehicles, board snapshots, planner totals and unidentified review. Existing and future operations use the standard without rewriting immutable source rows, hashes or import receipts. The dynamic importer and historical replay receipts are unchanged.

Validation: all 341 JavaScript tests passed. Database regression checks passed before deployment and on authoritative readback afterward: description variants, source hours, source/receipt preservation, unrelated operations, New Vehicles, workshop totals, board snapshot and unidentified review. Screenshot vehicle 13070889 has Pre-Delivery (Commercial) in Fitting at 1.00 h and its uncertain PTE tray item in Needs Review. Isolated browser checks passed for drag down/back, dropdown moves, refresh, desktop/mobile layout and Department 138 locking. No approvals, bookings or completions were made. Production untouched.

New helper functions are security invoker, use fixed search paths, and have execution revoked from application roles. Existing RPC authorization and grants remain unchanged.
