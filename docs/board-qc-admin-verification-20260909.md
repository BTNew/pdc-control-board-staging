# QC, booked indicators and Admin scheduling — STAGING, 9 September 2026

## Scope and release
Craig requested multi-item QC rejection, repair-only hours, return to QC, orange booked indicators across departments, working Admin duration input/cascades, and a broader board check. This release builds on `47a1d2a182a726d64680e4c74c5f75e03a77edfa` (the exact-dealer Review-save repair) without replacing it.

### Corrections
1. **Explicit multiple QC defects:** phone Not fitted controls and desktop Select items / Reject QC open a selection panel. Users select all failed operations before one confirmation. A six-argument overload of the existing rejection RPC validates every identity/version and records the exact selected set atomically. An old five-argument wrapper remains compatible with existing callers. The new overload is not executable by anonymous users and still requires the approved Operator/Administrator role.
2. **Repair scope:** only explicitly selected lines and their unchanged source hours enter the rejection receipt. An uninspected but unselected line is not silently treated as rejected. A selected previously checked item is unchecked within the same transaction, with history. Existing rework calculations and Return to QC operate on that receipt. Reinspection resets all checks, not just the repaired ones. No physical work is automatically marked complete.
3. **Orange booked indicators:** an unloaded or differently scoped station planner previously supplied an empty active-booking array, masking the canonical bookings already returned on each vehicle. Vehicle Locations now projects department state from the authenticated vehicle's own booking list, and successful workshop actions refresh that shared vehicle snapshot. All seven physical departments are covered; cancellations return to required, stoppages remain distinct, and completed requirements remain green. End-date text uses authoritative booking end times across working days.
4. **Admin decimal hours:** the palette no longer rewrites the input on every keystroke. Decimal and multi-day values convert to working minutes on change/drop. Invalid/empty/zero values disable dragging instead of silently selecting the previous/default duration.
5. **Admin compaction:** the database cascade always applied changes backwards, causing a real bay-overlap failure when deleting a block and shifting jobs earlier. Rightward shifts now vacate from the back, leftward shifts from the front. A delete calendar preflight was also moved before the deletion update to prevent a failure response after a partial change.

## Actual verification
### Local source / browser
- Full final Node suite: **285 passed, 0 failed, 0 skipped**. This includes 12 new regressions and retains the existing QC rework, Review station, New Vehicles, Parts/Sublet/RFT and planner tests.
- Frontend secret scanner after staging all files: **52 tracked frontend files, zero findings**.
- In-memory Chromium with complete deployed app sources and actual handlers, but **simulated authentication and network responses**: Review selector/save at 390px and 1440px used exact dealer 37047, issued the typed station move and refreshed the result with 0.00 hours unchanged. No QC tick was invented.
- Phone and desktop multi-rejection controls selected two items, made zero writes before confirmation, issued one exact selected-item request, and removed the vehicle from the QC queue only after a successful receipt/readback.
- Fresh Vehicle Locations render without loading the planner projected the actual Fitting `is-booked` class and exclamation marker from the server booking shape. Pure state tests cover all seven physical departments.
- Actual lazy-loaded Admin palette typing: 0.25h = 15 minutes, 1.5h = 90, 2.75h = 165, and 15h = 900. Zero was rejected.
- Navigation smoke checks: Vehicle Locations, Control Board, Parts, Sublet, RFT, New Vehicles, QC and Admin opened without JavaScript errors. This is navigation coverage, not verification of every mutation button.

### Actual STAGING database functions, rollback-only fixtures
- Created three consecutive one-hour synthetic bookings through `schedule_vehicle_work` in an isolated future bay.
- Inserted a 90-minute Admin block between the first and second jobs: first job unchanged; second and third shifted later. Retrying the same create request reused its receipt, with no duplicate block.
- Resized Admin to 15 hours: exactly 900 operational minutes, and the following job moved correctly across working days. Shrinking to 30 minutes compacted the queue. Rename succeeded. Delete restored consecutive jobs without overlap after the directional fix. Deferred constraints were forced and passed.
- New selected-rejection RPC: two defects at 0.25h Fitting and 0.50h Electrical; unrelated accepted and uninspected work excluded. Selected previously checked item was unchecked with history; unselected passed item unchanged; retry reused the receipt.
- Return to QC was refused while repairs were incomplete. With repair completion represented on **synthetic fixture work items**, the actual QC-entry RPC cleared only the matching rejection stoppage and reset all four inspection items. This test did not claim a real technician started/completed a customer job.
- Empty, duplicate, stale and unknown selected lines were refused. Viewer rejection was refused. These denied requests left no rejection receipt or changed vehicle state.
- All temporary database test effects were rolled back. No customer vehicle was rejected, reassigned, moved, booked, completed or signed off by these tests.

## Applied migrations
- `20260909111609_qc_selected_item_rejection_20260909.sql`
  - Stored SQL SHA-256: `b307596dbeab37ae7695d9b00dc8af26a34ed6989b0ff858380b47b5c47d787b`
- `20260909112022_admin_cascade_direction_and_atomic_delete_20260909.sql`
  - Stored SQL SHA-256: `b2d5d547e71f8df40c3303f2ead814c340fd8a677f386e95f533ee859e981938`

Repository SQL bytes match the live migration ledger. Neither migration changes customer business records during application. Existing evidence and old receipts remain intact.

## Boundaries
This is **not** a claim that every button on every page is certified. An authenticated staff browser, actual iPhone photo upload, Outlook handoff, concurrent users, every Admin move/resize permutation, and recurring report ingestion were not end-to-end exercised here. Photo and RFT logic is retained, not bypassed. Production, mailbox, outbound email, runtime credentials and schedulers were unchanged.

Require exact-head GitHub checks before merge and verify Pages deployment before reporting publication. Revert presentation files to disable the new UI if necessary; retain all rejection receipts and migration history. A database correction after operational use must preserve the exact selected repair evidence.
