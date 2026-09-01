# PDC Email AI Transaction Successor — STAGING runbook

This runbook is self-contained for a fresh Hermes. It applies only to the
isolated successor worktree and STAGING project `cdsmnqxtyyoeoznmbidd`.

Production is prohibited. Do not use Production remotes, branches, data,
credentials, service role, Administrator runtime identity, browser writes or
outbound email.

`recovery-pack/ARCHITECTURE.md` is the authoritative design baseline. This
runbook is STAGING design only and must not be used to revive a superseded
transport, planner fallback or global evidence gate.

## Artifact

Worktree:
`C:/Users/nwmgr/HermesWorkspaces/development/pdc-email-ai-transaction-successor`

Branch:
`feature/pdc-email-ai-transaction-successor`

Plan:
`docs/PDC-EMAIL-AI-TRANSACTION-SUCCESSOR-PLAN.md`

Manifest:
`runtime/pdc-email-ai-successor-manifest.json`

Migration:
`supabase/staging_only/20260831300000_pdc_email_ai_transaction_successor.sql`

Forward repair migration:
`supabase/staging_only/20260831320000_pdc_email_ai_transaction_successor_contract_repair.sql`

Typed least-authority action surface (guarded to live head
`20260901010000 / latest100_attachment_work_receipt_successor`):
`supabase/staging_only/20260901020000_pdc_email_ai_typed_action_surface.sql`

Append-only strict boundary repairs:
`supabase/staging_only/20260901030000_pdc_email_ai_typed_action_boundary_repair_20260901.sql`
`supabase/staging_only/20260901040000_pdc_email_ai_typed_action_validator_binding_20260901.sql`
`supabase/staging_only/20260901050000_pdc_email_ai_typed_action_v2_contract_binding_20260901.sql`

The 0500 repair is the current applied STAGING head. It binds the flattened
v2 planner envelope to the strict RPC and must remain append-only; the 0200
through 0400 migrations are retained as rollback history.

Successor inbox/read hardening migration:
`supabase/staging_only/20260831330000_pdc_email_ai_successor_inbox_read_projection.sql`
`supabase/staging_only/20260831340000_pdc_email_ai_successor_command_read_hardening.sql`

The staging website mounts `pdc-email-ai-successor-inbox.js` as a read-only
chronological email/vehicle projection. It uses the v2 composite-cursor RPC
`get_pdc_email_ai_transaction_successor_inbox_v2` and the successor Realtime
revision table. The legacy `.68` review surface remains hidden and untouched.

## Four-layer operation

1. The hosted, provider-neutral transport stores RFC822 bytes and original
   bounded attachments by digest and emits only evidence metadata. It has no
   PDC action code. The Windows monitor is an explicitly temporary rollback
   transport only, with the same evidence-only contract.
2. `pdc_email_ai_successor_planner.py` accepts complete correspondence,
   extracted PDF text and authoritative contexts and emits only the strict
   `pdc-email-ai-plan-v1` JSON contract. The configured AI planner/model is the
   normal engine; deterministic code is limited to fixtures, regression,
   validation and fail-safe checks and never silently replaces the planner.
3. The typed SQL action-surface RPC validates identity-to-vehicle binding, source receipt/digest,
   action-specific Job Card/attachment/Sublet evidence, independently bound
   transport/planner/model/prompt/business-rule/ruleset/taxonomy/Supabase
   action-contract versions, expected vehicle versions and stable action keys,
   then dispatches only to fixed existing canonical RPCs. Unsupported
   role/capability paths become `BLOCKED_EXACT_REASON`.
4. `pdc_email_ai_successor_executor.py` calls the command once and separately
   calls `get_pdc_email_vehicle_location_snapshot()`. It does not accept HTTP
   success, `ok=true`, a receipt, or UI appearance as readback proof. Every
   action receives its own audit record, readback and terminal disposition.

## Staging preflight

Use the protected STAGING connector. The preferred transport is the hosted
provider-neutral adapter; use the Windows DPAPI monitor only when the explicit
temporary rollback gate is active. Pass the exact STAGING Supabase URL through
the connector; never put its token, password, DSN or mailbox secret in this
repository. The migration itself requires:

- the STAGING sentinel for project `cdsmnqxtyyoeoznmbidd`;
- an independently versioned transport binding and a configured AI planner/model binding;
- live migration predecessor `20260831290000 / 863_exact_retry_after_storage_repair`;
- no Production sentinel;
- no existing successor version `20260831300000`;
- existing canonical read model and Parts ETA RPC.

If the predecessor/head guard fails, stop the migration and record the exact
sanitized code. Do not edit the current Email Monitor repair migration or
runtime to make the guard pass.

## Secretless identity provisioning

The runtime identity is an authenticated STAGING user recorded by an owner-only
provisioning path in `pdc_email_ai_successor_runtime_identities`. Its purpose is
exactly `pdc_email_ai_transaction_successor`, environment is `staging`, and it
must not have an Administrator role. The row binds the gateway, transport,
model, prompt, taxonomy, rules and action versions.

Provisioning is an installation action, not runtime authority. The runtime
must receive only an authenticated token for that identity through the approved
connector. It must never receive a service-role key, database password,
Administrator token or arbitrary SQL capability. The binding must carry
independent transport, planner/model, prompt, business-rule/ruleset, taxonomy
and Supabase action-contract versions.

Do not enable the existing Email Monitor task. The preferred hosted successor
transport remains disabled until the full staging gates pass. The Windows
transport may be enabled only as the named temporary rollback lane, never as an
implicit AI or business-rule fallback.

## Apply and health proof

Apply the migration once through the protected staging migration mechanism and
read back its catalog entry, function ACLs, forced-RLS tables and staging
sentinel. Then provision the successor identity through the same protected
mechanism. Use the authenticated health RPC:

`public.get_pdc_email_ai_successor_health()` and the read-only
`public.get_pdc_email_ai_successor_action_contract_20260901()`

The health result must show `production_writes=false`, `outbound_email=false`,
`historical_lane_isolated=true` and `live_lane_continues=true`. A source file,
HTTP 200, health response or Pages asset is not database proof unless the
catalog/function/read-model result is read back from STAGING.

## Acceptance order

Run the local suite first:

`python -m unittest -v tests/test_pdc_email_ai_successor_*.py`

Run the SQL parser and project regression suite:

`python -c "from pathlib import Path; from pglast import parse_sql; print(len(parse_sql(Path('supabase/staging_only/20260831300000_pdc_email_ai_transaction_successor.sql').read_text())))"`

`npm run test`

`npm run check`

Then run only controlled STAGING fixtures through the authenticated successor
identity. Every run must retain a source receipt, plan/action versions, action
keys, before/requested/result values, canonical RPC, readback, retry count,
disposition, per-action audit event and duration. Every action must include
planner/model/prompt/business-rule/ruleset/taxonomy and source/evidence digest
provenance, including blocked and not-applicable decisions.

Required sequence:

- valid Navision/backend activation;
- missing backend blocked, then retry after later Navision without rebuilding
  the email;
- Parts complete and Parts ETA-only;
- explicit Sublet create/update evidence, then 10→15 September update with one
  booking;
- complete Job Card PDF with all OP lines and explicit zero hours;
- revised/disregarded Job Card supersession;
- one email with at least three actions and one email with two vehicles;
- mixed-result multi-action email proving independent dispositions, action-level
  AI Intake audit and aggregate `PARTIAL_FAILURE`;
- hostile/unknown action, ambiguous identity/date and generic external wording;
- exact replay and duplicate attachment/graph ID;
- malformed historical quarantine while an unrelated live sibling completes;
- stale vehicle/booking state, expired token, mailbox/AI/Supabase outage,
  revoked permission, process kill/restart, transaction failure and repeated
  schedule;
- deliberate GVM/Tyre wording and readback parity;
- two natural cycles with real pending STAGING work.

A requested plan is complete only when every instruction has one terminal
status: `APPLIED_AND_VERIFIED`, `ALREADY_CORRECT`, `SUPERSEDED`,
`NOT_APPLICABLE`, `BLOCKED_EXACT_REASON`, `GENUINELY_AMBIGUOUS` or
`FAILED_QUEUED_RETRY`. Any missing/failed action is typed `PARTIAL_FAILURE`;
never report full success.

## Retry and quarantine

Retry only bounded transient transport/token/provider failures, maximum three
attempts with 1/2/4 second backoff. Deterministic validation, permission,
identity, business-rule and readback mismatches do not retry forever. Repeated
failure is quarantined with its immutable reason and surfaced through health;
failure is quarantined with its immutable reason and surfaced through health;
live sibling receipts continue. AI planner/model outage is never silently
handled by deterministic interpretation: it is an explicit
`FAILED_QUEUED_RETRY`, quarantine or `BLOCKED_EXACT_REASON` decision with
provenance.

## Disable and rollback

To disable the successor, stop its isolated hosted transport (or the explicitly
temporary Windows rollback transport), revoke its authenticated
function execution through the protected STAGING owner path, and mark its
runtime identity inactive/revoked. Do not change the current repair task or
runtime. Preserve every successor receipt and source byte.

Rollback means returning to the preserved current Email Monitor repair lane,
not deleting successor tables or receipts. If a forward repair is required,
create a new append-only STAGING migration with an exact predecessor guard;
do not rewrite this migration or historical evidence. Re-enable only after a
new focused contract, acceptance replay and readback proof.

## Fault disposition table

| Fault | Required disposition |
|---|---|
| duplicate email/attachment/graph ID | exact replay/duplicate receipt, zero duplicate effect |
| KeyAlreadyExists | idempotent replay, no new object/effect |
| unsafe attachment path | quarantine attachment, retain email/source digest |
| expired token/outage | bounded `FAILED_QUEUED_RETRY`, then quarantine |
| one permission revoked | affected action blocked/retry; unrelated sibling continues |
| process killed mid-run | restart from immutable source/action key, zero duplicates |
| transaction failure | no partial atomic group; receipt records retry/failure |
| stale state | `BLOCKED_EXACT_REASON` or replan/review, never overwrite |
| missing backend/ambiguous identity | fail closed; no activation or cross-stock effect |
| legacy/historical malformed row | historical quarantine only; live lane continues |
| repeated schedule | canonical booking key/version prevents duplicate |
| one action fails in multi-action mail | per-action result and `PARTIAL_FAILURE` |
| GVM wording includes tyres | controlled HOIST taxonomy, never TYRE-only inference |

## Action evidence matrix

Apply these gates per action, not per email or transaction:

| Action family | Job Card | Attachment | Required evidence |
|---|---|---|---|
| Activation/location | No | No | Unambiguous identity and explicit authoritative source instruction |
| Workgroup requirement | Only for Job Card-derived work | Only when Job Card is the source | Explicit work signal; no GVM/Tyre inference |
| Operation/Job Card upsert | Yes | Yes, valid Job Card attachment | Complete operation number, description and hours, including zero |
| Parts ETA/order/complete | No | No | Explicit Parts evidence; ETA-only cannot change completion/order |
| Notes | No | No | Retained source text evidence |
| Sublet booking | Only when Job Card is the source | Only when Job Card is the source | Explicit Job Card `SUBLET` or explicit staff/provider/booking evidence and one exact canonical booking/provider instance |
| RFT transfer/collect | No | No | Explicit lifecycle instruction plus canonical completion/Parts gates |

Generic Sublet wording, approximate booking identity or insufficient attachment
evidence is recorded as an action-level block and never creates or moves a
booking. A missing artifact blocks only the action that requires it; unrelated
actions continue independently.

## Soak gate

No Production recommendation is part of this artifact. Before any future
Production discussion, staging must prove 12 consecutive representative natural
cycles and a 24-hour staging soak, including duplicates, multi-action/multi-
vehicle mail, pending work, readback parity and deliberate restart recovery.

## Concrete implementation delta and acceptance criteria

The next implementation must:

- use a replaceable hosted transport contract as the normal path and label
  Windows `.68/.69/.71` as temporary rollback-only;
- enforce the action matrix and evidence-gated Sublet without a global Job Card
  or attachment requirement;
- require the AI planner/model for live interpretation, with deterministic
  logic limited to fixtures/regression/validation/fail-safe and no silent
  fallback;
- persist explicit per-action planner/model/prompt/business-rule/ruleset/
  taxonomy/transport/action-contract provenance and action-level `audit_events`;
- keep the six relevant version domains independent and fail closed on mismatch;
- make clean-room Recovery Pack use independent of Hermes state and old Windows
  tasks.

Acceptance is met only when a mixed-result email demonstrates independent
terminal dispositions and audit/readback per action, Sublet without evidence
cannot write, planner outage is visible, transport replacement preserves
semantics, all safety controls remain true, and a clean-room run succeeds or
fails closed without Production contact.
