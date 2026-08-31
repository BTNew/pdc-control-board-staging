# PDC Email AI Transaction Successor — STAGING runbook

This runbook is self-contained for a fresh Hermes. It applies only to the
isolated successor worktree and STAGING project `cdsmnqxtyyoeoznmbidd`.

Production is prohibited. Do not use Production remotes, branches, data,
credentials, service role, Administrator runtime identity, browser writes or
outbound email.

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

## Four-layer operation

1. `pdc_email_ai_successor_intake.py` stores RFC822 bytes and original bounded
   attachments by digest and emits only evidence metadata. It has no PDC
   action code.
2. `pdc_email_ai_successor_planner.py` accepts complete correspondence,
   extracted PDF text and authoritative contexts and emits only the strict
   `pdc-email-ai-plan-v1` JSON contract.
3. The single SQL command RPC validates identity, source receipt/digest,
   versions, expected vehicle versions and stable action keys, then dispatches
   only to fixed existing canonical RPCs. Unsupported role/capability paths
   become `BLOCKED_EXACT_REASON`.
4. `pdc_email_ai_successor_executor.py` calls the command once and separately
   calls `get_pdc_email_vehicle_location_snapshot()`. It does not accept HTTP
   success, `ok=true`, a receipt, or UI appearance as readback proof.

## Staging preflight

Use the existing protected/DPAPI staging connector. Pass the exact STAGING
Supabase URL through the connector; never put its token, password, DSN or
mailbox secret in this repository. The migration itself requires:

- the STAGING sentinel for project `cdsmnqxtyyoeoznmbidd`;
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
Administrator token or arbitrary SQL capability.

Do not enable the existing Email Monitor task. The successor transport remains
`disabled` until the full staging gates pass.

## Apply and health proof

Apply the migration once through the protected staging migration mechanism and
read back its catalog entry, function ACLs, forced-RLS tables and staging
sentinel. Then provision the successor identity through the same protected
mechanism. Use the authenticated health RPC:

`public.get_pdc_email_ai_successor_health()`

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
disposition and duration.

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
live sibling receipts continue.

## Disable and rollback

To disable the successor, stop its isolated transport, revoke its authenticated
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

## Soak gate

No Production recommendation is part of this artifact. Before any future
Production discussion, staging must prove 12 consecutive representative natural
cycles and a 24-hour staging soak, including duplicates, multi-action/multi-
vehicle mail, pending work, readback parity and deliberate restart recovery.
