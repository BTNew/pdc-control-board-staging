# Autocare selection repair · Sales 2026.10.05.04

The row action previously passed only its own vehicle to the existing dispatch RPC. The selection button previously passed only checked vehicles visible under the current search. Both now use the complete approved, current selection. The row option shows **Dispatched Autocare (N selected)** when multiple vehicles are checked, including when opened from a vehicle already dispatched. With no multiple selection, a row action still targets that row alone.

Vehicles already dispatched are counted and retained without writing another mark. The remaining entries are sent in one atomic, exact-version RPC. A missing, ambiguous or delivered-to-dealer selected vehicle blocks the operation with a specific message; the selection is retained for correction. Only a validated successful response updates the tiles and clears the processed selection. Undo remains an explicitly labelled action for the individual vehicle.

Regression checks cover all five checked vehicles, exclusion of unchecked vehicles, selections outside the current search, already dispatched entries, partial-transfer prevention, failed/malformed responses, stale polls and account/salesperson scope protection. Fictional browser checks exercise a five-vehicle selection, one already dispatched, through the native row menu on desktop/iPad and selection button on laptop/phone. The existing server RPC is reused; no migration or live vehicle repair is required.

The full Node suite passes 1,683 tests. The reviewed Pages runtime build and all four browser viewports pass. Browser fixtures use synthetic source records and do not send emails or change actual customer records.
