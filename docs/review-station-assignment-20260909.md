# Review operation station assignment — STAGING, 9 September 2026

Craig requested the ability to move Review operation lines into actual stations so they can be inspected in QC.

## Diagnosis
The existing station-move action recognised authenticated-email operations only, not retained Pilbara Job Card lines. It also required both the source and destination departments to be incomplete, which made Review lines and vehicles already in QC uneditable. Stock 13056938's Snake Bite Kit was a concrete Review case with an explicit 0.00-hour source estimate.

## Change
- Add a Choose station / Save station control beside each active unchecked Review source line on the phone and desktop QC screen, and a Review — assign stations panel in the vehicle Work tab.
- Supported choices: Fitting, Electrical, Fabrication, Hoist, Tint, Tyre, Bus 4x4 and Sublet. Parts/Pit are not offered as shortcuts around the inspection gate.
- Extend the existing `move_vehicle_workshop_source_line_stage` RPC in place. Resolve exactly one vehicle-bound authenticated-email or Pilbara source, preserve operation identity, description and all source hours, and save an audited locked manual station assignment. No replacement import or new write endpoint.
- Only Review resolution relaxes the previous department-availability gate. Already QC-completed operations remain protected. Approved Operator/Administrator subject and email, adjustment version and exact source checks are retained. A stale repeat is rejected rather than creating a duplicate.
- The shared operation snapshot overlays the saved station and retains the original work key separately. The workshop and QC use the same canonical adjustment. No QC checkbox, physical location, photo or sign-off is manufactured by an assignment.
- An unknown estimate remains unknown; assigning a station alone does not resolve missing hours. Explicit zero stays zero and can be inspected.

## Included pending QC-rework release
This release includes the already-prepared, approved QC-rework commit `fca57e8552344743eb8e644c0d4342bdc5085fa2`, which had not yet reached main. Its source and previously applied migrations are retained. Rejected-item-only booking estimates and Return to QC after completed repairs are exposed, with fresh checklist/photo-attempt handling. During combined browser testing, a lazy-loading defect was corrected: planner-only hooks now wait for `workshop-planner.js` instead of throwing when the phone opens QC first.

## Verification performed
- Actual STAGING station-move RPC exercised for all eight choices against the reported explicit-zero Review line, each in a rolled-back subtransaction. Source identity, 0.00 hours, unchanged description/unchecked state and matching Board/QC station readback passed.
- Actual QC checkbox RPC accepted the mapped line with `completed=false`; no physical completion was asserted. Stale repeat and unassigned identity were denied; deferred constraints were checked. All test effects were rolled back, with vehicle, work-item and raw source hashes unchanged.
- Nine new Node regressions passed. The deployed-base suite plus these tests passed 243/243 locally; the final PR also includes the pending rework tests and must pass exact-head CI before merge.
- In-memory Chromium at 390px and 1440px verified explicit station selection/save, matching readback, QC enabled but still unchecked, failure remaining in Review, and Work-tab controls without an unfinished destination requirement. The real source mapper/renderers were used; backend responses were simulated and external networking blocked. This is not a claim of authenticated physical-phone testing.
- Applied migration: `20260909090605_review_operation_station_assignment_20260909.sql`; stored SQL SHA-256 `7fccd56326d326f9fef49a8d14692a6f744bccb89cbf2ac2e651676895a37fa2`.

Stock 13056938 was left for Craig to choose the station himself. No customer source, hours, physical completion, location, email, credential, scheduler or Production state was changed by the implementation or retained test effects. Refresh STAGING before using the new controls.

## Rollback
Revert the frontend release to remove the new controls. Preserve all original source rows, manual assignment history and existing photo-attempt evidence. If a database correction becomes necessary after use, apply a reviewed forward migration; do not delete evidence or replay old migrations.
