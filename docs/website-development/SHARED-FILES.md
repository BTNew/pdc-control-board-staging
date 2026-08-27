# Shared Files

## Parts Received canonical Navision identity repair — 2026-08-27

- `app.js` — shared Navision projection now retains the linked canonical vehicle UUID for Parts actions.
- `vehicle-lifecycle-actions.js` — lifecycle identity resolution accepts the shared Navision canonical UUID.
- `index.html`, `pdc-supabase-config.staging.js` — cache-busted changed app/config and lazy resolver assets.
- `test_parts_received_shared_identity.js` — canonical/Navision/email Parts Received identity and payload regression coverage.

## Synthetic containment drift repair — 2026-08-26

- `supabase/staging_only/20260826215000_436_current_containment_read_repair.sql` — append-only staging contract repair for current read containment and exact protected/notification/outbound synthetic write postconditions.
- `supabase/staging_only/20260826220000_437_registered_replay_containment_repair.sql` — append-only registered synthetic replay repair that removes the stale receipt-vs-current protected-state comparison while retaining current containment and exact write postconditions.
- `supabase/staging_only/20260826221000_438_acceptance_stale_fast_path.sql` — append-only registered acceptance stale-version fast rejection before the expensive containment lock path; normal writes retain exact protected/notification/outbound postconditions.
- `supabase/staging_only/20260826222000_439_acceptance_stale_before_binding.sql` — append-only stale-version rejection before registry binding/idempotency/containment work.
- `supabase/staging_only/20260826223000_440_acceptance_stale_nonretryable.sql` — append-only non-retryable SQLSTATE repair for the pre-binding stale branch; the locked authoritative concurrency check remains SQLSTATE 40001.
- `test_staging_containment_drift_repair_436.js` — migration, effective-function repair and protected-boundary regression coverage.
- `test_registered_replay_containment_repair_437.js` — registered replay containment and protected-boundary regression coverage.
- `test_acceptance_stale_fast_path_438.js`, `test_acceptance_stale_before_binding_439.js`, `test_acceptance_stale_nonretryable_440.js` — stale rejection ordering, non-retryable error, containment, ACL and protected-boundary regression coverage.
- `deployment-identity.json` — exact 440 staging migration provenance.

## Receipt-backed QC photo finalization and canonical Sublet provider writes — 2026-08-26

- `app.js` — QC receipt-backed photo upload/finalization flow, already-QC-completed-at-QC support, legacy QC action replacement, canonical Sublet booking identity routing, and modal open/close interaction hooks.
- `pdc-email-vehicle-location-service.js` — compressed photo upload/storage receipt client, atomic finalization client, QC finalization projection mapper, and exact booking UUID/version provider-reassignment client.
- `styles.css` — top vehicle-modal stacking context and temporary background Sublet native-select suppression while the modal is open.
- `index.html`, `deployment-identity.json` — cache-busted staging asset release identity and uncommissioned 399 migration provenance.
- `supabase/staging_only/20260826140000_399_qc_finalization_photo_rft_salesperson_outbox.sql` — additive staging candidate migration for private photo evidence, atomic QC/RFT/outbox receipts and canonical Sublet provider updates.
- `test_qc_finalization_399.js`, `test_sublet_canonical_provider_mutation_399.js`, `test_sublet_modal_layering.js`, plus updated QC contract tests — focused regression coverage.

## Canonical Workshop booking snapshot authority — 2026-08-25

- `supabase/staging_only/20260826130000_397_canonical_workshop_booking_snapshot_authority.sql` — exact-head-guarded staging-only projection wrapper overlaying canonical booking scheduling/live fields by stable UUID while preserving snapshot shape and mutation authority.
- `test_workshop_canonical_booking_snapshot_authority_397.js` — canonical geometry, protected read-only evidence, synthetic acceptance, fixed overlap/nearest slot, receipt/replay/undo, cascade/resize, bay isolation and zero-notification regression coverage.

## Owner-supplied Job Card intake authority — 2026-08-25

- `supabase/staging_only/20260826120000_396_owner_supplied_document_jobcard_intake.sql` — additive staging-only exact-owner/Task/Stock/Job Card contract, immutable document and operation evidence, unknown-hour review rows, idempotency, audit and undo RPCs; no provider-email or mailbox dependency.
- `test_owner_supplied_document_jobcard_396.js` — exact provenance, identity, 18-row 14-explicit/4-unknown hour model, zero-vs-null, ACL, forged-email rejection, side-effect and undo contract coverage.

## Receipt-first salesperson readback race repair — 2026-08-25

- `app.js` — receipt-first canonical UUID/version application, in-memory pending receipt overlay, bounded targeted authoritative readback, contradiction handling, and delayed-save status.
- `test_salesperson_readback_race.js` — focused receipt/readback race, stale/eventual/immediate/contradictory snapshot, poisoned-state, replay and combined-save regression coverage.

## Restore Mobile QC operation-line projection — 2026-08-25

- `app.js` — QC operation-line rendering now distinguishes a missing server projection and shows a precise loading message.
- `pdc-email-vehicle-location-service.js` — QC snapshot mapper preserves a projection-presence signal while remaining fail-closed on missing data.
- `index.html` — cache-busted staging references for the QC projection asset release.
- `supabase/staging_only/20260826110000_395_restore_qc_operation_projection.sql` — additive, exact-head-guarded snapshot wrapper preserving the existing contract and canonical QC 379 lines.
- `test_qc_operation_projection_395.js`, `test_qc_operation_completion_379.js` — migration and missing-projection regression coverage.

## Focused booking and future-only Workshop corrections — 2026-08-25

- `app.js` — focused vehicle-card booking entry, canonical Parts projection/focus, and raw-baseline lifecycle guard for shared detail saves.
- `workshop-planner.js` — focused canonical booking mode, exact operation-line display, source-line adjustment projection, no local shared assignments, and exact candidate pill model/hours.
- `workshop-data-service.js` — authoritative future-only recovery before trusted snapshots.
- `workshop-planner.css` — focused booking operation/error layout.
- `supabase/staging_only/20260826093000_393_future_only_workshop_recovery.sql` — staging-only future scheduling enforcement and recovery.
- `supabase/staging_only/20260826100000_394_admin_compaction_and_duration_bounds.sql` — staging-only exact multi-day Admin duration and now-forward compaction correction.
- `test_workshop_focused_booking.js`, `test_workshop_owner_corrections.js` — focused UI, projection, future-only and raw-baseline contract coverage.

## Atomic Admin block insertion and cascade — 2026-08-25

- `workshop-planner.js` — Admin drop request state, request-id dispatch, placed/cascaded summary, and fixed blocker/nearest-slot feedback.
- `workshop-shared-actions.js` — request-id metadata for the protected Admin creation RPC.
- `workshop-planner.css` — responsive pending/success/error feedback styling.
- `supabase/staging_only/20260826090000_392_workshop_admin_block_atomic_cascade.sql` — staging-only atomic cascade, idempotent receipt, fixed blocker/nearest-slot contract and revision publication.
- `test_admin_block_atomic_cascade.js` — migration, bridge and UI contract coverage.

## Authoritative Vehicle detail saves — 2026-08-25

- `app.js` — shared Vehicle detail Save orchestration, receipt-backed salesperson/detail RPC dispatch, authoritative reconciliation, and poisoned legacy consultant cleanup.
- `pdc-email-vehicle-location-service.js` — canonical snapshot mapping plus salesperson and allowlisted detail RPC clients.
- `index.html` — cache-busted staging asset references for the authoritative detail tranche.
- `supabase/staging_only/20260825230000_386_authoritative_salesperson_assignment.sql` through `20260825235000_391_detail_stale_receipt_repair.sql` — staging-only authoritative detail contracts, synthetic route containment, snapshot convergence, and stale receipt repair.
- `test_authoritative_salesperson_assignment_386.js`, `test_email_authoritative_board.js` — contract, RPC-body, and poisoned-local-storage negative coverage.

## Parts ordered authority closure — 2026-08-25

- `app.js` — shared Parts projection, queue rendering and mutation handlers; this change keeps canonical Parts requirement and viewer access fail-closed.
- `pdc-email-vehicle-location-service.js` — shared Parts RPC error normalization.
- `styles.css` — not changed by this task.
- `supabase/staging_only/20260825220000_385_parts_order_authority.sql` — append-only staging trigger correction for ordered Parts writes.
