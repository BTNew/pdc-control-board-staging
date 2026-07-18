# Stage 2B — Shared Vehicle Master Design

**Status:** Design checkpoint — implementation gate passed only for conservative exact-match behavior described below

**Branch:** `feature/stage2b-shared-vehicle-master`

**Baseline:** merged Stage 2A source commit `4246f89a6a299ba61db081e3a7851856d8eca81f`

**Approved Stage 2A source:** `6bb75649db3dd695c293fdbbd726f023bf951c06`

**Environment boundary:** staging only (`cdsmnqxtyyoeoznmbidd`); production (`vjdtsswhroyguxyfjdkt`) must not receive requests or changes.

## 1. Goal and non-goals

Stage 2B makes Supabase the sole shared authority for **core vehicle identity/master records** used by the board and workshop planner. The first slice migrates identity only. It deliberately does not migrate or reinterpret operational state.

### Included core fields

- canonical vehicle UUID;
- stock number;
- VIN;
- Toyota/order number where needed for source matching;
- job-card number;
- key number;
- customer name;
- vehicle description, make and model;
- salesperson FK/reference;
- ETA to Kewdale and arrival/reference dates needed for age calculations;
- Navision/import batch, source and source metadata;
- stable external/source identifiers and aliases;
- created/updated timestamps, authenticated actor and optimistic version.

### Explicitly deferred

The following remain in their current source and must not be copied into the Stage 2B identity mutation contract:

- Parts completion, ordered/received flags, Parts ETA and Parts stoppage state;
- workflow/station required/completed state;
- location, lifecycle state, board visibility, PMB stage/bay and workshop status;
- workshop stoppages;
- free-text notes, email notes and timeline events;
- RFT, collected, completed, QC and delivery operational state;
- PO tasks, PO attachment contents and work-line allocations;
- AI proposals, AI review decisions, AI email monitoring and automatic updates;
- Admin planner blocks, current-time planner work and unrelated UI redesign.

Existing operational columns may remain on `public.vehicles`; Stage 2B RPCs must not accept or modify them.

## 2. Current authority and remaining localStorage inventory

### Vehicle-core keys

| Key/family | Current role | Core reads | Core writes | Stage 2B treatment |
|---|---|---|---|---|
| `vehicleTrackingCoreNavisionOnlyVehicles:v1` (`ADDED_KEY`) | Full records created outside the static/Navision dataset | `loadAddedVehicles()` and `buildVehicleData()` (`app.js:1241`, `1621-1642`) | manual add, PD/job-card creation, PO creation, reviewed vehicle import, Navision additions (`app.js:4949-4992`, `11332-11379`, `11552-11598`, `13919-13972`, `15141-15187`) | extract without deletion; preview/reconcile into canonical vehicles; retire writes only after acceptance |
| `vehicleTrackingCoreNavisionOnlyEdits:v1` (`EDITS_KEY`) | Generic patch map keyed by local `vehicleKey` | merged over base/added records by `buildVehicleData()` (`app.js:1621-1642`) | generic `saveVehicleEdits()` plus import paths (`app.js:9010-9038`, `11646-11651`, `13919-13972`) | extract only the allow-listed core fields; leave all deferred fields in their current source |
| `vehicleTrackingCoreNavisionOnlyDeleted:v1` (`DELETED_KEY`) | Browser-local deleted snapshots/keys | `deletedVehicleKeys()` and `deletedVehicleRecords()` (`app.js:1247-1278`) | removal/import reconciliation (`app.js:7660-7670`, `13919-13979`) | do not migrate lifecycle/delete state in initial slice; retain as rollback evidence |
| `vehicleTrackingCoreNavisionOnlyImport:v1` | Last Navision import report | app boot/sidebar (`app.js:1677`) | Navision apply (`app.js:13991-13992`) | source evidence only; import-run metadata may be recorded, but not treated as vehicle authority |
| `vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1` | Latest Autocare scan/cache | boot/reload and Autocare matching (`app.js:1674`, `12087-12115`, `14485`) | scan/reset (`app.js:11815`, `11860`) | deferred cache/integration; never a Stage 2B authority |
| static `window.VEHICLE_TRACKING_DATA.vehicles` | Base dataset loaded with page/fixture | cloned by `buildVehicleData()` (`app.js:1626`) | replaced by import/render bootstrap rather than localStorage | included in browser extraction as original evidence; shared snapshot replaces it only at read cutover |
| `vehicleTrackingCoreWorkshopPlan:v1` | Legacy planner rows referencing `vehicleKey` | `workshopLoadPlans()` (`workshop-planner.js:509-529`) | `workshopSavePlans()` when shared mode is off (`workshop-planner.js:532-557`) | bookings are deferred; only resolve/report linkage to canonical UUIDs in 2B.5 |
| `vehicleTrackingCoreWorkshopBaySetup:v1` | Local bay default assignee | planner legacy mode | planner legacy mode | Stage 2A reference data; not vehicle master |
| `vehicleTrackingCoreNotes:<stock>` | Dynamic vehicle notes | detail/export | note form | explicitly deferred; never silently swept into Stage 2B |
| `vehicleTrackingCoreNavisionOnlyPoTasks:v1` / `...PoFiles:v1` | PO work/file metadata keyed by local vehicle key | `buildVehicleData()` | PO import | deferred |
| `vehicleTrackingCoreNavisionOnlyAuditLog:v1` | Browser-local audit entries | transaction/action paths | capped append log | superseded by shared audit; not imported as master history |
| `vehicleTrackingCoreEmailReviewDecisions:v1` | Applied/rejected email-review decisions | review lookup | reviewed vehicle/parts intake | deferred AI/email intake |
| `vehicleTrackingCoreAiFileAssistantReviews:v1` | File-derived review proposals | seeded/local review merge | review save | deferred AI intake |
| `vehicleTrackingCoreOperationalHealth:v1` | Derived import/backup summary | health panel | recomputation/cache | deferred; recompute rather than migrate |
| `vehicleTrackingCoreStorageTransaction:v1` | Crash-recovery journal for local writes | startup recovery | snapshots/restores/removals for arbitrary listed keys | retained until local operational writes are retired |

### Local-only and retired-reference keys

The following remaining keys are inventoried but are not vehicle-master
authority:

- `vehicleTrackingCoreColumnOrder:v4`,
  `vehicleTrackingCoreColumnWidths:v4:<table-id>`,
  `vehicleTrackingCoreWorkflowWidthMode:v1`,
  `vehicleTrackingCoreRowWidthMode:v1`,
  `vehicleTrackingCoreQzPrinter:v1`, and
  `vehicleTrackingCoreWorkshopView:v1` are harmless per-browser display or
  machine preferences and remain local.
- `vehicleTrackingCoreCurrentOperator:v1` and
  `vehicleTrackingCoreCurrentOperatorRole:v1` are legacy identity fallbacks;
  shared mutations must use authenticated identity, and retirement is deferred
  until every fallback path is removed.
- `vehicleTrackingCorePdcMechanics:v1`,
  `vehicleTrackingCorePdcMechanicsRosterSeed:v1`,
  `vehicleTrackingCorePdcSubletProviders:v1`,
  `vehicleTrackingCorePdcSubletProvidersSeed:v2`,
  `vehicleTrackingCoreSalespersons:v1`, and
  `vehicleTrackingCoreSalespersonsSeed:v1` were retired from application
  authority in Stage 2A but remain untouched for its reconciliation importer.

No browser-local key is deleted or overwritten by preview, apply, cutover or acceptance. Existing reset code is not used for migration.

## 3. Core read and write locations

### Read model

1. `buildVehicleData()` (`app.js:1621-1642`) concatenates the static base with `ADDED_KEY`, removes `DELETED_KEY` matches, and overlays `EDITS_KEY` by `vehicleKey`/stock.
2. `vehicleKey()` (`app.js:1590-1597`) chooses non-placeholder stock, then order, then `id`. This value is not globally stable and can change when an order-only vehicle later receives stock.
3. `selectedVehicle()` (`app.js:8993-9007`) first requires one canonical-key match, then one alias match across stock/batch/order/id; multiple matches fail closed.
4. Search/card/customer/detail views read `app.data`; therefore `app.data` is the cutover seam for the shared identity snapshot.
5. Workshop local rows store `vehicleKey`. Shared workshop rows already store `workshop_bookings.vehicle_id` UUID, but `workshopMapSnapshotBookingToLegacyRow()` currently converts the shared UUID-backed record back to stock/permanent ID (`workshop-planner.js:480-506`). Stage 2B must retain the UUID in this adapter.
6. Shared workshop mutations reverse-map that legacy key with a first-match
   `.find()` (`workshop-planner.js:891-898`), so the adapter does not currently
   prove uniqueness even when the database booking itself has a stable UUID.

### Core mutation paths

| Path | Matching today | Core mutation today | Risk |
|---|---|---|---|
| Navision paste/file import | any exact normalized overlap among stock, batch, Toyota order, VIN, frame and local id (`app.js:13635-13660`) | writes `ADDED_KEY`, `EDITS_KEY`, deleted list and last-run summary (`13919-13992`) | one incoming row may overlap different existing vehicles by different identifiers; current `.find()` silently takes the first |
| PD/job-card/manual work import | OR match on stock, order or VIN (`4938-4946`) | creates a synthetic local record when no match (`4949-4992`) then patches reviewed core and deferred work fields | `.find()` first-match ambiguity; generated `PD-*` identity is not stable |
| Purchase-order import | OR match on stock/reference/VIN (`11541-11549`) | creates local record (`11552-11598`) and patches core plus deferred PO/work fields | first-match ambiguity and reference may not be a globally unique stock number |
| Manual vehicle activation/add | no server check; generated `NEW-*` when blank (`11332-11379`) | appends a full local record | duplicates across browsers; placeholder stock cannot establish identity |
| Vehicle detail edit | current selected local key (`8993-9007`) | generic patch store (`9010-9038`, form submit around `9353`) | master and operational fields share one unrestricted local function |
| Reviewed email vehicle import | exact stock/key/order/batch, first unique only (`15019-15026`) | creates/patches identity and work fields (`15141-15187`) | AI/email scope is explicitly deferred; no Stage 2B automatic write |

Stage 2B replaces only core portions of the first four paths and manual core edits. Deferred fields continue through their existing source until later stages, without being represented as migrated.

## 4. Identity and normalization rules

### Normalizers

- **Stock number:** trim, uppercase, remove spaces and hyphens for comparison; preserve original text as evidence. Empty, `0`, `TBA`, `NEW-*`, `PD-*`, `PENDING-*` and equivalent placeholders are not unique identifiers.
- **VIN:** trim, uppercase, remove whitespace/hyphens; valid canonical VIN is exactly 17 characters from `[A-HJ-NPR-Z0-9]`. Invalid/partial VIN is retained as source evidence but is not eligible for automatic matching or uniqueness.
- **Toyota/order, job card, key number and source IDs:** trim and uppercase for comparison; remove only formatting characters explicitly approved for that identifier type. Customer, vehicle description and salesperson text are never identity keys.

### Deterministic matching

For each incoming row, gather **all** candidate UUIDs for every valid strong identifier:

1. valid VIN;
2. real stock number;
3. source-scoped stable external record identifier;
4. Toyota/order number where configured as unique for that source;
5. job-card number only where confirmed unique for the source/batch.

Classification:

- zero candidates + sufficient core data: `new_vehicle`;
- exactly one candidate and no identifier points elsewhere: `safely_matched`;
- multiple local/source rows with the same proposed identity: `duplicate_candidate`;
- identifiers point to more than one canonical UUID: `ambiguous_match`;
- no usable strong identifier or validation failure: `invalid_incomplete`.

**Hard rule:** no priority order is used to pick between different UUIDs. If stock points to vehicle A and VIN points to vehicle B, the result is ambiguity/manual review, not “VIN wins” or “first row wins.” Customer/model similarity may be displayed to a reviewer but can never make a row safe.

## 5. Existing Supabase reuse

### Reused tables/columns

- `public.vehicles` already has UUID PK, `permanent_vehicle_id`, stock, VIN, Toyota order, job card, customer, salesperson FK, make/model, ETA to Kewdale, source payload, version, actors and timestamps (`001_initial_schema.sql:36-66`).
- `public.vehicle_aliases` already has UUID PK, vehicle FK and unique `(alias_type, alias_value)` (`001_initial_schema.sql:68-76`). It needs normalized/source/evidence/version metadata.
- `public.import_runs` already records source file/hash, status, counts, summary, actor and timestamps (`001_initial_schema.sql:120-136`).
- `public.audit_events`/`audit_pdc_event()` provide mutation history (`001_initial_schema.sql:171-183`; `003_rpc_functions.sql:18-59`).
- `public.salespeople` and `vehicles.salesperson_id` are reused.
- `public.workshop_bookings.vehicle_id` already references `vehicles.id` (`006_workshop_planner_foundation.sql:51-77`).
- `get_workshop_snapshot()` includes UUID-backed vehicle rows (`012_workshop_snapshot_and_revision.sql:64-84`) and can be extended without migrating operational fields.
- Realtime already publishes `vehicles` (`001_initial_schema.sql:222`); replica identity must be explicitly set to FULL in Stage 2B.
- Migration 005 already drops direct browser-write policies and revokes browser writes on vehicles, aliases, import runs and audit events (`005_lock_down_direct_writes.sql:7-27`). Stage 2B reasserts this boundary.
- Existing approved viewers can directly select every `vehicles` column under
  the broad migration-002 policy. Stage 2B introduces a sanitized core snapshot
  contract first, then removes broad direct table reads at the final cutover
  after workshop and board consumers no longer depend on them.

### Existing protected RPCs retained but outside the initial identity mutation contract

`move_vehicle`, `mark_vehicle_deleted`, `restore_vehicle`, `record_import_run`, workshop booking RPCs, QC/RFT RPCs and vehicle-intelligence RPCs remain available under their existing scopes. Stage 2B does not use movement/delete/restore to imply that lifecycle state has migrated.

## 6. Migration sequence

Applied migrations 001–027 are immutable.

### Migration 028 — vehicle master foundation

Additive outline:

1. immutable normalization/validation helpers for stock, VIN and source identifiers;
2. add core-only columns to `vehicles` where existing columns are insufficient:
   - `key_number`;
   - `vehicle_description`;
   - `salesperson_reference`;
   - `arrival_reference_date`;
   - `source_system`, `source_batch_id`, `source_record_id`, `source_metadata`;
   - normalized generated/stored values for stock and VIN;
3. checks so canonical VIN is null or valid, versions remain positive, and normalized placeholder stock cannot be treated as unique;
4. partial unique indexes for valid VIN and business-approved real stock values; source-scoped uniqueness for `(source_system, source_record_id)`;
5. extend `vehicle_aliases` with normalized value, source scope, original evidence, metadata, actor/timestamps and optimistic version;
6. deterministic unique indexes for strong alias types, without making customer/model text an alias;
7. create `vehicle_master_revision` singleton for preview/apply destination-race checks and a mutation trigger that increments it for core vehicle/alias changes;
8. create `vehicle_master_import_items` only if durable reconciliation evidence is required at apply time; preview itself remains read-only and does not insert rows;
9. set `REPLICA IDENTITY FULL` on `vehicles` and `vehicle_aliases`, and idempotently add aliases to `supabase_realtime`;
10. viewer+ read RLS; no browser INSERT/UPDATE/DELETE policies; reassert write revocations and least-privilege grants;
11. add a sanitized, role-aware core snapshot surface without exposing
    unrestricted `source_payload`; direct table SELECT retirement occurs only
    after all current consumers have cut over;
12. backup/restore metadata coverage and FK-safe restore ordering tests.

### Migration 029 — protected vehicle-master RPCs

- `get_vehicle_master_snapshot()` — role-aware core-only snapshot and revision.
- `preview_vehicle_master_import(source_version, source_hash, rows)` — `STABLE`, read-only classification; returns destination revision/hash and per-row candidates/reasons.
- `apply_vehicle_master_import(preview, rows)` — importer/admin only; locks revision, verifies source hash/version and destination revision, reclassifies under lock, applies reviewed safe rows only, audits each mutation, returns rollback mapping and reconciliation counts.
- `upsert_vehicle_master_from_source(...)` — importer/admin only, exact source identities, optimistic version, core allow-list only.
- `create_manual_vehicle(...)` — operator/admin according to final access matrix; rejects duplicates/ambiguity and placeholder-only identity.
- `edit_vehicle_master(...)` — operator/admin, expected version required, core allow-list only.
- `activate_vehicle_master(...)` — protected activation without accepting lifecycle/workflow payloads.
- all RPCs return structured JSON error codes such as `invalid_stock`, `invalid_vin`, `duplicate_candidate`, `ambiguous_match`, `version_conflict`, `source_changed`, `destination_changed`, `permission_denied`, and `not_found`.

### Later Stage 2B migrations

- 030: workshop UUID retention/link reconciliation support, no guessed links;
- 031: final privilege/retirement guards and staging evidence fixes if review requires them.

## 7. Import preview/apply contract

1. Browser exporter reads static base, `ADDED_KEY` and core-only fields from `EDITS_KEY`; it leaves every local key untouched.
2. Export preserves original row/key/value evidence and computes a canonical SHA-256 over source version plus rows.
3. Preview is read-only. It returns source version/hash, destination master revision/hash, normalized identifiers, all candidate UUIDs, classification and reason codes.
4. The UI/report permits apply selection only for `safely_matched` and `new_vehicle`. Duplicate, ambiguous and invalid rows are never auto-selected.
5. Apply receives the exact preview evidence and source rows. The RPC recomputes source hash, locks/checks destination revision, re-runs classification, and refuses the whole apply if source or destination changed.
6. Every accepted update uses the version captured at preview, never a freshly fetched version substituted at apply.
7. Every mutation goes through protected RPC code and writes `audit_events`; apply returns old local key → canonical UUID, before/after versions and created aliases.
8. Reconciliation reports all counts and unresolved rows. Local evidence remains available for rollback/independent review.

## 8. Shared service and cutover

### 2B.1 service/read model

A dedicated `vehicle-master-data-service.js` follows the proven Stage 2A patterns:

- cache is committed before state notification;
- monotonically increasing request generation rejects stale responses;
- one Realtime channel per subscribed table/resource;
- reconnect transition triggers authoritative snapshot reconciliation;
- explicit states: `disabled`, `loading`, `connected_read_only`, `connected_editable`, `reconnecting`, `permission_denied`, `offline_error`;
- local authority remains active during parity-only mode, but shared and local snapshots are compared and discrepancies reported.

### 2B.2 controlled staging import

Synthetic fixtures first, then sanitized browser exports. No production endpoint is permitted. Apply requires safe classifications and exact preview tokens.

### 2B.3 shared read cutover

Board search/cards, customer views and workshop vehicle lookup read core fields from the shared snapshot. Existing operational fields are joined from their existing source by canonical/local mapping and are clearly not treated as shared. In shared mode, unavailable shared identity fails closed; stale local identity is not silently promoted to authority.

### 2B.4 protected write cutover

Navision, PO/job-card core portions and manual core create/edit use protected RPCs. Accepted and rejected mutations both trigger authoritative reconciliation. Core localStorage writes remain guarded until acceptance; keys are not deleted.

### 2B.5 workshop linkage

- Retain `vehicle_id` UUID in `workshopMapSnapshotBookingToLegacyRow()` and every reconciliation map.
- Existing DB bookings already have a non-null UUID FK and must remain unchanged.
- Legacy local booking references are resolved using the same all-candidate matcher. Zero/multiple matches are reported as unresolved; no booking is linked by customer/model or first match.
- Acceptance requires zero orphaned DB bookings and a complete unresolved-legacy report.

## 9. Rollback and dual-read controls

- No production deployment or request.
- Fresh encrypted staging backup and verified restore evidence before migration apply/import.
- Migrations are additive; rollback is a reviewed forward migration, not editing 001–027.
- Frontend rollback reverts only the staging deployment commit.
- Browser-local data remains untouched and exportable throughout.
- Dual-read parity mode has exactly one named authority: local before 2B.3, shared after 2B.3. It never merges two authorities silently.
- Shared-mode failure never falls back to stale local core identity.
- Rollback mapping records every local key/source row and resulting UUID/version.

## 10. Required tests

Credential-free tests cover normalizers, exact matching, multi-candidate ambiguity, preview/apply source and destination races, cache-before-notify, stale-response rejection, reconnect/no-duplicate channels, grants/RLS static shape, structured errors, retirement guards, workshop UUID retention, and backup/restore FK ordering.

Staging-only tests cover role matrix, protected RPCs, direct-write denial, Realtime create/edit/activation behavior, two-browser search/card/planner identity updates, ambiguity refusal, reconnect catch-up, rollback/cleanup and zero production requests.

## 11. Decisions and safe defaults

| Ambiguity | Safe default used for implementation | Decision still needed before real browser-data apply |
|---|---|---|
| May real stock numbers ever be reused? | enforce uniqueness only for non-placeholder active canonical stock; any existing collision blocks migration/index application | confirm reuse/archive rule |
| Is job-card number globally unique? | source-scoped alias only; never sole automatic global match | confirm business scope |
| Is Toyota/order number globally unique? | source-scoped strong alias; conflicts become ambiguity | confirm source scope |
| Is `pmb_key_tag` the requested key number? | add/use a distinct identity `key_number`; do not mutate `pmb_key_tag` operational behavior | confirm whether they should later converge |
| Which arrival date drives board age? | retain `eta_to_kewdale` and add a separate `arrival_reference_date`; do not infer arrival from workflow/location timestamps | confirm exact source column/date semantics |
| Can operators create/edit master identity or importer/admin only? | viewers read only; importer/admin for batch/source upsert; operator/admin for deliberate manual create/edit, all audited | confirm final access matrix |
| Legacy booking has no strong vehicle identifier | unresolved report; booking is not linked or dropped | human resolution required |
| Two identifiers point to different UUIDs | `ambiguous_match`; no write | human resolution required |

## 12. Design gate conclusion

Core identity can be migrated without silently merging ambiguous vehicles **only** with the all-candidate exact matcher, read-only preview, source/destination race checks, and fail-closed unresolved handling above. The design therefore permits migration 028 implementation for schema/security and synthetic staging fixtures. It does **not** authorize applying real browser-local rows classified as duplicate, ambiguous or invalid, and it does not authorize retiring or deleting local data.
