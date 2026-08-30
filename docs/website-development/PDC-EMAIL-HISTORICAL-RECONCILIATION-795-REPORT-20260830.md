# Historical Inbox proposal-binding remediation report — 2026-08-30

Scope: STAGING only (`cdsmnqxtyyoeoznmbidd`). Production and outbound email were prohibited and untouched.

## Outcome

The 788 historical reconciliation path now safely handles pending proposal collisions without changing the existing proposal rows. The final live staging head is:

`20260830202000 / 795_historical_wrapper_short_name_repair`

Applied append-only successors:

- 789: immutable proposal binding for same full tuple with observation-only drift.
- 790: authenticated typed terminal/tuple/payload conflict preflight with proposal-row locking.
- 791: exact authorized attachment-manifest byte compatibility.
- 792: deterministic vehicle identity count/readback; invalid UUID aggregate removed.
- 793: immutable compatibility review before enqueue when no authorized intake exists.
- 795: PostgreSQL-truncated 793 routine name and cloned-wrapper parameter repair.

Migration 794 was not applied; it was superseded by the short-name 795 successor because PostgreSQL truncates identifiers over 63 bytes.

## Proposal safety

Existing `pdc_ai_intake_proposals` are never updated, deleted, reclassified or silently equated. The server locks the proposal row with `FOR UPDATE` and compares source hash, evidence hash, provider UID, sender, authentication, Stock, source time, subject, action and summary.

- Material mismatch returns typed tuple/payload conflict with review required.
- Terminal proposal returns typed terminal conflict.
- Same full tuple with older observations is recorded separately, never treated as equal.
- If no authorized intake exists, a distinct immutable compatibility review is recorded before enqueue and the protected pilot/intake guard is not bypassed.
- Exact replay is idempotent.

## Live UID 1:21 proof

Frozen UID `1:21` has four non-Job-Card siblings and an existing pending proposal.

- Exact frozen request: `ok=false`, `historical_proposal_tuple_conflict`, `review_required=true`.
- Same full source tuple with older proposal observations: `ok=false`, `historical_proposal_observation_review_required`, `review_required=true`.
- Exact replay of that review: same typed result; no second review row.
- Existing proposal status/version/observations/authentication/source/evidence/UID/sender/Stock unchanged.
- Vehicle, work, booking, operation, revision, historical observation, binding, review and aggregate receipt counts remained unchanged in the rollback proof.
- Rollback proof left persistent review rows at zero.

## Caller safety

`pdc_full_inbox_typed_import.py` now:

- enforces exactly the frozen 15-provider-UID cohort;
- rejects missing, duplicate or extra rows;
- durably records pending/imported/retry/review state;
- records attempt count, error code, response JSON and review-required state;
- returns nonzero exit status if any row returns `ok=false`.

The final handoff uses a new unused outbox only.

## Security and deployment evidence

- Independent 789 review: ready_for_apply=true, zero blockers.
- Independent 790 review: ready_for_apply=true, zero blockers.
- Independent 791 review: ready_for_apply=true, zero blockers.
- Independent 792 review: ready_for_apply=true, zero blockers.
- Independent 793 review: ready_for_apply=true, zero blockers.
- Independent 795 review: ready_for_apply=true, zero blockers.
- Local focused historical/security suite: 41 tests passed.
- Full website suite: 229 passed, 0 failed, 1 skipped.
- Full website check: 229 passed, 0 failed, 1 skipped.
- SQL parse counts: 789/790/791/792/793/795 = 24/13/16/16/24/13.
- Python compilation: passed.
- Live rollback-only rehearsals: passed for each successor.
- Live RLS/grants: authenticated wrapper only; anonymous/service-role wrapper denied; private bases denied; review/binding/observation/receipt RLS forced; direct authenticated review-table SELECT denied.
- Live anonymous RPC/direct-table probes: HTTP 401.
- Live observations/bindings/reviews/aggregate receipts: `0/0/0/0`.
- Frozen pending proposals: unchanged.
- Production sentinel: absent.

## Runtime and Apply boundary

The protected `.68` runtime remains installed and previously proven by exact receipt/hash/ACL, VerifyOnly and dry-run OneCycle. `PDC-PMB-Email-Monitor-Staging` remains disabled as `LOCAL SERVICE`, `Limited`, `PT5M`; no task enablement was requested.

Website Development Lead did not run genuine historical business Apply. pdc-emails must use the new handoff and outbox. Keep PT5M disabled until all 15 outcomes, canonical receipts, exact replay/idempotency and unrelated-isolation readback are complete.

## Artifacts

- Final handoff: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\handoffs\PDC-EMAIL-HISTORICAL-RECONCILIATION-795-PROPOSAL-BINDING-FINAL-HANDOFF-20260830.md`
- Migration 789: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830190000_789_historical_proposal_binding_successor.sql`
- Migration 790: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830191000_790_historical_proposal_conflict_wrapper.sql`
- Migration 791: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830192000_791_historical_manifest_compatibility_successor.sql`
- Migration 792: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830193000_792_historical_vehicle_identity_successor.sql`
- Migration 793: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830200000_793_historical_proposal_review_successor.sql`
- Migration 795: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830202000_795_historical_wrapper_short_name_repair.sql`
- Caller: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\pdc_full_inbox_typed_import.py`
