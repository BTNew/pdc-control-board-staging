# localStorage → Supabase Migration Plan (Stage 2 Design)

Status: **DESIGN ONLY. No implementation in this document.** Per the current instruction, Stage 2 begins with this design and the accompanying inventory (`docs/localstorage-key-inventory.csv`), not with code changes to `app.js`. Nothing in this document has been deployed, and no migration has been applied.

Branch: `fix/independent-review-production-blockers`. Staging only (`cdsmnqxtyyoeoznmbidd`). Production (`vjdtsswhroyguxyfjdkt`) untouched.

## 1. Why this exists

The independent review identified the browser-local operational data model (vehicles, edits, notes, parts status, mechanic/salesperson/sublet lists, PO tasks, workshop planner state) as the single largest remaining blocker to a genuinely shared, multi-user PDC Control Board. Everything else remediated in Stages 1 and 5–10 hardens the *shared* data path (account approval, RLS, grants, backup/restore, artifact validation, test reproducibility) — but most of the application's actual day-to-day data still lives in `localStorage`, is invisible across browsers, and is not backed up by the encrypted backup system at all (the backup system only ever covered Supabase tables).

This document is the complete inventory and migration plan the review explicitly required before any `app.js` rewrite begins.

## 2. Summary of the inventory (`docs/localstorage-key-inventory.csv`)

27 distinct localStorage keys/key-families were traced by reading actual read/write call sites in `app.js` and `workshop-planner.js` — not guessed from key names alone. Classification:

- **Category A (must move to Supabase): 14 entries.** Vehicle edits (the generic patch store), manually-added vehicles, deleted vehicles, PO tasks, PO files, email-review decisions, AI file-assistant reviews, Navision import results, mechanics roster, sublet providers, salespeople, per-vehicle notes, the legacy workshop plan array, and the workshop bay-setup defaults.
- **Category B (harmless local preference, stays in localStorage): 7 entries.** Workshop planner view filter, column order, column widths, row/column density mode, the QZ Tray printer name (genuinely per-computer, must never sync), and — separately noted — none of these carry vehicle-workflow meaning.
- **Category C (obsolete/superseded, to be retired not migrated): 6 entries.** Two seed-version markers (mechanics, sublet, salespeople — 3 total, one per list), the local audit log (superseded by the real `audit_events` table), the legacy pre-Auth operator name/role fallback, the operational-health summary (becomes a live query, not stored state), and the storage-transaction journal (superseded by real Postgres transactions).

Two entries (PO tasks, PO files) are marked **tentative** because their exact field shape could not be confirmed from read/write call sites alone in this pass — see §9.

## 3. Key architectural finding: much of the destination schema already exists

Before designing new tables, the existing Supabase schema was audited (migrations 001–021). This changes the risk profile of Stage 2 substantially:

| Category A data | Existing destination | Status |
|---|---|---|
| Vehicle identity/status fields (location, PMB stage/bay, parts flags, QC/RFT timestamps) | `public.vehicles` | **Already has the columns.** Not yet written to by the frontend for these fields — `saveVehicleEdits()` still owns them locally. |
| Required/completed work | `public.vehicle_work_items` | **Already exists**, already used by `qc_complete_vehicle()`. |
| Parts status/ETA | `public.vehicle_parts_updates` | **Already exists.** |
| Vehicle location/stage moves | `public.vehicle_movements` + `move_vehicle()` RPC | **Already exists and already works** (from migration 003). Not called by the frontend today. |
| Soft-delete / restore | `mark_vehicle_deleted()` / `restore_vehicle()` RPCs | **Already exist and already work.** Not called by the frontend today. |
| QC / RFT transfer / RFT collect | `qc_complete_vehicle()` / `rft_transfer_vehicle()` / `rft_collect_vehicle()` RPCs | **Already exist and already work** (migration 016, this session's earlier QC/RFT/Collected work). |
| Mechanics roster | `public.workshop_technicians` | **Already exists**, already used by the workshop planner's shared-mode path — but the Setup screen's separate mechanic list (`MECHANICS_KEY`) has never been reconciled with it. Two parallel lists exist today. |
| Salespeople | `public.salespeople` (with a real FK from `vehicles.salesperson_id`) | **Already exists.** Never used by the frontend — vehicles are matched to salespeople by free-text name in localStorage. |
| Sublet providers | `public.sublet_providers` | **Already exists.** Never used by the frontend. |
| Import run history | `public.import_runs` | **Already exists**, already has the right columns. |
| Bay default technician | `public.workshop_bays.default_technician_id` | **Already exists** as a column. |
| Audit trail | `public.audit_events` + `audit_pdc_event()` | **Already exists and already used** by every RPC-mediated action. |
| Workshop bookings (planner) | `public.workshop_bookings` + the full protected-RPC write path (`schedule_vehicle_work`, `move_workshop_booking`, etc.) | **Already exists and already works** — this is the completed shared-write-path from the earlier remediation phase of this project. |

**Not yet existing, needing new schema:**
- `public.vehicle_notes` (per-vehicle free-text notes with author/timestamp) — genuinely new.
- `public.po_tasks` / a PO-attachments equivalent — pending clarification (§9).
- A decision on `public.vehicle_aliases` usage for manually-added-vehicle identifier variants (table exists but is not populated by the frontend today).

This means **Stage 2's dominant activity is wiring the frontend to an already-designed, already-tested backend**, not inventing a new schema from scratch — which meaningfully de-risks the timeline versus treating this as a blank-slate design exercise. The exception is genuinely new work: `vehicle_notes`, the PO-tracking tables (pending clarification), and the mechanics-roster reconciliation (two parallel lists today).

## 4. Category A → Supabase mapping (per item)

For every Category A row, the following detail is recorded in `docs/localstorage-key-inventory.csv` and summarized here by destination:

### 4.1 `public.vehicles` (existing table)
- **Primary key:** `id` (uuid, existing).
- **Vehicle relationship:** is the vehicle.
- **Relevant existing columns:** `current_location`, `pmb_stage`, `pmb_bay_stage`, `pmb_bay_number`, `pmb_key_tag`, `eta_to_kewdale`, `rft_transferred_at`, `rft_collected_at`, `deleted_at`, `deleted_reason`, `version` (optimistic concurrency, existing).
- **Missing columns identified during this audit that Category A data needs and `vehicles` does not yet have:** `qc_completed_at`/`qc_completed_by` were referenced in the `qc_complete_vehicle()` RPC body (§3) — confirm these columns exist via a live schema check before Stage 2C implementation; if absent, a small additive migration is needed (not designed here, per the "do not write migrations yet" instruction for this document).
- **Audit requirement:** every write must call `audit_pdc_event()`, exactly as `move_vehicle()`/`mark_vehicle_deleted()`/`qc_complete_vehicle()` already do.
- **Realtime requirement:** `vehicles` should be added to the `supabase_realtime` publication if not already present (confirm via live check before implementation — not assumed here).
- **RLS requirement:** existing `vehicles` RLS (viewer read / operator+ write, per the RLS matrix already tested in Stage 7) should be reused, not redesigned.
- **Conflict/version handling:** `version` column + optimistic-lock pattern already proven throughout the workshop RPCs — every new vehicle-mutation RPC must follow the same `p_expected_version` pattern.
- **Read RPC:** none needed beyond direct `select` under RLS for most fields; a `get_vehicle_snapshot()`-style RPC may be worth adding for the same reasons `get_workshop_snapshot()` exists (single round trip, consistent read).
- **Mutation RPCs:** see §6 — one narrow RPC per real business action (move location, change PMB stage/bay, set parts status, etc.), never one generic "update vehicle" RPC.

### 4.2 `public.vehicle_work_items` (existing table)
- Already has `required`/`completed`/`completed_by`/`completed_at`/`notes` per `(vehicle_id, work_key)`.
- **Gap:** the local `EDITS_KEY` data almost certainly stores *which* work items are "required" per vehicle type/stage as a derived/business-rule concept rather than a stored flag per vehicle — confirm this before assuming a 1:1 column mapping (§9).

### 4.3 `public.vehicle_parts_updates` (existing table)
- Already has `parts_required`/`parts_ordered`/`parts_received`/`parts_stoppage`/`parts_stoppage_reason`/`worst_eta`.
- **Gap:** this table has no obvious history/versioning column beyond `updated_at` — if the business needs to see *previous* ETAs (a capability explicitly required elsewhere in this project's AI Email Monitoring brief), either this table needs a companion history table or the existing `vehicle_eta_history` table (confirmed to exist in the schema audit, §3-adjacent) should be reused. Needs a decision, not assumed here.

### 4.4 New: `public.vehicle_notes`
- **Primary key:** `id` uuid.
- **Vehicle relationship:** `vehicle_id uuid not null references public.vehicles(id) on delete cascade`.
- **Required columns:** `note_text text not null`, `created_by uuid references auth.users(id)`, `created_at timestamptz not null default now()`.
- **Foreign keys:** `vehicle_id` as above.
- **Unique constraints:** none needed (notes are an append-only log).
- **Check constraints:** `note_text` non-empty (`check (length(trim(note_text)) > 0)`).
- **Indexes:** `(vehicle_id, created_at desc)` for the detail-panel newest-first read.
- **Audit requirement:** notes are themselves a form of audit trail; still emit an `audit_events` row on creation for consistency with every other mutation, distinguishing "note added" from other action types.
- **Realtime requirement:** yes — the acceptance test explicitly requires "a note added in Browser A appears in Browser B."
- **RLS requirement:** readable by viewer+, writable by operator+ (matches the existing role model; a note is not a higher-risk action than most operator-level writes).
- **Read RPC:** plain `select` under RLS is sufficient; no read RPC needed.
- **Mutation RPC:** `add_vehicle_note(p_vehicle_id uuid, p_note_text text)` — no version/conflict handling needed since notes are append-only, never edited or deleted (matching the current behavior, which also never allows editing a past note).
- **Import handling:** every existing per-vehicle `vehicleTrackingCoreNotes:<stock>` key across every staff browser must be walked (not just the named-constant key list) and imported with its original timestamp preserved and a clear "imported from legacy local notes" marker distinguishing it from a note added by a real authenticated user (since the legacy notes have no author).
- **Rollback:** notes are additive-only; rollback is "do not run the importer again" plus the standard encrypted-backup restore-to-isolated-schema path if a bad import needs to be inspected/reversed.

### 4.5 `public.salespeople`, `public.sublet_providers`, `public.workshop_technicians` (existing tables)
- All three already have the right shape (`name`, `active`, plus `email`/`phone` where relevant).
- **Read RPC:** none needed — a `select ... where active = true` under RLS is sufficient (all three already have `viewer`-readable RLS confirmed in Stage 7).
- **Mutation RPCs:** none exist yet with an audit trail attached. Direct RLS-governed writes on `salespeople`/`sublet_providers` are the *currently accepted* pattern (confirmed safe in Stage 7's privilege-hardening work), but per this brief's explicit instruction to prefer protected business actions over raw table writes, Stage 2A should add `add_salesperson()`/`deactivate_salesperson()` (and equivalents for sublet providers and technicians) that wrap the write in `audit_pdc_event()`, rather than relying on the RLS-only direct-write pattern for these three tables going forward.
- **Reconciliation risk:** vehicles currently store the salesperson as a free-text name string, not a `salesperson_id` FK. Cutover requires matching every distinct free-text name to a real `salespeople.id` (or creating one if genuinely new), then backfilling `vehicles.salesperson_id`. Same class of problem for the mechanics roster (`MECHANICS_KEY` vs `workshop_technicians`) — two independently-maintained name lists must be reconciled into one before the frontend can stop reading `MECHANICS_KEY`.

## 5. Frontend operational write-path inventory

Every current frontend function that mutates operational data, per the brief's required list:

| Function | Current storage behaviour | Shared RPC already exists? | Proposed protected RPC | Realtime required? | Can current UI be preserved? | Migration order |
|---|---|---|---|---|---|---|
| `saveVehicleEdits(key, updates)` | Generic merge-patch into `EDITS_KEY` for ANY field | No (this is exactly the "one generic function" the review said not to replicate) | **Decompose, not port.** Replace with the specific RPCs below, called from the same UI event handlers that currently call `saveVehicleEdits()` | Yes | Yes — UI stays the same, only the storage call inside each handler changes | Stage 2C (bulk of the work) |
| Manual vehicle add (`addCustomerFromForm()`) | `saveAddedVehicles()` appends to `ADDED_KEY` | No | `create_manual_vehicle(p_stock, p_customer, p_vin, ...)` — validates identifiers, checks for an existing match first (stock/VIN/job-card), returns a conflict result rather than silently creating a duplicate | Yes | Yes | Stage 2B |
| Vehicle delete (`removeVehiclesFromTrackerUnsafe()`) | Moves the record into `DELETED_KEY` | **Yes** — `mark_vehicle_deleted()` already exists | Wire the existing RPC in | Yes | Yes | Stage 2B (early — RPC already exists) |
| Vehicle restore | Reads back from `DELETED_KEY` | **Yes** — `restore_vehicle()` already exists | Wire the existing RPC in | Yes | Yes | Stage 2B |
| Parts information change | `saveVehicleEdits()` with parts-prefixed fields | No | `update_vehicle_parts_status(p_vehicle_id, p_expected_version, p_parts_required, p_parts_ordered, p_parts_received, p_parts_stoppage, p_parts_stoppage_reason, p_worst_eta)` | Yes | Yes | Stage 2C |
| Add note | `setNotes(stock, [...])` | No | `add_vehicle_note(p_vehicle_id, p_note_text)` (§4.4) | Yes | Yes | Stage 2D |
| Change required work | `saveVehicleEdits()` (exact mechanism unclear — see §9) | No | Depends on clarification — likely `set_work_item_required(p_vehicle_id, p_work_key, p_required)` | Yes | Yes, pending clarification | Stage 2C |
| Change completed work | `saveVehicleEdits()` | Related — `qc_complete_vehicle()` covers the QC case specifically | `complete_work_item(p_vehicle_id, p_expected_version, p_work_key, p_notes)` (generalizes the pattern `qc_complete_vehicle()` already uses, for non-QC work items) | Yes | Yes | Stage 2C |
| Change stoppages | `saveVehicleEdits()` (parts-stoppage fields) plus a possible non-parts stoppage concept — needs confirmation this is only ever parts-related today | No (beyond parts) | Covered by `update_vehicle_parts_status()` if stoppages are parts-only; a separate `record_job_stoppage()` may be needed if not (Stage 2 audit did not find a clearly separate non-parts stoppage write path in this pass — flagged for confirmation) | Yes | Yes | Stage 2C |
| Modify mechanic names | `saveMechanics()` on `MECHANICS_KEY` | Partial — `workshop_technicians` exists but is a separate list | `add_technician()` / `deactivate_technician()`, plus a one-time reconciliation import merging `MECHANICS_KEY` into `workshop_technicians` | Yes | Yes | Stage 2A |
| Modify salespeople | `saveSalespersons()` on `SALESPERSONS_KEY` | Partial — table exists, RPC does not | `add_salesperson()` / `deactivate_salesperson()`, plus free-text-name-to-FK reconciliation | Yes | Yes | Stage 2A |
| Modify sublet providers | `saveSubletProviders()` on `SUBLET_PROVIDERS_KEY` | Partial — table exists, RPC does not | `add_sublet_provider()` / `deactivate_sublet_provider()` | Yes | Yes | Stage 2A |
| PO task changes | `savePoTasks()` on `PO_TASKS_KEY` | No | Pending clarification (§9) before an RPC can be designed | Yes | Pending clarification | Stage 2D (after clarification) |
| Vehicle location/status changes | `saveVehicleEdits()` (location fields) | **Yes** — `move_vehicle()` already exists and covers exactly this | Wire the existing RPC in | Yes | Yes | Stage 2C (early — RPC already exists) |
| QC/RFT/Completed actions | Already migrated to real RPCs (`qc_complete_vehicle`, `rft_transfer_vehicle`, `rft_collect_vehicle`) per this session's earlier work — **confirm the frontend actually calls these today rather than still writing to `EDITS_KEY` in parallel** (not verified in this pass; flagged as a required check before Stage 2C begins) | Yes | N/A if already wired; otherwise wire the existing RPCs in | Yes | Yes | Stage 2C (verification, not new design) |
| Workshop-booking changes | Already has a complete protected-RPC write path (prior remediation phase); the remaining risk is the legacy local-plan fallback path (`WORKSHOP_PLAN_STORAGE_KEY`), not missing RPCs | Yes | N/A — retire the fallback, do not design new RPCs | Yes (already implemented) | Yes | Stage 2F |

## 6. Explicit rejection of one generic "update vehicle" RPC

Per the brief's instruction, this plan does **not** propose a single `update_vehicle(p_vehicle_id, p_fields jsonb)` RPC as a drop-in replacement for `saveVehicleEdits()`. That would reproduce the exact structural risk (over-broad backend authority via the frontend, no way to restrict which fields a given role can touch, poor auditability of "what business action actually happened") that this project's Stage 6/Stage 7 remediation just spent significant effort eliminating on the account/role side.

Instead, every Category A write path gets its own narrowly-scoped RPC (§5), following the existing pattern already proven throughout `move_vehicle()`, `mark_vehicle_deleted()`, `qc_complete_vehicle()`, and the workshop planner's shared-action bridge:

- Take `p_vehicle_id` and `p_expected_version` (optimistic lock).
- `perform public.require_pdc_role(...)` as the first statement.
- Touch only the specific columns that specific business action legitimately changes.
- Return `{ok: true/false, error: ...}` on conflict rather than throwing where a conflict is an expected, handleable outcome (matching existing RPC style).
- Call `audit_pdc_event()` with a specific, meaningful action label (not a generic "vehicle_updated").

## 7. Migration stages (2A–2F), adjusted for the actual schema/code found

The brief's proposed sequence is retained with adjustments based on what was actually found:

### Stage 2A — Shared lookup and configuration data
- **Scope:** mechanics, salespeople, sublet providers, workshop bays/technician defaults.
- **Adjustment from the brief:** destination tables already exist for all four; the actual work is (1) writing the missing audited mutation RPCs, (2) reconciling the two parallel mechanic lists, (3) reconciling free-text salesperson names to real FKs, (4) wiring the Setup screen's UI to the new RPCs instead of `MECHANICS_KEY`/`SALESPERSONS_KEY`/`SUBLET_PROVIDERS_KEY`.
- **Complexity:** Low-Medium (schema done; reconciliation is the real work).
- **Main risks:** silent data loss if a free-text name doesn't cleanly match any existing/created record during reconciliation; must produce a conflict report, not silently drop or silently invent duplicate roster entries.
- **Expected files changed:** `app.js` (Setup screen mutation call sites), new small JS module or inline RPC-dispatch functions mirroring `workshop-shared-actions.js`'s pattern.
- **Expected migrations:** none required if audited — the tables already exist; only new RPC functions need a migration file.
- **Expected RPCs:** `add_technician`, `deactivate_technician`, `add_salesperson`, `deactivate_salesperson`, `add_sublet_provider`, `deactivate_sublet_provider`, `set_bay_default_technician`.
- **Testing:** real staging RPC tests (mirroring the pattern used throughout this remediation phase's `_staging_test_tools/*.py` files) plus a reconciliation-specific test proving no name is silently dropped or duplicated.
- **Rollback:** these tables are low-volume and easy to hand-correct via SQL if reconciliation goes wrong; also fully covered by the existing encrypted backup/restore system once migration 021's FK-hardening work (Stage 9) is factored in.
- **Independently deployable to staging?** Yes.

### Stage 2B — Vehicle master records
- **Scope:** vehicle identity (stock, VIN, job card, customer, description, arrival dates, source/import metadata), manual-add, delete/restore.
- **Adjustment from the brief:** delete/restore RPCs already exist (`mark_vehicle_deleted`/`restore_vehicle`) — the real new work is `create_manual_vehicle()` (does not exist) and the identifier-matching logic needed to detect a manual-add that's actually a duplicate of an existing Navision-imported vehicle.
- **Complexity:** Medium-High (identifier matching across formatting variants is inherently fuzzy; this project's own AI Email Monitoring brief describes exactly this class of matching problem, and the same matching logic should likely be shared rather than built twice).
- **Main risks:** duplicate vehicle creation across browsers if two staff manually add "the same" vehicle with slightly different stock-number formatting before either browser has synced; this is the exact browser-migration risk in §8.
- **Expected files changed:** `app.js` (manual-add form handler, delete/restore handlers).
- **Expected migrations:** possibly none (schema exists) unless the audit in §9 finds missing columns.
- **Expected RPCs:** `create_manual_vehicle()`, wiring for the two existing RPCs.
- **Testing:** duplicate-detection tests, delete/restore round-trip tests (largely mirroring the existing workshop RPC test style).
- **Rollback:** `deleted_at`/`restore_vehicle()` already provide a safe, reversible path; no destructive delete exists in the proposed design.
- **Independently deployable to staging?** Yes, but should follow 2A (shared lookups) since manual-add likely references a salesperson.

### Stage 2C — Vehicle operational status
- **Scope:** location, workflow state, required/completed work, parts status/ETA, stoppages, QC/RFT/Completed state.
- **Adjustment from the brief:** this is the largest stage by write-path count (§5) but the least novel by schema — `move_vehicle`, `qc_complete_vehicle`, `rft_transfer_vehicle`, `rft_collect_vehicle` all already exist; `vehicle_parts_updates`/`vehicle_work_items` already exist. The main new RPC work is `update_vehicle_parts_status()` and generalizing `complete_work_item()` beyond the QC-specific case.
- **Complexity:** High (this is where `saveVehicleEdits()` is actually decomposed — the single riskiest step in the whole plan).
- **Main risks:** missing an edge case in the decomposition that silently drops a field `saveVehicleEdits()` currently handles; must be preceded by a systematic audit of every distinct field name ever passed to `saveVehicleEdits()` across the codebase (not attempted in this design pass — this is real Stage 2C prep work, not something to guess at).
- **Expected files changed:** `app.js` (every current `saveVehicleEdits()` call site).
- **Expected migrations:** possibly a small additive migration if `vehicles.qc_completed_at`/`qc_completed_by` turn out not to already exist (§4.1) — to be confirmed by a live schema check before this stage starts, not assumed here.
- **Expected RPCs:** `update_vehicle_parts_status()`, `complete_work_item()`, `set_work_item_required()` (pending §9 clarification), plus wiring the existing move/QC/RFT RPCs.
- **Testing:** field-by-field regression tests proving every `saveVehicleEdits()` call site's behavior is preserved after decomposition; this is the stage where the acceptance tests in §8 do the most work.
- **Rollback:** version-conflict handling throughout; encrypted backup/restore for a full point-in-time rollback if needed.
- **Independently deployable to staging?** Yes, but only after 2B (vehicles must exist as real rows before their status can be updated).

### Stage 2D — Notes and history
- **Scope:** notes, audit events (already real), PO task metadata, source references, attachments metadata.
- **Adjustment from the brief:** audit events are already real and already used by every migrated RPC — nothing new needed there. Notes need the new `vehicle_notes` table (§4.4). PO tasks/attachments are blocked on clarification (§9).
- **Complexity:** Medium (notes: low; PO tasks: unknown until clarified).
- **Main risks:** the per-vehicle dynamic notes key (§2, "not covered by the existing bulk key list") means a naive importer that only walks the named `_KEY` constants will silently miss every vehicle's notes — this must be explicitly handled.
- **Expected files changed:** `app.js` (notes-form submit handler, detail-panel note rendering).
- **Expected migrations:** new `vehicle_notes` table + RLS + realtime publication membership.
- **Expected RPCs:** `add_vehicle_note()`.
- **Testing:** the "note added in Browser A appears in Browser B" acceptance test (§8) is the primary proof here.
- **Rollback:** notes are additive-only; nothing to roll back except via full backup/restore.
- **Independently deployable to staging?** Yes, and can run in parallel with 2C since notes do not depend on the parts/status decomposition.

### Stage 2E — Browser-data importer
- **Scope:** preview, duplicate detection, conflict handling, idempotent import, verification, safe local-data retirement.
- **Detailed design:** §8.
- **Complexity:** High (this is a one-shot, high-stakes tool — it runs once per staff browser against real accumulated local data, and getting it wrong risks either data loss or duplicate vehicle creation across the whole fleet).
- **Main risks:** see §8 in full.
- **Expected files changed:** a new dedicated importer UI/flow (not a reuse of the existing Navision-import machinery, which assumes a clean authoritative source file, not a messy accumulated local browser state).
- **Expected migrations:** none beyond what 2A–2D already added; may need an `import_runs`-style tracking row per browser-import run (the existing `import_runs` table may already be reusable here — confirm before designing a new one).
- **Expected RPCs:** none new beyond what 2A–2D already added; the importer calls those same RPCs, just in bulk with a preview/confirm step in front.
- **Testing:** the duplicate-browser-import and conflicting-import acceptance tests (§8) are specifically about this stage.
- **Rollback:** must never auto-clear browser data (explicit requirement, §8); the DB-side rollback is the standard backup/restore path.
- **Independently deployable to staging?** No — this stage is meaningless until 2A–2D exist to import into.

### Stage 2F — Full shared read path
- **Scope:** database-first loading, realtime subscriptions, disposable caching only, removal of static/local operational authority.
- **Adjustment from the brief:** this is also where the Category C retirements happen (local audit log, operator-name fallback, operational-health summary becoming a live query, the storage-transaction journal, the legacy workshop-plan fallback path) — not just "turn on the read path."
- **Complexity:** Medium (mechanically large — touches how the app boots — but low-novelty since the realtime/shared-data patterns are already proven from the workshop planner work).
- **Main risks:** retiring a Category C key before every code path that depends on it (however indirectly) has been re-audited; the brief's own non-negotiable rule ("the website does not fall back to stale local operational data after a database error") must be implemented as an explicit, tested failure mode, not assumed.
- **Expected files changed:** `app.js` boot/init sequence, every remaining direct `localStorage` read for Category A/C data.
- **Expected migrations:** none beyond what prior stages added.
- **Expected RPCs:** none new; this stage is wiring, not schema.
- **Testing:** the "browser refresh does not lose information," "clearing localStorage does not remove operational data," and "no stale-data fallback after a DB error" acceptance tests (§8) are specifically about this stage.
- **Rollback:** feature-flag-gated (mirroring the existing `workshop.sharedData`/`vehicleLifecycle.sharedData` flag pattern already used and tested in this remediation phase) so the cutover can be reverted per-feature without a code rollback.
- **Independently deployable to staging?** Only after every earlier stage; this is explicitly the final stage.

## 8. Browser-data importer requirements

Per the brief, the importer must assume operational data is spread across multiple staff computers with no single authoritative browser. Requirements, and how each is met:

- **Preview mode first:** the importer runs entirely read-only against a given browser's localStorage, producing a full "what would be created/changed" report before any write occurs — mirrors the existing pattern already proven in `scripts/workshop_planner_legacy_extract.js` (extraction) → `scripts/workshop_planner_legacy_validate.js` (validation) → `scripts/workshop_legacy_import.py` (dry-run-by-default, `--apply` required) from the earlier legacy-migration work this session already completed for the workshop planner specifically. The browser importer should follow the same three-phase shape, generalized to cover vehicles/notes/lists rather than only workshop bookings.
- **Duplicate vehicle detection:** reuses the same multi-identifier matching priority (stock number → VIN → job card → registration → Toyota order number → customer name) already specified for the AI Email Monitoring feature's vehicle-matching engine — this is deliberately the same matching problem, and should not be implemented twice with different tolerance rules.
- **Conflicting field values:** when the same vehicle exists in two browsers' local data with different values for the same field, the importer does not silently pick one — it produces a conflict report entry and requires explicit human resolution (mirrors the AI Email Monitoring brief's manual-review-queue pattern).
- **Preserve notes and timestamps:** every per-vehicle note is imported with its original timestamp; imported notes are visibly marked as legacy-imported (no real author, since the old notes never recorded one) rather than attributed to whichever staff member happens to run the importer.
- **Preserve source-browser identity where useful:** the importer should record which named/labeled browser/computer a given import batch came from (a simple free-text label the staff member running the import provides), attached to the import run record, so a later "this looks wrong, where did it come from" question is answerable.
- **Stable vehicle matching:** as above — the same tolerant-formatting matching logic (spaces, hyphens, case, common prefixes) specified elsewhere in this project's AI Email Monitoring brief.
- **Idempotent:** running the same browser's import twice must not create duplicate vehicles or duplicate notes — requires a stable dedup key per imported record (mirrors the `metadata_legacy_plan_id` idempotency pattern already implemented and proven in `scripts/workshop_legacy_import.py` for the workshop-planner legacy import).
- **Before/after counts:** every import run reports exact counts (vehicles matched/created/skipped, notes imported, list entries reconciled) — mirrors the existing legacy-import tooling's reconciliation summary output.
- **Conflict report:** a structured, reviewable list of every field-level conflict found, not a single pass/fail result.
- **Never auto-clears browser data:** explicit requirement; the importer's write phase never calls `localStorage.clear()` or removes any key — retirement of local data (if ever done) is a separate, explicitly confirmed, later action, not an automatic side effect of running the importer.
- **Explicit confirmation before retirement:** local-data retirement (removing the now-migrated keys from a given browser) requires a distinct, separate confirmation step after the import has been verified successful — never bundled into the import action itself.
- **Supports importing each currently-used browser:** the importer is a UI flow run once per staff computer, not a one-time server-side migration — because the brief is explicit that no single browser has the complete dataset.
- **Prevents an older browser import from overwriting newer database information:** every Category A field that already has a `version`/`updated_at` column in its Supabase destination must compare the local value's own last-modified information (if available) against the current database value before applying an import-driven update, and skip (reporting a conflict) rather than blindly overwrite when the database's value is newer than the local snapshot being imported. Where the local data has no reliable last-modified timestamp of its own (most of these keys currently do not track one), the safer default is to treat any existing database value as authoritative and only import genuinely new/never-before-seen data, surfacing everything else as a conflict for manual review rather than guessing which is newer.

## 9. Fields whose meaning is unclear (not guessed at)

Per the brief's explicit instruction not to guess:

1. **`PO_TASKS_KEY` / `PO_FILES_KEY` exact field shape.** The read/write call sites (`loadPoTasks`/`savePoTasks`/`loadPoFiles`/`savePoFiles`) were traced, but the actual object shape stored under these keys — what a "PO task" contains, what statuses/fields it has, whether "PO files" are actual binary attachments (base64/data-URL) or just metadata about files stored elsewhere — was not determined from the call sites alone in this pass. **This needs either a direct answer from the project owner or a dedicated follow-up code-reading pass focused only on these two keys** before Stage 2D's PO-task schema can be finalized.
2. **Whether "stoppages" exist outside the parts-related case.** The brief's write-path list includes "changing stoppages" as a distinct item from "changing Parts information," but this audit only found parts-related stoppage fields (`partsStoppage`/`partsStoppageReason`) in `vehicle_parts_updates` and no clearly separate non-parts stoppage concept in the current `app.js` write paths traced. **Needs confirmation**: is there a job-stoppage concept independent of parts (e.g. "stopped for QC hold," "stopped for customer decision") that this audit simply didn't locate, or is "stoppages" in the brief specifically about parts stoppages as already modeled?
3. **Whether "required work" is itself a stored per-vehicle flag or a derived/business-rule value.** `vehicle_work_items.required` exists as a column, but it was not confirmed in this pass whether the current `app.js` code ever actually *writes* to a "required" concept via `saveVehicleEdits()`, or whether "required work" is computed from vehicle type/stage rules rather than stored per-vehicle. This materially changes whether `set_work_item_required()` (§5) is a real RPC that needs to exist, or whether "required" should instead be treated as Category C (derived, not migrated).
4. **Whether the QC/RFT/Completed frontend flows already call the existing RPCs or still write to `EDITS_KEY` in parallel.** **CONFIRMED via a direct grep check during this design pass: `app.js` contains zero references to `qc_complete_vehicle`, `rft_transfer_vehicle`, or `rft_collect_vehicle`.** These RPCs exist and work in the database (proven by staging tests from earlier in this remediation project) but the frontend has never been wired to call them — the QC/RFT/Completed UI flows still write only to `EDITS_KEY` today. This is real, not-yet-started Stage 2C work, not a verification step — remove any assumption that this portion of Stage 2C is "already done."
5. **Whether `vehicles.qc_completed_at`/`qc_completed_by` actually exist as columns today.** **CONFIRMED via a live, read-only `information_schema.columns` check against staging during this design pass: both columns exist on `public.vehicles` today.** This removes one candidate "missing column" risk from Stage 2C's estimate — no additive migration is needed for these two fields specifically.

None of these five open questions block writing this design document, but all five materially affect Stage 2C/2D implementation estimates and must be resolved (by direct answer or a further targeted code-reading pass) before that code is written.

## 10. Acceptance tests (to be written before implementation, not after)

Every test below must exercise real staging Supabase behavior (mirroring the existing `_staging_test_tools/*.py` convention already used throughout this remediation phase — real module logic, not mocks) once the corresponding stage is implemented. Listed here as the acceptance criteria the implementation must satisfy, not yet written:

1. Two browsers load the same vehicle records (Stage 2B/2F).
2. A note added in Browser A appears in Browser B (Stage 2D, requires realtime).
3. Parts status changed in Browser A appears in Browser B (Stage 2C, requires realtime).
4. Mechanic changes appear in both browsers (Stage 2A, requires realtime).
5. Vehicle locations and statuses remain identical across browsers after a move (Stage 2C).
6. Browser refresh does not lose information (Stage 2F — proves the database, not localStorage, is now authoritative).
7. Clearing localStorage does not remove operational data (Stage 2F — the strongest proof that Category A data has genuinely left the browser).
8. Database backup contains every operational change (mirrors the FK-hardening backup/restore work already completed in Stage 9 of this remediation — extend the existing `test_backup_restore_fk_hardening_staging.py`-style real backup+restore test to cover the new tables).
9. Duplicate browser imports do not create duplicate vehicles (Stage 2E, idempotency).
10. Conflicting imports require review (Stage 2E, conflict-report requirement).
11. Viewer cannot change operational data (already covered by the existing RLS matrix pattern from Stage 7 — extend `test_role_access_matrix_staging.py`'s style to the new RPCs).
12. Controller can perform only permitted actions (same extension).
13. Administrator actions are audited (extend the existing `audit_pdc_event()` coverage pattern).
14. Realtime subscriptions reconnect safely (already proven for workshop bookings via `workshop-realtime.js`'s exponential-backoff reconnect logic — the same module/pattern should be reused for vehicle/notes/lookup-table subscriptions rather than a new implementation).
15. Version conflicts do not silently overwrite changes (every new RPC must return `{ok: false, error: 'version_conflict'}` exactly like the existing workshop RPCs, and every UI call site must handle that response by refreshing rather than silently discarding the conflict).
16. The website does not fall back to stale local operational data after a database error — this is a genuinely new requirement not yet implemented anywhere in the codebase (the current app has no concept of "the DB is authoritative and a failed read should show an error state, not silently render whatever was last in localStorage") and needs explicit design/implementation, not just a test.

## 11. Overall risk summary

The single highest-risk item in this entire plan is the decomposition of `saveVehicleEdits()` (Stage 2C) — not because the destination schema is missing (it mostly is not) but because it is the one place where an incomplete field-by-field audit could silently drop functionality that currently works. Every other stage's risk is materially reduced by how much of the destination schema and RPC pattern already exists and has already been proven in this remediation phase's earlier stages (workshop bookings, account approval, RLS matrix, backup/restore).

The second highest risk is the browser-data importer (Stage 2E), specifically the "prevent an older browser import from overwriting newer database information" requirement (§8) — most of today's local data has no reliable per-field last-modified timestamp to compare against, which limits how automatically safe this can be made and increases how much must default to "flag as a conflict for manual review" rather than "safely auto-merge."

## 12. Explicit non-goals for this document

This document does not: write any migration SQL, write any RPC body, modify `app.js`, modify `workshop-planner.js`, create any new table, or run any command against staging beyond the read-only schema/code audit needed to write this plan. Per the instruction, implementation begins only after this plan and the accompanying inventory are reviewed and approved.
