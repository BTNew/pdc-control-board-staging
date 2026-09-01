# PDC Email AI v2 — immutable legacy freeze

Freeze status: preserved rollback/evidence only. No v2 business logic is added to the legacy Windows monitor. No mailbox flags, Supabase state, scheduler state or Production state was changed by this foundation lane.

## Freeze identity

- Legacy source baseline: Git commit `dd826dc24e9eccd39d6208af6ea4cc870f6720df` (the `.71` rollback lineage).
- Current successor documentation baseline: Git commit `131c10f1` (architecture revision only; not a legacy runtime replacement).
- Existing recovery pack: `recovery-pack/RECOVERY-PACK-MANIFEST.json`, pack version `pdc-email-ai-recovery-pack-v1.11`, source commit recorded by its manifest as `dd826dc24e9eccd39d6208af6ea4cc870f6720df`.
- Legacy role: incumbent rollback transport and retained historical evidence; it is not the v2 planner, queue, ruleset, action boundary or live fallback.
- Immutable rule: do not migrate the failed legacy backlog into the v2 live queue and do not destructively rewrite legacy receipts/evidence.

## Frozen source/evidence inventory

The machine-readable inventory at `foundation/legacy-freeze-inventory.json` records exact SHA-256 identities for legacy source and `.71` installer/dispatch artifacts. It also records the recovery-pack manifest and the source snapshot as retained rollback evidence. Hashes are computed from Git bytes for the frozen commit where noted, not from a dirty working tree.

## Compatibility boundary

The v2 contracts intentionally do not depend on legacy UID adapters, old proposal formats, legacy outboxes, Windows-specific business logic, failed intake queues, hidden Hermes memory or legacy local configuration. Hosted/provider-neutral transport is the portable v2 path; Windows remains optional rollback only.

## Verification statements

- Freeze is descriptive/identity-only; no staging operational write was attempted.
- Legacy files remain present and unmodified in the existing worktree.
- Production was not contacted.
- Downstream runtime and database lanes must re-verify these hashes immediately before any enablement.
