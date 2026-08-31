# PDC Email AI Transaction Successor — authoritative STAGING architecture

Status: design authority; implementation must not proceed against an older contract.
Environment: STAGING only. Production is outside this specification.

This document is the authoritative architecture baseline for the successor. The
plan, runbooks, Intake UI and Recovery Pack commissioning material must agree
with it. It deliberately separates transport, interpretation, business rules,
taxonomy and Supabase action-contract releases so that any one can be replaced
without silently changing the others.

## Architecture decisions

1. **Transport is replaceable and preferably hosted.** The normal design is a
   hosted/server-side mailbox transport behind a provider-neutral adapter. It
   owns receipt delivery only; it never classifies work or performs a business
   write. The Windows monitor is a temporary, isolated rollback transport only
   while the hosted transport is unavailable or being proved. Windows is not a
   second business engine, not the target architecture and not an implicit
   fallback. Switching transport requires an explicit versioned deployment and
   must preserve the same source/attachment digests and idempotency keys.
2. **Sublet is evidence-gated.** No generic external/provider wording can create
   or move a Sublet booking. A Sublet action requires an explicit Job Card
   `SUBLET` instruction or explicit staff/provider/booking evidence, and must
   address one exact canonical booking/provider instance. Missing, conflicting
   or non-specific evidence produces an action disposition without a write.
3. **Evidence is conditional per action.** Job Card and attachment requirements
   are defined by the action matrix in `BUSINESS_RULES.md`; they are not a
   global gate. An absent attachment blocks only an action that requires that
   attachment. An action that does not require a Job Card must not invent one.
4. **Actions are independently disposed.** Every typed instruction has its own
   validation, evidence, command, readback, audit and terminal disposition.
   Supported domain atomic groups remain atomic, but a sibling action is never
   reported as successful merely because another action succeeded. Aggregate
   `PARTIAL_FAILURE` is used whenever requested actions differ in outcome.
5. **The AI planner is the normal engine.** The configured planner/model path is
   required for live interpretation. Deterministic logic is limited to fixtures,
   regression tests, contract validation and explicit fail-safe checks. It must
   never silently replace an unavailable or failed planner; planner/model outage
   becomes a typed retry, quarantine or blocked result with provenance.
6. **Every decision carries provenance.** Each action decision and terminal
   disposition records the planner version, model version, prompt version,
   business-rules/ruleset version, taxonomy version, evidence/source digest and
   action-contract version. Provenance is retained for `NOT_APPLICABLE`,
   `SUPERSEDED`, blocked and failed decisions as well as applied actions.
7. **Safety controls remain mandatory.** Dedicated authenticated non-
   Administrator runtime, no service-role runtime, no browser business writes,
   no direct table DML/arbitrary SQL, forced RLS, staging-sentinel and
   production-sentinel guards, immutable evidence, stable replay keys,
   independent readback, no automatic outbound email, quarantine and preserved
   rollback remain required controls.
8. **Recovery is clean-room portable.** A Recovery Pack is portable only when a
   fresh environment can use the immutable pack/source snapshot plus explicitly
   injected protected connector interfaces, without Hermes memory/cache,
   undocumented local files, a pre-existing Windows task or copied runtime
   state. Hosted transport is the portable path; the temporary Windows rollback
   is optional and must be independently gated.

## Layer 1 — evidence-only intake

`backend/pdc_email_ai_successor_intake.py` accepts RFC822/provider evidence through the replaceable hosted transport adapter, retains immutable source and attachment digests, records mailbox/message/thread/provider metadata and never classifies PDC work or performs a business write. The temporary Windows rollback adapter has the same contract and no additional authority.

## Layer 2 — Hermes/AI typed interpretation

`backend/pdc_email_ai_successor_planner.py` receives complete correspondence, bounded PDF extraction and authoritative vehicle context. The configured AI planner/model is the normal interpretation engine and emits only `pdc-email-ai-plan-v1`: one independently accounted instruction per vehicle/action, identity evidence, conditional evidence references, expected versions and explicit per-decision provenance. It cannot provide SQL, table names, RPC names or credentials. Deterministic code is test/fixture/validation/fail-safe support only and never silently takes over live interpretation.

## Layer 3 — canonical command boundary

`public.apply_pdc_email_ai_transaction_successor(jsonb)` is the only successor apply boundary. The authenticated dedicated runtime is checked first; Administrator/service-role/browser/direct-DML/arbitrary-SQL paths fail closed. Identity-to-vehicle binding, source receipt/digest, action-specific evidence gates, separately bound transport/prompt/business-rule/taxonomy/Supabase action-contract versions, action allow-list, stable action keys, locks and readback confirmation precede canonical RPC dispatch. Each action is audited and disposed independently.

## Layer 4 — independent authoritative readback

`backend/pdc_email_ai_successor_executor.py` calls the command once and separately reads the authoritative Board/read model. Expected and actual values, IDs, versions, operation/hour tuples, Parts, Sublet, location, lifecycle and revisions are compared. HTTP 200, `ok=true`, a receipt row or visual UI state is not proof.

## UI projection

The successor Intake UI is read-only and uses `get_pdc_email_ai_transaction_successor_inbox_v2(jsonb, integer)` with composite cursor `(sort_time, created_at, id)`. It renders one parent row per email and child vehicle/action results. Realtime is invalidation followed by authoritative refresh; stale generations are suppressed. Raw message bodies and secrets are excluded.

## Rollback

The hosted transport is the preferred lane. The existing Windows `.68/.69/.71`
transport lineage is retained only as a temporary rollback lane while hosted
transport commissioning is incomplete; it may be disabled/revoked without
changing business authority. Rollback preserves successor evidence and does not
delete receipts or rewrite migrations. Production is outside the pack.

## Concrete implementation delta

- Replace transport-specific assumptions in intake and commissioning with a
  provider-neutral hosted transport contract plus an explicitly named,
  time-bounded Windows rollback adapter.
- Add an action evidence matrix and enforce it before dispatch: Sublet evidence
  and exact-booking checks, conditional Job Card/attachment checks, and no
  cross-action borrowing of evidence.
- Make planner/model availability a required live gate. Mark deterministic
  interpreters as fixture/regression/validation/fail-safe only and emit an
  explicit `PLANNER_UNAVAILABLE` disposition when the normal engine cannot run.
- Carry per-action provenance and action-level `audit_events` data through the
  plan, command receipt, readback and AI Intake projection.
- Version and bind transport, planner/model, prompt, business rules/ruleset,
  taxonomy and Supabase action contract independently; reject mismatched
  combinations rather than selecting a silent compatibility path.
- Make Recovery Pack bootstrap depend only on its immutable contents and
  secure connector interfaces, with hosted transport first and Windows rollback
  optional.

## Architecture acceptance criteria

- A live STAGING decision cannot be produced without the normal configured AI
  planner/model provenance; deterministic code cannot silently replace it.
- A Sublet action without the required explicit evidence or exact canonical
  booking is recorded and not written.
- Job Card and attachment requirements are evaluated per action, and a missing
  required artifact does not suppress or falsely fail unrelated actions.
- Every requested action has exactly one terminal disposition, its own
  planner/model/prompt/ruleset/taxonomy/evidence provenance, action audit and
  authoritative before/requested/actual readback.
- Changing one version domain (transport, prompt, business rules/ruleset,
  taxonomy or Supabase action contract) is independently detectable and cannot
  silently reuse another domain's version.
- Hosted transport can be replaced without changing planner or business-action
  semantics; the Windows adapter is demonstrably temporary and rollback-only.
- A clean-room Recovery Pack run succeeds or fails closed using no hidden local
  dependency, while all retained safety controls and Production-untouched
  assertions remain true.
