# Review station save repair — STAGING, 9 September 2026

## Reproduced defect
The original Review controls existed, but their save path loaded workshop detail using the site's default Broome dealer 14450 when an authoritative email/QC vehicle DTO had no dealer field. For Pilbara Stock 13056938 (Snake Bite Kit), the correct scope is 37047. The scoped server correctly denied the wrong-dealer request; the frontend incorrectly presented the resulting null detail as an operation changed in another session. Earlier mocked tests did not exercise this real loader path.

The deployed-source browser reproduction clicked the existing selector and Save button, observed `get_vehicle_workshop_detail_scoped` with 14450, and never reached the station-move action. A separate database-role check reproduced the denial and proved that exact scope 37047 works.

## Change
- Update the existing Review module, not a new runtime. The real workshop-detail loader now resolves authoritative vehicle scope from supported explicit metadata or an exact canonical UUID + Stock in current authenticated Navision rows / bound modal identity. Missing or conflicting scope never borrows the configured default dealer. A missing local feed gets one read-only refresh.
- Put Choose station / Save station directly beside Review operations inside expanded Vehicle Locations rows. Retain QC and vehicle Work-tab controls. Display matching is not write authority: every request uses the exact canonical source UUID; duplicate visual labels use separately identified controls.
- Separate dealer/detail-loading failures from actual stale-version errors. Preserve user choices after a failed save.
- Bump Review JS/CSS version to 2026.09.09.12. Existing phone QC, New Vehicles, RFT and rework loaders are retained.

No database function, permission, source hours, completed work, booking, vehicle location or photo is modified by this release. No new migration is needed.

## Verification
- Final local Node suite: 273 passed, 0 failed, 0 skipped. Nine new regressions include the original default-dealer reproduction, both supported dealer codes, ambiguous/wrong/retired identities, exact modal binding and the actual asynchronous detail loader.
- Four in-memory Chromium interaction paths passed: desktop Work modal, expanded Vehicle Locations, desktop QC and 390px phone QC. Each used actual deployed app functions and click/change handlers. The save requested dealer 37047, then one typed station move, then authoritative snapshot readback. Result: Fitting, explicit 0.00 hours retained, QC still unchecked; no JavaScript errors. Auth/session and network responses were simulated, not an authenticated staff browser or physical phone.
- Actual STAGING database-role test exercised the existing scoped-detail and station-move functions on the reported line inside a rollback-only transaction. The snapshot verified correct station, original hours, unchecked state and unchanged PMB location. Deferred integrity constraints passed. Vehicle, adjustment and work-item hashes were identical after rollback; the customer item remains Review for its operator to choose.
- This repair does not assert that an accessory has been fitted or complete QC. No mailbox, outbound email, credentials, schedulers or Production were changed.

Require exact-head repository checks before merge and verify the Pages deployment before reporting publication. Reverting these frontend files restores the prior presentation without discarding any server history.
