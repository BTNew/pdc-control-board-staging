# PDC Email Monitor .44 execution/attachment compatibility successor 673

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and protected local staging runtime only.
Production: untouched.

## Outcome

The two post-preflight activation blockers are repaired without editing the
sealed `.44` release or its `CURRENT` pointer:

1. The external runtime adapter validates the complete seven-part MIME set and
   deterministically projects exactly four verified PDF business documents. The
   Job Card is selected only by the exact content hash
   `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`; all
   seven parts remain in the retained evidence projection.
2. Staging successor 673 adds the exact standard-authenticated actor branch to
   the existing server-side monitor scope. It grants only the required existing
   queue/claim/attachment/result/canonical-work and agentic execution RPCs to
   `authenticated`; server-side proof still requires the exact actor/email,
   approved importer role, active writer, exact gateway/release/source/manifest,
   commissioned planner/trust, staging sentinel, zero active mailboxes,
   disabled pilot and absent Production sentinel.

Wrong actors, wrong gateways, malformed claims, anon, service_role, direct
capability/selection-table access and malformed MIME/attachment sets fail
closed. No broad table DML or direct receipt access was granted.

## Exact source and installed artifacts

- Migration source:
  `supabase/staging_only/20260827106000_673_authenticated_monitor_execution_attachment_successor.sql`
- Migration SHA-256:
  `742f3517d85c14ae09de7ee489f039fa261c5895039940adde66e2e67ea3f1b1`
- Semantic successor: `673`; ledger version: `20260827106000`
- External adapter:
  `scripts/pdc_authenticated_monitor_runtime_adapter.py`
- Adapter SHA-256:
  `08e9a0dbca7640b93911fe397e3f9577b7f1e79bebc97c780efbe6aeb4a298e0`
- Installer:
  `scripts/install_pdc_authenticated_monitor_runtime_adapter.ps1`
- Installer SHA-256:
  `667bec3b867ade57425580793f17c09b7be3ba0775d65b0e297dfa38772f0df4`

Installed protected paths:

- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\pdc-authenticated-monitor-runtime-adapter.py`
- `C:\ProgramData\PDCMonitor\Staging\trust\2026.08.44\AUTHENTICATED_RUNTIME_ADAPTER_SHA256`

The installed adapter and its protected anchor both match
`08e9a0dbca7640b93911fe397e3f9577b7f1e79bebc97c780efbe6aeb4a298e0`.
The sealed `.44` `backend\imap_bridge.py` hash remains
`80d45bb7bde5e0b00fe73e5a54386ede07f7c44fbafcb9e3cc990cc501979248`, matching
the sealed release inventory. `CURRENT` remains `2026.08.44`.

## Staging RPC/control surface

The successor uses these existing RPC names with the exact authenticated scope:

- `enqueue_pdc_email_intake(jsonb,jsonb)`
- `claim_pdc_email_intake_batch(integer,text)`
- `record_pdc_email_monitor_cycle(text,text,text)`
- `heartbeat_pdc_email_intake_claim(uuid,uuid,text)`
- `get_pdc_monitor_intake_attachments(uuid,uuid,text)`
- `record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text)`
- `record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb)`
- `process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)`
- `authorize_pdc_uid514_retained_intake_257(uuid,integer)`
- `claim_pdc_uid514_recovery_257(text,integer)`
- `read_pdc_uid514_transaction_receipt_authenticated_672(integer)` remains the
  read-only pre-processing gate.
- Agentic execution: `read_pdc_agentic_email_context_502(jsonb)`,
  `record_pdc_agentic_email_plan_502(jsonb)`,
  `execute_pdc_agentic_email_action_502(jsonb)`,
  `pdc_agentic_apply_action_502(uuid)`,
  `read_pdc_agentic_email_vehicle_502(uuid)`,
  `append_pdc_agentic_email_action_audit_502(jsonb)`, and
  `finalize_pdc_agentic_email_plan_502(jsonb)`.

New internal scope: `pdc_monitor_authenticated_active_scope_673(text)`.
New rollback/disable RPC:
`admin_rollback_pdc_email_monitor_authenticated_execution_673(text)`.
The rollback disables only successor 673 and appends immutable history; it does
not rewrite 670/671/672, delete evidence, or enable any fallback.

New immutable/forced-RLS objects:

- `pdc_email_monitor_authenticated_execution_attachment_controls_673`
- `pdc_email_monitor_authenticated_execution_attachment_history_673`
- `pdc_uid514_attachment_selection_673`

The UID514 selection table is empty until the separately authorised future
UID514 runtime path runs; the real UID514 message was not processed here.

## Verification

- Contract suite: 5 passed, 0 failed.
- Live staging successor suite: 4 passed, 0 failed. It exercised standard
  authenticated cycle/claim calls in a rolled-back transaction, agentic guard
  reachability without mutation, wrong actor/role/gateway and malformed input,
  narrow privileges, forced RLS and repeated scope idempotence.
- Existing live 672 suite: 4 passed, 0 failed.
- Migration transaction rehearsal: full successor executed against staging and
  rolled back successfully before apply.
- Live staging apply: migration ledger contains 670, 671, 672 and
  `673_authenticated_monitor_execution_attachment_successor`; the live head is
  `20260827106000` (later unrelated 700-series history was preserved).
- Live post-readback: successor control enabled, MIME contract 7/4, exact
  planner/trust/source/manifest binding, active mailboxes 0, automatic pilot 0,
  Production sentinel absent, authenticated execution true, anon/service_role
  claim execution false, and direct authenticated control/selection reads false.
- Synthetic adapter rehearsal: returned seven retained parts, four business
  PDFs, the exact Job Card hash and stable PDF IDs; repeated enqueue simulation
  produced one stored effect.
- Installed adapter readback: protected file/anchor hashes match; sealed
  manifest hash unchanged; task `PDC-PMB-Email-Monitor-Staging` remains
  `Disabled` under `LOCAL SERVICE`.

No task enable/start, mailbox contact, UID514 processing, vehicle/work/receipt
mutation, evidence deletion, credential refresh/copy, or Production action was
performed by this repair. The exact hashes and RPC names above are the handoff
for pdc-emails.
