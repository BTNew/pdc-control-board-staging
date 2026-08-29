# Historical PMB Inbox reconciliation — 778 resume contract

Environment: STAGING project `cdsmnqxtyyoeoznmbidd` only. Production and outbound email are prohibited.

The frozen read-only Inbox boundary is immutable:

- mailbox `pmbcontroller@gmail.com`, folder `INBOX`;
- UIDVALIDITY `1`;
- high-water UID `685`;
- `669` frozen UIDs;
- manifest SHA-256 `aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018`;
- mailbox flags must remain unchanged.

The current staging RPC is:

`public.submit_pdc_historical_reconciliation_778(jsonb)`

The source-side caller must use `pdc_historical_778_caller.py` and a new outbox path. It must not rescan IMAP, call the normal monitor, alter flags, or reuse an outbox:

```text
python pdc_historical_778_caller.py --rows-json <frozen-rows-export.json> --outbox <new-historical-778-outbox.sqlite3> --bounded-caller
```

The rows export is a local artifact produced from the existing frozen checkpoint and extracted evidence only. It must contain exactly the 15 773-authorized eligible rows; UID `1:197` / Stock `13056899` is omitted before any RPC call. Every row must contain:

- `manifest_sha256`, `provider_uid`, `parent_source_hash`, `sender_email`, `authentication`, `stock_number`;
- `source_received_at`, `subject`, `action_type`, `summary`, `evidence_hash`, `observations`;
- exact `source_metadata` keys: `attachment_names`, `graph_message_id`, `internet_message_id`, `parsed_text`, `provider_authserv_id`, `raw_body`, `received_at`, `recipient_mailbox`, `sender_name`, `uid`, `uidvalidity`;
- `attachments`, each with `filename`, `sha256`, `size`, `content_type`, and optional frozen evidence classification.

For each genuine Job Card sibling, include one child with exactly `attachment_hash`, `attachment_kind=job_card`, `extraction`, and `extraction_hash`. For an ambiguous/multi-vehicle Job Card sibling, include `attachment_kind=ambiguous_job_card`; it is recorded as failed closed and does not block independent valid siblings. PO/Pick List siblings remain evidence and are never imported as Job Cards.

The caller adds these exact runtime fields to every request:

- gateway `pdc-monitor-staging-sales-uid509-v1`;
- release `pdc-monitor-staging-m502-2026.08.44`;
- release source `e850c319989d98b45b95a28aa815d78e2c2e3a4b`;
- release manifest `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`;
- manifest UIDVALIDITY/high-water/count `1/685/669`.

The server rechecks the current authenticated Monitor actor and runtime binding, exact 773 sender/authentication/source/Stock tuple, 24-hour authorization expiry, manifest hash and attachment rows. It uses provider-bound enqueue, immutable per-sibling observations, the canonical Job Card importer, receipt-backed replay protection, and old-mail completion protection. Any Navision `not_found`, identity conflict, unauthorized identity, ambiguous sibling, or canonical rejection remains fail closed. No booking, completion, location scheduling, outbound email, mailbox contact, task enablement, or Production mutation is part of this contract.

Resume only after the current staging RPC and runtime proof are read back. Stop and report the exact sanitized error if the current actor/gateway/release/high-water/manifest or sender binding fails.
