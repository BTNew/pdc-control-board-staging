# Bay technician reassignment after reset — 17 September 2026

A browser could submit the bay version it loaded before the technician reset. The protected setter correctly rejected that stale version, but the planner surfaced an unclear bay-default error.

The assignment path now reads current bay authority before saving and retries once only for a definitive version conflict whose assignment has not been replaced by another user. An unassigned bay after reset can be assigned again. A different concurrent non-null assignment is retained. The selected dropdown remains disabled while its request is pending. Lost or ambiguous write responses are reconciled without replaying the write. Confirmed bay saves and later booking-assignment failures are reported separately.

Booking backfill remains limited to unassigned planned bookings in the selected bay and department, using each booking's version. Existing assigned, live and completed work stays intact. Navigation and account/session changes stop remaining dependent writes. No database permissions or scheduling rules changed.

Validation:
- Actual authenticated staging assignment/clear path tested for all 43 workshop bays: 172 assertions passed inside one rolled-back transaction. Booking and booking-assignment checksums were unchanged.
- All 45 stored bay records still had no default technician after verification.
- All 1,142 JavaScript regression checks passed.
- Browser check confirmed stale Alice/version 1 → cleared server/version 2 → Bob/version 3, exactly one write, matching displayed/cache/server assignment and no pending request.
- Regression coverage includes stale reset state, competing assignments, duplicate taps, conflict retries, timeouts, readback failures and session changes.
- The staging browser session available for testing was signed out; authenticated UI verification used an isolated synthetic fixture with the production save functions and reference service.

Deployment assets use bay-assignment=2026.09.17.01. Refresh the existing staging page to load the update.
