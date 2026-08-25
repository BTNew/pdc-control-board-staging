# Autonomous Website Changes

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
