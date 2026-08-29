# PDC-EMAIL frozen historical Apply handoff — 788 canonical digest

Date: 2026-08-30
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Production: prohibited and not contacted
Outbound email: prohibited and not sent

## Frozen input — unchanged

- Source artifact: `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-778-rows.json`
- Folder: `INBOX`
- UIDVALIDITY: `1`
- High-water UID: `685`
- Messages accounted: `669/669`
- Attachments accounted: `2,305`
- Exact authorized rows: `15`
- Exact Job Card children: `3`
- Frozen manifest SHA-256: `aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018`
- Selected frozen UIDs: `1:21, 1:22, 1:23, 1:26, 1:40, 1:57, 1:85, 1:93, 1:95, 1:96, 1:133, 1:134, 1:137, 1:168, 1:172`
- New outbox path verified absent before handoff: `historical-788-resume-outbox.sqlite3`
- Do not rescan IMAP, reset UIDs, reuse a failed outbox, alter flags, or enable the PT5M task.

## Website/staging gate

- Migration head: `20260830185000 / 788_canonical_historical_digest_contract`
- Public RPC: `submit_pdc_historical_reconciliation_778(jsonb)`
- Private base: `submit_pdc_historical_reconciliation_782_base(jsonb)`
- Independent security review: `deleg_a6903a92`
- Verdict: `ready_for_apply=true`, zero blockers
- Live request canonicalization: Python and PostgreSQL equal for frozen UID `1:21`; 3,667 UTF-8 bytes; SHA-256 `fd784959b016976994087545866e346f01b6f05e1e0faf8627bda25ed9e84550`
- Live private base execute: authenticated `false`
- Live public wrapper execute: authenticated `true`; anonymous/service-role `false`
- Live historical observations/receipts: `0/0`
- Historical observation, aggregate receipt and binding tables: forced RLS
- Observation occurrence and digest unique indexes: present
- Complete protected snapshot: verified for Parts, bookings, Sublet, stoppage, mailbox, monitor controls/pilot/status, QC and RFT/sublet outboxes
- Production sentinel: absent
- Authenticated malformed RPC probe: HTTP 200 `{ok:false,code:unauthorized}` with no state change

## Exact resume command

Run only after the protected `.68` runtime is restored and VerifyOnly/OneCycle has passed through the reviewed installation path:

```text
python pdc_full_inbox_typed_import.py --rows-json "C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-778-rows.json" --outbox "C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-788-resume-outbox.sqlite3" --bounded-caller
```

Required execution controls:

- Use the exact approved Monitor actor/runtime identity already bound to the frozen authorization cohort.
- The caller must use `pdc_historical_778_caller.py` canonical request bytes and the `p_request` RPC envelope.
- Process only the 15 selected rows above.
- Validate every result with `ok == true` and retain the canonical receipt.
- Perform authoritative Board, work, operation, Parts, Sublet, stoppage, QC/RFT and Navision readback for each successful row.
- Replay each successful request exactly once and prove zero new vehicles, operations, work, receipts or revision drift.
- Keep the PT5M task disabled until Apply, replay and isolation proof are complete.
- Do not enable natural concurrent processing until this historical Apply completes.

## Current remaining human-only blocker

The reviewed `.68` source bundle was rebuilt and its canonical inventory verifier passed, but the protected ProgramData install could not be completed because the existing elevated installer invocation was cancelled at the UAC boundary. Current task state remains `Disabled`, principal `LOCAL SERVICE`, run level `Limited`, interval `PT5M`, `LastTaskResult=267014`; VerifyOnly and OneCycle are not yet proven from protected ProgramData.

No historical writer call was made by Website Development Lead. No business mutation was performed beyond staging migration DDL and rollback-only verification.

## Evidence paths

- WDL remediation handoff: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\handoffs\PDC-EMAIL-HISTORICAL-RECONCILIATION-782-REMEDIATION-20260830.md`
- Cycle-7 report: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-pmb-auditor-integration-cycle4-20260817\auditor-reports\cycle-7-integrity-audit-20260830.md`
- Cycle-7 JSON: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-pmb-auditor-integration-cycle4-20260817\auditor-reports\cycle-7-integrity-audit-20260830.json`
- Final attempt session: `@session:pdc-emails/20260828_191237_5e0e90`
- Historical accounting: `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\full-historical-pmb-inbox-accounting.json`
- Frozen rows: `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-778-rows.json`
- 788 migration: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830185000_788_canonical_historical_digest_contract.sql`
- 788 apply/readback controller: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\scripts\apply_migration_788_staging.py`
