# Autonomous Website Changes

## 2026-08-26 — Repair recurring synthetic containment drift after ordinary Workshop reads

- Added staging-only migration `supabase/staging_only/20260826215000_436_current_containment_read_repair.sql` and regression `test_staging_containment_drift_repair_436.js`.
- Preserved the immutable 432 baseline as evidence while rebinding read containment to the current staging/registry/mailbox/Monitor/outbound-delivery guards, so ordinary mutable Workshop state cannot make read-only synthetic inventory unavailable.
- Rebound the acceptance create/lifecycle effective function definitions to compare exact protected, notification and outbound state before versus after; retained authenticated-only ACLs, replay/stale protections, synthetic identity and absent-Production-sentinel guards. Production, real vehicles/bookings/users, mailbox runtime, sent/delivered delivery and production data remain untouched.
- Added append-only migration `supabase/staging_only/20260826220000_437_registered_replay_containment_repair.sql` so registered synthetic replays remain safe after ordinary mutable staging changes instead of comparing current state with an obsolete receipt snapshot. The replay remains identity-, registry-, ACL- and containment-bound; no write or delivery path was relaxed.
- Added append-only migration `supabase/staging_only/20260826221000_438_acceptance_stale_fast_path.sql` after the live stale-version probe showed the lifecycle path could spend its full timeout in containment locking before rejecting an already-stale registered synthetic request. The early check is only an additional fast rejection; the locked path remains authoritative and all normal writes retain exact protected/notification/outbound before-vs-after checks.
- Added append-only migrations `supabase/staging_only/20260826222000_439_acceptance_stale_before_binding.sql` and `supabase/staging_only/20260826223000_440_acceptance_stale_nonretryable.sql` after the first fast path still allowed the PostgREST serialization-failure retry behavior to mask the stale response. The authenticated pre-binding branch now rejects before binding/idempotency/containment work with stable `PDC_375_LIFECYCLE_VERSION_CONFLICT` / SQLSTATE `P0001`; the locked authoritative stale check remains SQLSTATE `40001`. Registered create replay and stale probes preserved the protected digest and notification/outbound state, with sent/delivered outbound remaining zero.

## 2026-08-26 — Receipt-backed QC photo finalization and canonical Sublet provider writes

- Added candidate staging-only migration `supabase/staging_only/20260826140000_399_qc_finalization_photo_rft_salesperson_outbox.sql`. It adds private compressed photo evidence receipts, authenticated storage ownership checks, exact active QC-line snapshots, named QC sign-off, atomic QC-to-RFT movement/date milestone, immutable exact salesperson outbox payload, no-dispatch/sent/delivered containment, replay/version conflict handling, readback, and an exact booking UUID/version provider-reassignment RPC with idempotent receipts.
- Updated `app.js`, `pdc-email-vehicle-location-service.js`, `styles.css` and `index.html`: QC uploads only a canvas-compressed auto-oriented image (1600px max, target <=750KB, hard <=1MB), records the receipt before finalization, supports vehicles already QC-completed but still at QC, reports `Signed off and moved to RFT`, routes canonical Sublet provider changes by booking UUID/version, fails closed for zero/multiple canonical rows, and prevents background Sublet native selects painting through the vehicle modal.
- Added/updated focused contract tests for QC finalization/photo compression, QC page behaviour, canonical Sublet provider mutations, modal stacking, and the changed cache-busted release metadata. All local `node test_*.js` tests pass. Staging database application is pending the authorised Main Supabase connector; no protected vehicles, production, mailbox runtime or real notification was changed.

## 2026-08-25 — Fail-closed Vehicle identity and Workshop line projection

- Bound open Vehicle modals to the exact canonical UUID plus displayed Stock baseline across delayed refresh/realtime reorder; conflicting, missing or unresolved identities now render read-only and cannot invoke a mutation RPC. `app.js` no longer resets the active modal to the first refreshed row.
- Updated `vehicleWorkshopGroups` to retain every authoritative Job Card/operation line, including explicit `0.00` hours, preserve OP17 evidence and represent Parts/Pit lines, while moving adjusted lines into their authoritative station without generic fallback replacement.
- Workshop shared booking duration now ignores stale/user-derived hours and uses the exact whole-minute adjusted operation projection (including the 516-minute Fitting case). Added `test_identity_zero_hours_booking_duration.js`; production remains untouched.


## 2026-08-25 — Canonical Workshop booking snapshot authority

- Added staging-only migration `supabase/staging_only/20260826130000_397_canonical_workshop_booking_snapshot_authority.sql`, guarded after the exact live 20260826124500 final owner-document constraint-correction head (preserving both prior 396 corrections). Both station and full Workshop snapshots now overlay scheduling, status, version, actual and stoppage fields from `workshop_bookings` by stable booking UUID, without rewriting canonical rows or moving active bookings.
- Added `test_workshop_canonical_booking_snapshot_authority_397.js` covering the protected Stock 13000549 read-only geometry evidence, synthetic HERMES-TEST acceptance contracts for fixed overlap/nearest free slot, receipt/replay/undo, planned-only cascade/resize, bay locking and zero notifications, plus stale-estimate chip regression.
- Production, production branches/data, mailbox runtime and credentials remain untouched.

## 2026-08-25 — Owner-supplied Job Card intake authority

- Added staging-only migration `supabase/staging_only/20260826120000_396_owner_supplied_document_jobcard_intake.sql` and regression `test_owner_supplied_document_jobcard_396.js`.
- The additive contract accepts only Craig's exact owner instruction/task reference and Stock 13080553 / JC J139125519, labels provenance `owner_supplied_document`, binds immutable PDF hash/byte metadata to one current Navision identity, and writes receipt-backed canonical operation evidence without provider-email, mailbox, booking, movement, completion or notification authority.
- Explicit zero hours remain numeric `0`; unknown hours remain `NULL` with durable review rows. Immutable receipts, source-row fingerprints, audit, idempotency/conflict handling and owner-scoped undo are included. Production and mailbox runtime remain untouched; live staging application still requires the approved temporary Importer writer activation.

## 2026-08-25 — Receipt-first salesperson readback race repair

- Updated `app.js` so accepted salesperson/detail receipts apply immediately to the one canonical stable UUID/version in memory, while a bounded targeted snapshot readback reconciles stale, delayed and contradictory projections independently of broad-refresh generation races.
- Broad refresh supersession no longer converts a validated write into `salesperson_assignment_readback_failed`; delayed readback is shown as `Saved online; refreshing…`, exact contradictory readback fails closed, and subsequent detail saves use the salesperson receipt's `vehicle_version_after`.
- Added `test_salesperson_readback_race.js` covering stale/eventual/immediate/contradictory snapshots, poisoned local state, replay-shaped receipts, combined detail save versioning, and broad-refresh generation race behavior. No browser-local persistence was added.

## 2026-08-25 — Restore Mobile QC operation-line projection

- Added staging-only migration `supabase/staging_only/20260826110000_395_restore_qc_operation_projection.sql`, an additive wrapper over the live snapshot that preserves all existing fields while projecting canonical `pdc_qc_operation_lines_379` output as `qc_operation_lines` for every returned vehicle. The migration is guarded to the exact staging sentinel/head, production exclusion, protected digest and zero-notification postconditions.
- Updated `pdc-email-vehicle-location-service.js` to distinguish an absent/malformed server QC projection from a valid empty array, and updated `app.js` to show a precise server-projection loading message without claiming source operation evidence is absent. Cache-busted staging asset references in `index.html` and updated focused regression coverage.
- The source release is staging-only. Protected Stock `12664962` remains read-only; no production data, branch, migration, credentials or notification rows were changed.

## 2026-08-25 — Focused booking and future-only Workshop corrections

- Vehicle-card booking links now enter a focused, scoped canonical booking mode. Exact booking ID resolution fails closed on missing/ambiguous rows, displays authoritative operation lines and exact whole-minute totals, removes legacy duration buttons, supports receipt/version-safe Save plan edits, hides candidate noise, and provides Back to Workshop planner.
- Workshop planner projections now consume authoritative source-line stage adjustments in shared mode and never use browser-local line assignments; moved source lines follow their canonical target station and exact hours.
- Outstanding pills now use canonical vehicle description, station-only exact authenticated minutes, explicit zero/unknown hours, no Requirements line, and focused Parts navigation uses the exact selected stock.
- Shared vehicle detail lifecycle/stoppage guard compares only against the rendered raw baseline, preserving the exact dedicated-action error while allowing unrelated salesperson/detail saves.
- Added staging-only migration `supabase/staging_only/20260826093000_393_future_only_workshop_recovery.sql` for future-only planned scheduling, overdue recovery, idempotent recovery receipts, history/version preservation, and a staging rollback switch with zero notifications.
- Added staging-only migration `supabase/staging_only/20260826100000_394_admin_compaction_and_duration_bounds.sql` for exact multi-day Admin operational durations and atomic now-forward compaction after shortening/deletion, preserving fixed/live/history rows and receipts.
- Shared detail Save now treats raw rendered lifecycle/work baselines as the only editable comparison; derived Parts/STOPPAGE projections cannot block unrelated salesperson assignment. Parts navigation focuses the exact selected stock and preserves authoritative ordered projection.

## 2026-08-25 — Atomic Admin block insertion and cascade

- Added staging-only migration `supabase/staging_only/20260826090000_392_workshop_admin_block_atomic_cascade.sql` for drop-time bay/revision locking, idempotent Admin insertion, exact operational-minute cascading of planned vehicle and Admin rows, fixed/live blocker details with nearest available slot, immutable receipt/history, one revision bump and zero notification delta.
- Updated `workshop-planner.js`, `workshop-shared-actions.js` and `workshop-planner.css` so Admin drops send a request id, show pending state, and render a placed/cascaded or blocker/nearest-slot summary without a blocking failure alert.
- Added `test_admin_block_atomic_cascade.js` covering the migration/UI/bridge contract. Production data, branches and credentials remain untouched.

## 2026-08-25 — Authoritative Vehicle detail saves

- Routed shared Vehicle Locations salesperson assignment through `assign_pdc_vehicle_salesperson_386`, with approved active-code validation, exact UUID/version/operator checks, idempotent SHA-256 receipts, immutable history/audit, manual Navision override preservation, revision publication and zero notification delta.
- Added `update_pdc_vehicle_detail_fields_388` for allowlisted canonical `client_name`, PMB-only unique `key_number`, and `job_card_number` changes with bounded normalization, stale/replay handling, immutable before/after history, and no browser-local fallback.
- Updated the Vehicle detail Save flow and snapshot mapper to use authoritative RPC receipts, per-save Saving/Saved/Error status, exact read-back, poisoned consultant-edit cleanup, and no localStorage writes for shared salesperson/detail fields. Lifecycle/location and stoppage actions remain on their dedicated shared contracts.
- Added staging-only migrations 386–391 for the contract, registry-bound HERMES-TEST routing, detail snapshot identity convergence, and stale-receipt repair; live synthetic assignment/clear and detail assign/replay/stale/restore probes passed without changing protected vehicles or notification count.
- No production data, branch, migration or remote was accessed or changed.

## 2026-08-25 — Parts ordered authority closure

- Changed `app.js` so shared authoritative Parts rows use canonical `pdcRequiresParts`; a display stock/batch number cannot project `Not Ordered` or enable ordering when canonical `parts_required` is false.
- Added operator/admin-only Parts controls with visible `Operator access required` messaging for viewer rows, and replaced Parts mutation error alerts with inline status messages for missing requirement, ETA, permission, stale-version, duplicate, schema and receipt outcomes.
- Added `pdc-email-vehicle-location-service.js` response-code normalization for the 377 error family.
- Added staging-only migration `supabase/staging_only/20260825220000_385_parts_order_authority.sql`, which preserves the existing 377 RPC contract while adding the canonical `parts_required=true` trigger guard before ordered writes.
- Added `test_parts_order_authority_377.js` and updated the Parts button contract test.
- No production data, branch, migration or remote was accessed or changed.
