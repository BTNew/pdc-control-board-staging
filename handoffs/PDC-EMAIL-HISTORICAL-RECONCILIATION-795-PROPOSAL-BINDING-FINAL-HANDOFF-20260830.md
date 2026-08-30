# PDC-EMAIL historical reconciliation handoff — proposal binding remediation

Date: 2026-08-30
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Production: prohibited and not contacted
Outbound email: prohibited and not sent

## Frozen boundary — unchanged

- Source artifact: `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-778-rows.json`
- Folder: `INBOX`
- UIDVALIDITY: `1`
- High-water UID: `685`
- Messages: `669/669`
- Attachments: `2,305`
- Authorized rows: `15`
- Selected UIDs: `1:21, 1:22, 1:23, 1:26, 1:40, 1:57, 1:85, 1:93, 1:95, 1:96, 1:133, 1:134, 1:137, 1:168, 1:172`
- Manifest SHA-256: `aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018`
- New unused outbox: `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-795-proposal-binding-resume-outbox.sqlite3`
- New outbox was verified absent before this handoff.

Do not rescan IMAP, change mailbox flags, reuse either previous outbox, enable PT5M, send outbound mail, or call a legacy writer.

## Live staging gate

- Current live head: `20260830202000 / 795_historical_wrapper_short_name_repair`
- Applied append-only chain: 789 proposal binding, 790 typed conflict wrapper, 791 manifest compatibility, 792 deterministic vehicle identity, 793 immutable proposal review, 795 short-name/parameter repair.
- Independent reviews: 789 `ready_for_apply=true`; 790 `ready_for_apply=true`; 791 `ready_for_apply=true`; 792 `ready_for_apply=true`; 793 `ready_for_apply=true`; 795 `ready_for_apply=true`; all zero blockers.
- Public RPC: `submit_pdc_historical_reconciliation_778(jsonb)`
- Private predecessor path: deployed PostgreSQL-truncated routine `submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)`
- Wrapper authenticated execute: `true`; anonymous/service-role: `false`
- Private base authenticated execute: `false`
- Review/binding/observation/aggregate receipt tables: forced RLS; no authenticated direct table SELECT
- Live pending proposal count: `15`; all frozen pending proposal fingerprint checks unchanged through every migration
- Historical observations/bindings/reviews/aggregate receipts: `0/0/0/0`
- Production sentinel: absent
- PT5M: disabled

## Required safe behavior

Existing pending `pdc_ai_intake_proposals` are never updated, deleted, reclassified, or silently equated.

For a pending proposal, the server locks the row with `FOR UPDATE` and compares the complete source tuple and payload: source hash, evidence hash, source UID, sender, authentication, Stock, source received time, subject, action and summary.

- Same complete tuple with older `observations` JSON is not equated. If an authorized existing intake is present, the path records a distinct immutable 789 binding linked to the canonical 788 receipt/digest. If no authorized intake is present, the path records a distinct immutable 793 compatibility review and stops before enqueue.
- Material tuple/payload difference returns typed `historical_proposal_tuple_conflict` or `historical_proposal_payload_conflict` with `review_required=true`.
- Terminal existing proposals return typed `historical_proposal_terminal_conflict`.
- Exact replay is idempotent and must not create duplicate vehicles, work, operations, receipts, revisions or bindings/reviews.

## Exact frozen Apply command

Run only from the pdc-emails controlled staging worker with the approved Monitor actor/runtime and this new unused outbox:

```text
python pdc_full_inbox_typed_import.py --rows-json "C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-778-rows.json" --outbox "C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-795-proposal-binding-resume-outbox.sqlite3" --bounded-caller
```

The caller now:

- enforces exactly the 15 frozen UIDs, with no missing, duplicate or extra row;
- writes durable `pending`, `imported`, `retry` or `review` state;
- stores attempt count, last error code, response JSON, timestamps and review-required flag;
- returns nonzero exit status if any row has `ok=false` or any failure remains;
- treats typed proposal conflicts/reviews as durable review outcomes, not success.

Do not proceed as successful unless the process exits zero and every row is `ok=true` with canonical receipt/readback evidence.

## Verified UID 1:21 synthetic evidence

- Exact frozen artifact request returned `ok=false`, `code=historical_proposal_tuple_conflict`, `review_required=true`; no state drift.
- Same full source tuple with older proposal observations returned `ok=false`, `code=historical_proposal_observation_review_required`, `review_required=true` because no authorized intake exists.
- Exact replay returned the same typed review without a second review row.
- Proposal status/version/observations/authentication/source/evidence/UID/sender/Stock remained unchanged.
- Vehicle/work/booking/operation/revision/observation/receipt counts remained unchanged.
- Entire proof transaction was rolled back; persistent compatibility-review rows remained zero.

## Final verification evidence

- Focused historical/security suite: `41/41` local tests passed.
- Full website suite: `229 passed, 0 failed, 1 skipped`.
- Full website check: `229 passed, 0 failed, 1 skipped`.
- pglast: migrations parsed as `24, 13, 16, 16, 24, 15` statements for 789, 790, 791, 792, 793, 795.
- Python compilation: passed.
- Live rollback-only rehearsal: each candidate restored its exact predecessor head.
- Anonymous RPC and direct review-table probes: HTTP `401`.
- No Production, outbound email or mailbox flag operation occurred.

## PT5M boundary

Keep `PDC-PMB-Email-Monitor-Staging` disabled until the frozen Apply completes, every successful receipt is replayed exactly once, authoritative Board/work/operation/Parts/Sublet/stoppage/QC/RFT/Navision readback proves no unrelated drift, and pdc-emails records the final evidence.
