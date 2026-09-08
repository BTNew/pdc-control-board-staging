# t_780b25d4 — Job Card hours and Workshop detail repair

## Proved root causes

1. Stock 12705177 is dealer 37047 and its three Job Card rows come from `pdc_pilbara_service_operations`, not `pdc_authenticated_email_operation_lines`. The deployed batch RPC only resolved the latter table. The browser projected the Pilbara rows from the shared snapshot, but the save RPC could not resolve those submitted operation UUIDs, so an otherwise valid all-hours payload was rejected before authoritative persistence.
2. The deployed Workshop detail client always submitted the global configured dealer (14450) to the scoped detail RPC. For stock 12705177, the scoped RPC truthfully returned `vehicle_not_in_dealer_scope`; the client discarded that structured rejection and reported the misleading generic message `The shared Workshop response was incomplete.`
3. Numeric client validation converted text to `Number` before applying only range/precision checks. A strict lexical contract was missing, so non-advertised numeric forms could be accepted. Blank/null and exact zero also needed an explicit end-to-end distinction.
4. The inherited batch SQL inserted new adjustment rows but omitted an explicit update for already-existing adjustment IDs. A RED regression proved existing audited overrides could be silently omitted from a batch.
5. The new explicit unknown provenance initially projected `null`, but the line renderer could replace it with a single-line booking-duration fallback. Independent review caught this; a RED regression now proves an audited unknown remains blank.
6. Migration 20260904010100 had re-granted authenticated execution on the unscoped SECURITY DEFINER `get_vehicle_workshop_detail(uuid)` after the scoped-wrapper hardening. The repair seals that bypass and retains only the authenticated dealer-scoped wrapper.
7. The separate live Fitting planner regression was server-side and independent of the editor save path: `workshop_vehicle_stage_estimated_hours(uuid,text)` aggregated `pdc_authenticated_email_operation_lines`, manual overlays, and the isolated synthetic fixture, but not `pdc_pilbara_service_operations`. Stocks 12705177, 13007660, and 13015144 each had zero authenticated-email rows and 3, 2, and 4 classified Pilbara Fitting rows respectively, so the station snapshot received `null` hours despite authoritative positive source values.

## Repair

- The client derives the detail request dealer from confirmed vehicle/Navision authority and accepts only dealer 14450 or 37047.
- Structured scoped-RPC rejections remain truthful; a ready DTO requires matching vehicle ID plus arrays for requirements, bookings, and line adjustments.
- Job Card input uses a strict plain-decimal lexical grammar, accepts blank/null, exact zero, whole-hour forms, and up to two decimal places through 999.99, and rejects exponent/hex/nonfinite/negative/overprecision/out-of-range forms.
- Only rendered hour-bearing controls are serialized. Parts rows have no hours control and are excluded.
- Save-all is deduplicated while in flight; failure reloads authoritative state while preserving every draft.
- STAGING migration 20260908103000 resolves both authenticated-email and Pilbara Service operation UUIDs, validates the complete batch before DML, locks vehicle/adjustments, inserts or updates effective adjustment overlays, writes audit events and one idempotent receipt, and increments the vehicle version once. Immutable Pilbara raw/source hours, Parts, bookings, and completion remain untouched.
- A blank override is stored as `manual_operator_unknown`; projection and display preserve it as unknown instead of falling back to source or booking duration.
- Direct authenticated execution of the unscoped Workshop detail function is revoked. Authenticated access remains on the dealer-scoped wrapper and batch RPC; anon and service_role cannot execute either browser contract.
- STAGING migration 20260908150000 extends the internal planner aggregate to classified Pilbara Service rows. Active audited overlays replace source stage/effective hours (including explicit unknown), inactive source overlays remain explicit removals, and immutable source rows are not modified.

## Evidence

- Original STAGING source snapshot: `live-diagnostic.json` and `live-diagnostic-summary.txt`.
  - Stock 12705177 canonical vehicle: `a1b2ea79-1933-5453-81e3-b0b1945c94bf`.
  - Dealer: 37047; repair order: JC14123887.
  - Original immutable source hours: Fuel 0, Pre-Delivery 1.5, Side Steps 0.75.
  - Original effective adjustment rows and hours receipts: none.
- RED captures:
  - `red.txt`, `red-unknown-override.txt`, `red-existing-adjustment.txt`, `red-manual-unknown-display.txt`, `red-unscoped-detail-grant.txt`.
- GREEN/full suite: `full-suite.txt` records 195 tests passed, 0 failed.
- Migration rollback rehearsal: `migration-dry-run.json` proves before/after STAGING state equality.
- Migration application: `migration-apply.json` records head 20260908103000, function markers present, authenticated scoped/batch execute true, unscoped authenticated execute false, anon/service execute false, Production sentinel absent, and `production_contacted=false`.
- Independent pre-commit review: PASS after the existing-adjustment, manual-unknown fallback, and unscoped detail grants were corrected.
- Fresh live Fitting evidence: `fitting-hours-gap-live.json` proves the three reported stocks use only Pilbara operation rows; `red-pilbara-fitting-stage-hours.txt` records the RED regression; `fitting-hours-migration-dry-run.json` and `fitting-hours-migration-apply.json` prove guarded STAGING-only apply, unchanged vehicle/source/adjustment/booking business state, migration head 20260908150000, and live Fitting projections 2.25h, 1.5h, and 2.83h respectively. The post-change full suite is 196/196 in `full-suite-after-fitting-projection.txt`.

Signed-in deployed UI mutation/read-back/restoration, deployed SHA, asset equality, and GitHub Actions run IDs are recorded in the final Kanban handoff and its attached post-deployment evidence.
