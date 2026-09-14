# Mobile QC Sublet completion

Published scope: staging only, 14 September 2026.

## Fault and resulting behavior

The completion ledger allowed only the seven physical workshop stages. A Sublet tick therefore failed even with a zero-hour estimate. Separate client and database checks also treated a missing Sublet estimate as an unresolved workshop estimate.

Sublet is now an allowed completion stage. Its inspector checks can be saved and cleared with zero or absent hours, and each operation retains its own identity and saved receipt. The same Sublet-only hours exemption applies to department completion, QC finalization, retest, rework readiness and downstream transport eligibility. Physical workshop items still require known hours; unmapped items remain blocked.

The migration changes no vehicle, operation, estimate, booking, photo or saved inspection tick. Existing authorization, version conflicts, idempotent receipts, incomplete-item checks and photo requirements remain. The separate unused legacy individual-operation rejection endpoint is outside this change; the current mobile rejection flow uses the existing whole-vehicle rejection service.

## Verification

- 597 frontend regression checks passed, including six new tests executing the real mapper, shared handlers and mobile module.
- 24 database integration assertions passed against the installed staging migration in a transaction that was rolled back. Covered null and zero hours, distinct operations with duplicate descriptions, tick/clear/recheck, department completion, stale versions, retries, access checks, unmapped and unknown-workshop-hour blocks, mandatory photo, incomplete Sublet sign-off rejection, successful QC-to-RFT sign-off, and unchanged existing records.
- At a 390 px phone viewport, a synthetic local fixture using the actual mobile module and shared handlers saved and cleared Sublet checks, completed a mixed checklist, required a photo, and reached finalization after a synthetic saved photo. External writes were blocked in the fixture.
- Existing customer QC checks, photos and bookings were retained. No customer operation was ticked or signed off during verification.
- Cache markers updated for the application, canonical loader and mobile module so a fresh page loads the fix.

Database migration: `20260914062014_mobile_qc_sublet_without_hours`.
Regression: `test_qc_sublet_completion_20260914.js`.
Rollback integration test: `tests/mobile_qc_sublet_rollback.sql`.
