# Staging migration-ledger baseline and Stage A identity

Latest pre-freeze identity verification:

- Repository staging SQL files end at tracked migration `110`; live-only migrations `111`–`114` are intentionally absent from repository source.
- Live staging ledger contains:
  - `111 = authenticated_job_card_hour_correction`
  - `112 = authenticated_operation_work_key_correction`
  - `113 = authenticated_multi_attachment_email_import`
  - `114 = contain_multi_attachment_email_import`
- Live migrations 113 and 114 appeared during Stage A verification. The migration identity guard rejected each conflicting candidate before auditor objects were created, and Stage A was renumbered rather than overwriting either migration.
- No repository file, fetched remote ref, rejected/obsolete migration record, documented reservation, or live ledger row claims `115` at this verification point.
- Former Stage A identities 112, 113, and 114 have been removed.
- Current Stage A migration identity: `115_beta_ai_auditor_foundation.sql`; ledger name `beta_ai_auditor_foundation`.

Migration 115 verifies the exact predecessor identity `114 = contain_multi_attachment_email_import`, rejects a conflicting version-115 identity, and never edits the migration ledger. The final freeze gate must re-query the live ledger and renumber again if version 115 becomes occupied before freeze.

Rollback and authenticated campaign proofs compare complete ledger signatures before/after and require version 115 / `beta_ai_auditor_foundation` to remain absent. The migration remains staging-only and unapplied until separate deployment approval.
