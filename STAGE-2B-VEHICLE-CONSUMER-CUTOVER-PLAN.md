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

### C1 — lifecycle identity resolver first — **complete on staging**

Migration `030` adds `resolve_vehicle_lifecycle_identity`, a viewer-authorized SECURITY DEFINER RPC that accepts text inputs for explicit UUID, canonical stock/VIN/permanent ID, source-scoped job/order identity, approved aliases and permitted source evidence. It reuses the immutable 028/029 normalizers, evaluates every candidate, and returns one of `resolved`, `not_found`, `ambiguous`, `conflict`, `invalid_input` or `unauthorized`; the browser maps transport/auth failures to `service_unavailable`/`unauthorized`.

The resolved allowlist is deliberately limited to canonical UUID, optimistic version, QC timestamp, lifecycle state, archived flag, resolver revision and matched input names. The core snapshot was not widened. `vehicle_lifecycle_resolver_revision` carries only a revision signal; each event and reconnect performs an authoritative RPC refetch, and consumer actions also resolve freshly rather than reusing the cache.

**Proof completed:** UUID, stock, VIN, source-scoped job card, source evidence and alias resolution; zero/many/canonical-alias/cross-identifier failures; invalid inputs; archived addressability; viewer/operator/administrator role matrix; anon/unapproved denial; narrow projection; stale in-flight suppression; version/revision refresh; two independent browser sessions refreshed from version 1 to 2; zero direct `vehicles` lifecycle reads; browser-local stores unchanged; synthetic fixture cleanup.

**Rollback:** `resolverRollbackDirectRead` is accepted only when the project ref is exactly staging, defaults `false`, is observable in diagnostics and is never selected in response to resolver ambiguity/conflict/failure. The guarded direct read requests at most two rows and itself returns `ambiguous` rather than first-row authority. Transitional authenticated table SELECT remains; remove this flag and code after the agreed C1 observation window.

### C2 — workshop identity alignment and offline tools

#### C2a — guarded importer/admin identity export — **complete on staging**

Migration `031` adds `export_workshop_legacy_vehicle_identities(text, integer, bigint)`, an authenticated SECURITY DEFINER export available only when `current_pdc_user_role()` is exactly `importer` or `administrator`. Viewer and operator/controller sessions receive `unauthorized`; anon/public have no execute grant. The projection contains only canonical vehicle UUID, optimistic version, archived flag, typed approved canonical/alias identifiers, conflict evidence and the lifecycle resolver/export revision.

The export is UUID ordered, cursor paginated (maximum 500 rows), revision pinned across pages and retry safe because it is read-only. It reuses the 028–030 SQL normalizers, excludes placeholder stock and malformed VINs, emits normalized duplicate and canonical-versus-alias candidate sets, and returns `stale_export` if the expected revision changes.

`scripts/workshop_legacy_import.py::fetch_reference_data` now uses this export by default. Matching evaluates the complete candidate set across canonical stock, VIN, job card, permanent ID, Toyota order and source record, approved migration-030 alias classes, and retained `vehicle_master_source_records` evidence; zero, many, conflicting and inactive identities are review buckets, never first-row authority. Apply retains the canonical UUID and locks the accepted export revision for the transaction. The historical direct vehicle query remains only behind the explicit `--vehicle-export-rollback` flag, which is staging guarded by the exact project ref plus fixture, defaults off, logs use, exports ambiguity evidence instead of choosing a row, and carries a revision that must still be current at apply.

**Proof completed:** importer and administrator access; viewer and operator/controller denial; narrow projection; canonical UUID retention; stock/VIN/job-card/alias/source-evidence normalization; zero/many/canonical-alias/canonical-source conflicts refused; archived handling; deterministic ordering and page retry; malformed completion markers rejected; stale normal and rollback revisions refused; exact apply replay returns one durable receipt with no repeated booking/history write; exact project-ref plus fixture rollback guard; synthetic importer apply with transaction rollback; zero fixture/receipt/source-evidence residue; migration dry run/lint; encrypted backup and isolated restore.

**C2b offline artifact alignment — complete in source.** The migration 031 server contract is sufficient, so no migration 032 is created. `fetch_reference_data` emits `pdc.workshop.vehicle-reference/v2`: resolver revision, UTC generation timestamp, staging/test environment identifier, item count, complete page/cursor evidence, strict typed items/conflicts, and a deterministic SHA-256 over canonical logical content. Python import/dry-run and Node validator consumers independently enforce the same allowlist, SQL-equivalent normalization, canonical/alias/source-evidence distinction, UUID/version retention, checksum/count/pagination integrity, stale-revision refusal and complete candidate-set matching. The former `vehicles` + `vehicleIdentityExport` envelope is disabled by default and requires the explicit staging/test rollback flag, exact revision and a clear warning.

No browser workshop file, `get_workshop_snapshot`, browser-local store, main-board path, workshop authority or production artifact changes in C2b.

**Next after C2b:** C3 is still the reviewed synthetic import/reconciliation pilot described below. It must begin only under a separate explicit instruction; C2b does not authorize it.

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
