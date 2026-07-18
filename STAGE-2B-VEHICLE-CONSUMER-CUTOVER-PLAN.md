# Stage 2B vehicle-consumer cutover plan

Baseline: `feature/stage2b-shared-vehicle-master` at reviewed commit `7404fb00aa2d5a12b9776814abe60cb3f47827b2` plus the companion `STAGE-2B-VEHICLE-CONSUMER-INVENTORY.md`.

This plan does not execute a consumer cutover. Migration `029` establishes protected write contracts only. Existing direct reads, browser-local records and operational authorities remain unchanged until their individual proof gates are approved.

## 1. Sanitized core snapshot contract

RPC: `public.get_vehicle_core_snapshot()` (migration `028`).

### Response envelope

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "revision": 1,
    "caller_role": "viewer|operator|importer|administrator",
    "capabilities": {
      "can_edit": false,
      "can_import": false,
      "can_administer": false
    },
    "vehicles": []
  }
}
```

### Allowlisted vehicle fields

`id`, `permanent_vehicle_id`, `stock_number`, `vin`, `toyota_order_number`, `job_card_number`, `key_number`, `customer_name`, `vehicle_description`, `salesperson_id`, `salesperson_reference`, `make`, `model`, `registration`, `eta_to_kewdale`, `arrival_reference_date`, `source_system`, `source_batch_id`, `source_record_id`, `version`, `created_at`, `updated_at`, and derived `is_archived`.

### Explicit exclusions

The contract does **not** return:

- legacy `source_payload` or raw `vehicle_master_source_records` evidence/metadata;
- deletion timestamp/reason;
- actor UUIDs or emails;
- lifecycle, QC/RFT, PMB, bay, workshop, Parts or active-booking fields;
- aliases, identity-conflict evidence, history, audit events, AI analysis or review data;
- notification recipients or email bodies.

Purpose-built operational RPCs continue supplying their own minimum projections. The core snapshot is not a universal replacement for workshop, lifecycle or vehicle-intelligence contracts.

### Consistency and cache rules

- `vehicle_master_revision.revision` is the race token for the whole core snapshot.
- A consumer commits the returned vehicle array and revision atomically.
- Realtime events are invalidation hints only. Consumers refetch the full RPC and never reconstruct authority from row event payloads.
- Reconnect, token refresh and return-to-visible must trigger a refetch.
- An unavailable snapshot is read-only/offline; it must never cause fallback writes to browser-local state when shared mode is active.

## 2. Transitional authenticated table-level SELECT

Migration `028` deliberately retains:

- `SELECT` on `public.vehicles` and `public.vehicle_aliases` for `authenticated`;
- viewer-gated RLS policies;
- no browser `INSERT`, `UPDATE`, `DELETE` or `TRUNCATE` grants on vehicle-master tables.

This transitional read surface remains unchanged through migration `029`. It exists only for known legacy consumers and rollback. It must not be used by new code.

Retirement requires all of the following:

1. `app.js::vehicleLifecycleSharedRef` no longer calls `/rest/v1/vehicles`.
2. `scripts/workshop_legacy_import.py::fetch_reference_data` no longer directly selects vehicle identity, or is formally classified as an approved privileged offline tool with a non-browser database role.
3. No active frontend bundle contains `.from('vehicles')`, `/rest/v1/vehicles`, or an equivalent PostgREST query.
4. No backend application role requires table-level read; backup/restore uses a privileged non-browser role and is not evidence for retaining authenticated SELECT.
5. Database/API access-log review over an agreed observation window shows no authenticated direct vehicle/alias reads outside approved test identities.
6. Snapshot, lifecycle, workshop and intelligence role matrices pass through PostgREST.
7. Realtime revision/refetch works in two independent browser sessions, including disconnect/reconnect.
8. A tested rollback migration restoring the policies/grants is ready before revocation.

## 3. Ordered consumer migration

### C0 — protected write foundation (migration 029; current stop point)

- Add deterministic preview/apply/idempotent-upsert/manual-edit RPCs.
- Add an idempotency receipt table with no direct authenticated access.
- Reuse migration 028 normalization and candidate rules.
- Do not change frontend code, localStorage, existing direct SELECT, Realtime subscribers or production.

**RLS/RPC:** preview/apply/upsert require importer; manual edit requires operator; administrator inherits. Viewer and unapproved users cannot execute mutation RPCs. Internal helpers and receipt/evidence tables receive no browser grants.

**Proof:** credential-free contract tests, guarded staging role matrix, stale preview test, repeated-apply test, ambiguity/conflict tests, source/audit/history evidence, encrypted backup/restore, fixture cleanup.

**Rollback:** migration remains additive. Before consumer use, rollback is disabling/revoking 029 RPC execution and leaving 028/read paths intact; do not delete audit/source evidence created by legitimate calls.

### C1 — lifecycle identity resolver first

Replace `app.js::vehicleLifecycleSharedRef` direct `vehicles?...limit=1` with a protected deterministic resolver or cached core snapshot lookup plus a narrow lifecycle-state RPC. It must evaluate all normalized candidates and fail closed.

**Why first:** it is the identified active direct frontend table read and currently uses first-row semantics.

**RLS/RPC:** add a viewer-readable allowlisted lifecycle lookup if needed; never add QC/lifecycle fields to the core snapshot merely for convenience. Keep existing lifecycle mutation RPC grants.

**Proof before switch:** zero/one/many/conflicting identifier browser tests, UUID/version retention, viewer read/operator mutation role matrix, stale version rejection, no local edit on failure, two-session refresh.

**Rollback:** feature flag back to the transitional direct resolver while SELECT remains; no data copy or localStorage rewrite.

### C2 — workshop identity alignment and offline tools

- Keep `get_workshop_snapshot` for bookings/workshop state.
- Make overlapping core identity fields conform exactly to the core contract and normalization rules.
- Update `workshop_legacy_import.py`/validators to consume an exported snapshot or shared deterministic resolver and reject ambiguous normalized identities.
- Inventory every active caller of the lower-level authenticated booking RPCs. Retire those grants only after transactional wrappers cover the callers and prove identical vehicle-pointer/status/revision/audit behavior.
- Add a health check that `vehicles.active_workshop_booking_id`, when present, points to a booking for the same vehicle.
- Keep workshop and vehicle-master revision subscriptions independent.

**RLS/RPC:** no broader table grants. If an offline export RPC is needed, expose only `id`, identities and archived flag to importer/admin.

**Proof:** adapter UUID preservation, duplicate/conflicting identity failures, reconnect resync, workshop mutation expected-version tests, dry-run import report, zero writes for unsafe buckets.

**Rollback:** disable workshop shared mode or use the last approved tool version; unchanged legacy planner/local data remains available.

### C3 — reviewed synthetic import/reconciliation pilot

- Map Navision/CSV/email proposals to 029 preview.
- Preview captures current version and an immutable request fingerprint.
- A human approves only synthetic records at this stage.
- Apply sends the exact previewed payload/version/idempotency key.
- PO, Autocare, workshop and AI child data are excluded unless separately mapped and approved.

**RLS/RPC:** importer can preview/apply; operator can manual-edit; viewers remain read-only. Raw source evidence is never granted directly.

**Proof:** preview/apply parity, repeated apply identical response/no extra version bump, stale preview loses, conflict evidence, source evidence retention, safe retry after response loss, synthetic cleanup.

**Rollback:** stop calls; retain receipts/source/audit/history. No real vehicle or browser-local record is deleted or rewritten.

### C4 — main-board read authority switch

Only after an approved field map and reconciliation report:

1. Load core snapshot into a separate shared cache keyed by UUID.
2. Render a comparison mode without changing authority.
3. Prove row counts, identity mapping, null semantics, archived handling and operational child joins.
4. Switch one read-only screen first.
5. Switch main-board core identity reads; keep operational domains on their existing contracts until each has a protected API.
6. Disable local writes per domain only after the corresponding protected write path is proven.

**RLS/RPC:** add only narrow operational projections/mutations. Never broaden the core snapshot with raw payload or audit fields.

**Proof:** signed reconciliation report with every local record classified; two-browser consistency; offline/read-only behavior; no fallback local writes; tested rollback flag; verified browser backup retained.

**Rollback:** flip authority flag to the unchanged local/static dataset and restore the pre-switch browser backup. Shared DB rows remain as auditable records; never auto-reverse them from stale local data.

### C5 — retire broad direct SELECT

After the retirement prerequisites and observation window:

- revoke authenticated `SELECT` from `vehicles` and `vehicle_aliases`;
- drop/replace viewer table SELECT policies if no Realtime authorization dependency remains;
- retain RLS and no-direct-write posture;
- keep service-role/postgres backup/restore access;
- consider removing `vehicles`/`vehicle_aliases` from Realtime only after proving no subscriber uses them; retain `vehicle_master_revision`.

This must be a separate reviewed migration, not part of 029.

## 4. Realtime cutover strategy

1. Subscribe authenticated core consumers to `vehicle_master_revision`, not vehicle row payloads.
2. On any INSERT/UPDATE signal, debounce and call `get_vehicle_core_snapshot()`.
3. Cache only a fully successful `ok=true, code=ok` response.
4. On channel reconnect, visibility return and token refresh, refetch unconditionally.
5. Keep `vehicles` and `vehicle_aliases` publication membership during transition.
6. Verify with two independently authenticated sessions: session A remains subscribed; session B performs a protected synthetic edit; A must update without reload.
7. Disconnect A, mutate from B, reconnect A, and prove the missed event is recovered by refetch with no duplicate channels.
8. Keep `workshop_revision` for workshop data; a core revision event does not replace booking revision events.

## 5. Authority-switch proof gate

Before every consumer/domain switch, capture:

- exact source and target contract versions/signatures;
- field-by-field mapping, null/default/date normalization and excluded fields;
- candidate-set report showing zero unresolved or ambiguous mappings for the switched scope;
- expected-version behavior and a real stale-write rejection;
- role matrix through PostgREST: viewer read/no mutate, operator boundaries, importer boundaries, administrator inheritance, unapproved blocked;
- idempotency and response-loss retry proof;
- audit/history/source evidence and revision increments;
- two-session Realtime and reconnect proof;
- encrypted pre-switch backup, manifest/hash verification and isolated restore;
- rollback feature flag/migration and a successful rollback rehearsal;
- explicit confirmation that browser-local source data is still present and unchanged;
- browser acceptance runs only in an in-memory or dedicated prefixed fixture (`test-50.html`, `test-75.html`, `test-100.html`, or a new Stage 2B prefix); `no-vehicles.html` is prohibited because it deletes `vehicleTrackingCore*` keys;
- if backup format changes, explicit retained-v1 acceptance, new-version restore proof and unknown-version rejection;
- explicit decision on shared `vehicles.version`/master-history semantics for any consumer that treats version or history as core authority.

A failed proof blocks the switch; it does not justify a best-effort merge or first-match fallback.

## 6. Rollback criteria

Immediately stop a cutover and restore the prior read authority when any of these occurs:

- candidate count differs from exactly one where a match is required;
- preview action/vehicle/version/fingerprint differs at apply;
- duplicate, conflicting or malformed identity is accepted;
- a viewer/unapproved user can mutate or raw evidence becomes viewer-readable;
- a stale update succeeds;
- retry creates a second vehicle/source effect or extra version bump;
- Realtime misses changes after reconnect or creates duplicate channels;
- row counts/UUIDs/archived classification diverge from the signed reconciliation;
- browser shared-mode failure silently writes to localStorage;
- backup, restore, lint, ledger, cleanup or environment guard is not clean.

Rollback is fail-closed and domain-scoped. It never silently merges records, deletes source evidence, imports real vehicles, clears browser-local data, or contacts production.

## 7. Broad SELECT retirement proof

The final direct-read retirement review must include:

- repository scan results;
- deployed bundle scan results;
- API/database access-log evidence for the observation window;
- exact grants/policies before and proposed after;
- Realtime authorization impact analysis;
- service backup/restore role proof;
- viewer/operator/importer/admin/unapproved PostgREST matrix;
- a rollback migration that restores only the prior read grants/policies;
- explicit approval in a later Stage 2B phase.

Migration 029 does not retire direct reads and does not start any consumer switch.
