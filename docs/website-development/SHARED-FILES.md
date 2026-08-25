# Shared Files

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
