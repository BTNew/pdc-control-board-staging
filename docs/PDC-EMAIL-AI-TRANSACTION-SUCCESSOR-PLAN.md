# PDC Email AI Transaction Successor — STAGING plan

Status: UI/read projection, staging Pages deployment and live browser/read contract proven; runtime identity commissioning and natural-cycle acceptance remain blocked on protected owner provisioning
Environment: STAGING only
Dashboard: `20260831_095314_64feeb`
Production: prohibited and not contacted
Current repair lane: preserved; no files, task, runtime, mailbox flags, migrations, or worker changed

## 0. Baseline and boundary

The isolated worktree is:

`C:/Users/nwmgr/HermesWorkspaces/development/pdc-email-ai-transaction-successor`

Branch:

`feature/pdc-email-ai-transaction-successor`

Source baseline:

`87224a2e` — the latest committed website-development source. The parent worktree contains unrelated dirty and untracked Email Monitor repair work. This worktree was created from the committed tree, not copied from that dirty worktree.

No source or object from 863 is copied or rewritten; the new migration only requires the observed 863 ledger entry. The current repair runtime remains the rollback reference; this successor will not edit or enable its scheduled task, migrations, mailbox flags, or worker.

## 1. Grounded current map

### Current intake and interpretation

- `backend/imap_bridge.py:2-15, 251-292, 312-360` reads IMAP evidence, hashes the RFC822 source, retains raw `.eml`, stores bounded attachments, captures thread/provider/authentication metadata, and can mark messages seen. It is not an acceptable business command authority.
- `backend/email_intake_processor.py:2-9, 412+` extracts body/PDF/office/image text and currently mixes extraction, classification and downstream processing. Its classifiers include a known unsafe broad `HOIST`/GVM and `TYRE` overlap that the successor must replace with a versioned taxonomy.
- `backend/pdc_email_communication_parser.py:1-7, 140-215` is a conservative deterministic parser for a small communication vocabulary, but it is single-vehicle and cannot be the complete multi-action/multi-vehicle successor contract.
- `backend/pdc_active_semantic_planner.py:1-8, 51-174` demonstrates the required direction: authoritative contexts are inputs, unknown/uncertain clauses become `REVIEW_REQUIRED`/`NOT_APPLICABLE`, and the planner emits actions rather than SQL. It is current repair-lane material and will not be modified or imported as a runtime dependency.

### Existing canonical backend actions

The successor must call/reconcile these existing safe domain boundaries rather than reproduce their semantics:

- Activation and identity: `public.import_pdc_authenticated_vehicle_email(...)` from staging migrations 066/096/145, with Stock as primary identity, Navision/backend linkage and duplicate/source receipt guards.
- Read model: `public.get_pdc_email_vehicle_location_snapshot()` from migrations 066/073/093/096/097/099/104/105/107/109/110 and later successors. It returns revision, canonical vehicles, work items, operation lines, Parts and Sublet projection.
- Parts: `public.update_pdc_parts_eta(uuid, integer, date)` in 073/110; `public.mark_pdc_parts_ordered(uuid, integer)` in 091; `public.set_pdc_vehicle_work_states(uuid, integer, jsonb)` in 142 for the complete tri-state map. The successor will not direct-write Parts tables.
- Work/operations: `public.import_pdc_authenticated_email_operations(...)` in 093 and the later hours-aware canonical operation importer. Job Card attachment adapters 159/161 preserve source operation numbers, evidence coordinates and explicit zero hours; they never create bookings or silently complete work.
- Workshop planning: `public.schedule_vehicle_work(...)`, `public.move_workshop_booking(...)`, and `public.cascade_workshop_schedule(...)` in 077, with the authoritative eligibility, minimum 60-minute duration, overlap, calendar and Parts gates.
- Sublet: `public.update_pdc_sublet_booking(...)` and the later multi-provider instance functions in 168/171. A provider email may update an existing exact booking only; generic external wording cannot create one.
- Lifecycle: `public.qc_complete_vehicle(...)`, `public.rft_transfer_vehicle(...)`, `public.rft_collect_vehicle(...)`, and `public.qc_signoff_to_rft(...)` in 070 and later canonical lifecycle successors. Existing RFT gates and collected-vehicle protection remain authoritative.
- Realtime/readback: `pdc_email_vehicle_revision`, `workshop_bump_revision()`, `get_pdc_email_monitor_status()`, and the authenticated Board snapshot are readback surfaces, not proof by themselves. The successor must compare expected versus actual state after every applied action.
- Evidence/history: existing `ai_email_intake`, `ai_email_attachments`, `pdc_email_source_claims`, canonical import/operation/Job Card/communication receipts and `audit_events` are retained. Historical rows are evidence and compatibility input, not the live hot path.

### Established business rules to preserve

`BUSINESS_RULES.md:10-33, 36-47, 49-73, 82-111` requires Stock-first identity, no ambiguous alias choice, Navision/backend before activation, PMB/YH/RFT location protection, no automatic bay assignment, atomic workshop scheduling and minimum duration, Parts gating, and protected RFT/Completed state. Migrations 145, 159, 160, 168 and 142 add exact receipt, attachment, operation, Sublet and work-state boundaries. Current staging handoffs add:

- Kewdale ETA/Sub Location controls location except OD; used/non-Broome-Pilbara/other-franchise defaults to YH.
- Delivered-at-Dealer and seven applicable Navision omissions leave active/backend scope while retaining history.
- Sublet requires explicit Job Card SUBLET or explicit staff/provider/booking evidence and updates one existing canonical booking.
- Job Card operation source numbers, complete descriptions and explicit zero hours are authoritative; GVM cannot be inferred as Tyres.
- Revised/disregarded/cancelled/moved/no-longer-required instructions supersede earlier evidence without deleting history.

## 2. Proposed four-layer architecture

### Layer 1 — Evidence-only receipt/intake

`backend/pdc_email_ai_successor_intake.py` will provide a narrow, deterministic intake adapter:

- consume RFC822/hosted provider payloads without PDC classification;
- retain immutable original email bytes and every bounded original attachment under content-addressed paths;
- produce one receipt containing receive time, mailbox/message/thread IDs, sender/authentication, attachment metadata, source digest, evidence digest and transport state;
- use at-least-once transport with bounded exponential retry and a stable `mailbox/message/source-digest` key;
- prefer a hosted/server-side Edge Function only when the staging connector is available; otherwise the tiny local poller remains disabled-by-default and has no business RPC;
- historical lane uses a separate receipt namespace/quarantine and cannot block live intake.

### Layer 2 — AI interpretation

`backend/pdc_email_ai_successor_planner.py` will expose a model adapter boundary plus a deterministic staging reference interpreter. Input is complete correspondence, extracted PDF text, attachment identity/evidence, current authoritative identity and current Board/backend state. Output is only the strict typed plan in `backend/pdc_email_ai_successor_contract.py`.

The plan contains one independently accounted instruction per vehicle/action, source evidence references, identity proof, expected state/version, model/prompt/taxonomy/rule versions and no SQL/table/RPC names supplied by the model. Unknown actions, GVM/Tyre ambiguity, missing dates, conflicting identity, missing backend and generic Sublet wording fail closed.

### Layer 3 — Validation and canonical command

Add one staging-only transactional RPC:

`public.apply_pdc_email_ai_transaction_successor(jsonb)`

The caller is a dedicated authenticated staging runtime identity, never service role, Administrator, browser, direct table DML or arbitrary SQL. The RPC will:

1. verify staging sentinel, runtime identity, release/action/rule versions and immutable source receipt/digest;
2. lock and re-read each authoritative vehicle/backend/Board row and reject stale or conflicting state;
3. validate the complete typed plan before the first domain write;
4. dispatch only to an internal fixed allow-list of existing canonical action functions;
5. use stable per-email/per-action keys over mailbox/message/digest/vehicle/action/payload for replay protection;
6. apply an atomic action group where the canonical function supports it; otherwise return a typed per-action result and do not claim whole-plan success;
7. write immutable plan/action/verification receipts and audit metadata;
8. return every requested action result plus complete resulting authoritative state.

All detected instructions end in exactly one of: `APPLIED_AND_VERIFIED`, `ALREADY_CORRECT`, `SUPERSEDED`, `NOT_APPLICABLE`, `BLOCKED_EXACT_REASON`, `GENUINELY_AMBIGUOUS`, `FAILED_QUEUED_RETRY`. A plan with any non-success action is `PARTIAL_FAILURE`, never full success.

### Layer 4 — authoritative readback/confirmation

`backend/pdc_email_ai_successor_executor.py` will call only the single command RPC, then validate its returned state and independently call the authenticated Board/read-model RPC. It will compare expected fields, IDs, versions, booking cardinality, operation/hour tuples, Parts state, location/lifecycle and revision. HTTP 200, `ok=true`, a receipt row or UI appearance is insufficient without parity.

## 3. Compatibility and versioning

Retain the current Email Monitor repair lane and all historical evidence/receipts as rollback evidence. Do not reuse its task or processor.

Use independent version fields:

- `transport_release_version`: stable evidence transport/install bytes;
- `model_version` and `prompt_version`: interpretation;
- `taxonomy_version` and `rule_version`: classification/business rules;
- `action_contract_version` and `supabase_action_version`: command/RPC contract;
- `receipt_schema_version`: immutable evidence/decision records.

Rule/taxonomy corrections create a permanent fixture, update the rule version, replay/correct only affected STAGING evidence, and create an audit receipt. They do not rebuild Windows transport.

## 4. TDD checkpoints and acceptance matrix

Checkpoint A — strict contract and evidence receipt red/green:
- complete correspondence accounting;
- raw source/attachment digest and immutable path;
- duplicate attachment/unsafe path/KeyAlreadyExists/restart replay;
- hosted outage and bounded retry.

Checkpoint B — planner red/green:
- one email with three actions;
- one email with two vehicles;
- hostile/unknown action rejection;
- ambiguous identity/date and explicit zero-hour preservation;
- GVM taxonomy and generic Sublet rejection;
- revised/disregarded supersession and old-email non-reopen.

Checkpoint C — command/RPC contract red/green:
- runtime identity and staging-only guards;
- no service-role/Admin/browser/direct-table/arbitrary SQL authority;
- stable action keys, exact replay and duplicate graph attachment protection;
- atomic all-or-nothing groups, typed partial failure, stale-state replan;
- activation/backend, Parts, operation, booking, RFT/Collected and notes paths.

Checkpoint D — live STAGING acceptance, each with receipt/readback and no Production effect:
- valid backend activation and missing-backend fail-closed/retry after Navision;
- Parts complete and Parts ETA only;
- explicit Sublet create/update, 10→15 September move with one booking;
- Job Card with all valid OPs/hours including zero;
- revised Job Card supersession;
- malformed historical quarantine while live sibling continues;
- repeated schedule, one failing action in multi-action mail, transaction failure;
- expired token, mailbox/AI/Supabase outage, one RPC permission revoked, process kill/restart;
- readback parity, live Board parity, two natural cycles with real pending staging work.

For every fault: no duplicate effect, no loss, no Production contact, complete immutable disposition, correct bounded retry/quarantine, and live siblings continue.

## 5. Cutover and rollback

1. Map and freeze current writes/layers; do not disable the old business processor yet.
2. Run shadow comparison on synthetic and safe STAGING correspondence only.
3. Apply the successor migration and provision secretless runtime configuration through the staging connector.
4. Run replay/restart/fault matrix and two natural cycles.
5. Disable the old business processor only after all acceptance and readback gates pass; retain its rollback/disable path through soak.
6. Require 12 consecutive representative natural STAGING cycles and a 24-hour STAGING soak before any Production recommendation. This task contains no Production recommendation or action.

## 6. Deliverables

- Architecture/plan, current/proposed maps, retained/removed compatibility layers.
- Strict contract, intake/planner/validator/executor code and tests.
- Append-only STAGING migration/RPC, RLS/grants, immutable receipts and readback.
- Versioned prompt/rule/taxonomy/action manifests and permanent fixtures.
- Secretless provisioning, install/recovery, health check, fault runbook and rollback/disable instructions.
- Synthetic and safe STAGING acceptance evidence with cycle/failure/recovery counts.
- Staging source branch/commit, Pages/live asset proof where applicable, live RPC/readback proof, and explicit Production-untouched statement.
- Residual Hermes dependencies stated plainly; no hidden-memory dependency.
