# AI Auditor implementation-ready gap report

Source baseline reviewed: `6132e8571a054af7f66d691b3af26ae773ca9517`; this report is committed with the regression/security candidate and must be rebound to that final exact SHA after the final review commit.

Scope: source inspection only. No profile, mailbox, gateway, credential, staging database, staging record, Pages, migration or production access was used.

## Current implementation

The source already contains a substantial unapplied staging design:

- `supabase/staging_only/225_ai_auditor_telegram_plans.sql`
- `supabase/staging_only/226_ai_auditor_atomic_apply_undo.sql`
- `supabase/staging_only/227_ai_auditor_versioned_rules.sql`
- `supabase/staging_only/228_proven_duplicate_source_evidence.sql`
- `supabase/staging_only/229_auditor_realtime_publication.sql`
- `supabase/staging_only/230_auditor_authorization_hardening.sql`
- `supabase/staging_only/231_auditor_delivery_registry_reconciliation.sql`
- `backend/pdc_auditor_telegram_runtime.py`

This is **not deployment-ready**. The installation handoff explicitly blocks activation until a signed gateway envelope, owning-profile wrapper and real staging acceptance exist.

## Requirement-by-requirement gaps

| Requirement | Present source | Gap / implementation-ready next step |
|---|---|---|
| Scoped Auditor service identity | Migration 225 defines an ordinary authenticated Viewer identity scoped to staging/dealer and excludes `service_role`; migrations 230–231 harden authorization/delivery. | Remove source-time identity enrolment assumptions from migration 225 and provision via a separate authorised ceremony. Complete gateway signature verification before exposing planning/apply RPCs. Keep identity separate from Administrator, booking and Monitor identities. |
| Operation-line read/write RPCs | Read projections exist; 225 plans against canonical operation lines; 226 writes adjustment overlays rather than source rows. | Define a single documented operation-line mutation contract that supports every required edit shape and returns exact effective-line before/after state. No direct source-row update/delete grants. |
| Add operations | Not represented by the controlled 225 plan-item actions (`edit`, `delete`, `move`). Older generic batch RPC source in migrations 176/178/189/201 names add/edit/delete/split/combine/reorder/move, but migration 225 revokes that authenticated path and those labels do not provide the required typed controlled semantics. | Add a controlled append action with server-generated stable operation identity, bounded required fields, source/instruction evidence and idempotent reservation. Do not re-enable the older generic RPCs. |
| Edit operations | Supported for department/hours overlays. | Extend exact validation to description/code only if explicitly authorised; preserve immutable source facts and distinguish manual-protected fields. |
| Split operations | Missing. | Add a typed split plan whose children preserve parent/source evidence, quantities/hours conservation rules, stable ordering and atomic receipt. |
| Combine operations | Missing. | Add a typed combine plan requiring one vehicle/job-card scope, explicit survivor, exact source set, hours policy and complete supersession history. |
| Reorder operations | Missing. | Add bounded per-vehicle/job-card sequence positions, uniqueness and deterministic reindexing; include full order in intent hash and receipt. |
| Remove duplicates | Implemented narrowly for duplicate bullbars and protected duplicate evidence. | Generalise only through deterministic duplicate families with exact survivor selection. Ambiguity/manual/completed rows must remain review-only. |
| Department corrections | Present through `move`/`line_department` and rule-driven intended department. | Add exhaustive department allowlist parity and contract tests for all stations; reject unsupported Sublet/Parts/booking semantics. |
| Estimated-hours corrections | Present through `edit`, `stock_hours`, `gvm_hours`, quarter-hour validation and overlays. | Document precedence between authenticated source, manual later correction and Auditor overlay; add aggregate recalculation assertions. |
| Batch Review and Apply | 225 supports review/apply plans up to 250 items; 226 applies one immutable plan atomically. | There is no browser implementation for 225/226 Review/Apply. The Python adapter immediately applies a successful non-review plan, so a distinct explicit confirmation step is absent. Add confirmation showing count, ambiguity/exclusion totals and plan hash; Apply must require that exact reviewed plan and unchanged operational revision. |
| Protected manual values | 225 has manual/completed protection and exclusion codes; 226 uses overlays and conflict-preserving Undo. | Formalise field-level protection for manual description, department, hours, completion and subsequent staff edits; add negative tests for each mutation shape. |
| Complete before/after history | 226 stores plan evidence and adjustment before/after rows with apply/rollback receipts. | For add/split/combine/reorder, receipt must capture the complete ordered effective operation set, required-work projection and aggregate hours before/after—not only per-overlay rows. |
| Instruction evidence | Telegram IDs, exact instruction text/hash and immutable plan/run evidence exist. | Mandatory gateway-signed envelope remains missing. Persist verified sender/chat/message/update, gateway instance, bot identity, timestamps, nonce/key ID and canonical signature validation. |
| Recalculate hours and required-work identifiers | 226 recalculates non-completed `vehicle_work_items` from effective lines. | Add an authoritative aggregate-hours projection/readback and verify exact required-work identifier set after every apply and Undo. Never change completed rows. |
| Realtime publication | 229 publishes `vehicle_workshop_line_adjustments` and `pdc_auditor_workshop_revisions`. | **Current blocker:** the browser still subscribes to the older `pdc_auditor_revision` table, not migration 229's run-revision publication. Wire the operation-control consumer to the new publication and prove two authenticated website sessions invalidate/refetch once per whole run; do not publish secret instruction content. |
| Whole-run Undo | **Partial:** 226 resolves the last run and records per-change rollback audit, but later conflicts can yield `telegram_run_partially_rolled_back`: unaffected changes are restored while conflicts are preserved. This is safe conflict-preserving rollback, not strict all-or-nothing whole-run Undo. | Decide and document whether strict atomic whole-run Undo is required. Extend the chosen semantics to all new action types and complete ordered-set/aggregate state. Exact replay must be zero-add and later manual changes must follow the approved conflict policy. |
| Prevent vehicle deletion | Current apply design changes only line-adjustment overlays and required-work projection. | Add static and database postconditions proving no Auditor RPC can insert/update/delete vehicles or invoke lifecycle/delete RPCs. |
| Prevent unauthorised booking changes | Current 225–226 design does not write booking tables. Administrator migration 244 separately denies Auditor identities. | Add explicit forbidden-call inventory tests for all booking/scheduling RPCs and ensure Auditor functions have no EXECUTE path to private legacy functions. |
| Natural-language routing | Python adapter has a bounded grammar for review, duplicate bullbars, GVM hours, tank department, stock hours, line department, rules, Apply matching and Undo. | Add typed grammar/context for add/edit/split/combine/reorder/general duplicate removal. Clarify all ambiguous references; never infer vehicle/line identity broadly. Gateway authenticity remains blocking. |

## Proposed source workstreams

1. **Schema/RPC extension (new append-only migration, not applied):** typed `add`, `split`, `combine`, `reorder`, generalized `remove_duplicate`; effective ordered-set receipts; exact aggregate hours and required-work readback.
2. **Protection closure:** field-level manual/completed protection matrix; forbidden vehicle/booking mutation postconditions; service identity provision moved out of source-time enrolment.
3. **Gateway authenticity:** signed canonical delivery envelope and replay registry, implemented only by the owning `work-receipting` profile.
4. **Runtime grammar:** typed commands and clarification paths for every new action; exact context binding.
5. **Acceptance:** focused static/unit tests, rollback-only database rehearsals, real scoped identity denials, two-session Realtime, whole-run Apply/Undo/replay and exact-SHA independent review.

## Implementation status

- Existing 225–231 source: **substantial partial implementation**.
- Missing operation shapes and complete ordered-set history: **not implemented**.
- Gateway-signature boundary: **not implemented; activation blocker**. Current 225/226/runtime evidence contains sender/chat/message/update/bot/text/hash only; it lacks gateway instance, immutable delivery UUID, key ID/nonce, verified timestamps and a validated canonical signature.
- Realtime operation-control consumer: **not implemented; activation blocker** because the browser listens to the old Stage A revision table.
- Separate Apply confirmation UX: **not implemented**; non-review runtime commands currently plan and immediately call Apply.
- Migrations 225–231 lack focused SQL-contract and database-execution tests; existing runtime/Stage-A tests do not prove installation, scoped denials, database Apply/Undo, two-session Realtime or booking/vehicle postconditions.
- Administrator closure migration: **drafted as append-only migration 251 with a focused static contract; not applied**. It closes the current and retained pre-116 cascade-move signatures plus all other legacy scheduling/move/resize/bay-change RPCs. The separate Auditor add/split/combine/reorder schema still requires a later independently reviewed migration beyond 251.
- Deployment/activation: **not performed and not authorised**.
