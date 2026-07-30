# Preserved pre-Stage-A AI Auditor draft inventory

The pre-existing shared worktree was not used as the implementation worktree.

- Source worktree: `C:\Users\nwmgr\AppData\Local\Temp\pdc-workshop-load-fix`
- Branch: `qa/workshop-bulletproof-20260728`
- Base HEAD: `47830a914a80939a492ae571a1fa4ad439597a71`
- Evidence backup: `C:\Users\nwmgr\AppData\Local\hermes\backups\pdc-ai-auditor-draft-20260729T122704+0800`
- Stage A worktree: `C:\Users\nwmgr\AppData\Local\Temp\pdc-ai-auditor-stage-a`
- Stage A branch: `feat/stage-a-ai-auditor-20260729`

## Original dirty inventory

Tracked modifications:

- `app.js` — mixed AI Auditor preview and unrelated Planner presentation changes
- `staging.html` — preliminary Auditor navigation/page markup
- `test_workshop_planner.js` — unrelated Planner work
- `workshop-planner.js` — unrelated Planner work

Untracked files:

- `ai-auditor.css`
- `docs/beta-ai-auditor-design.md`
- `supabase/staging_only/111_preserve_stoppage_when_returning_to_unallocated.sql` — unrelated
- `supabase/staging_only/121_beta_ai_auditor_foundation.sql`
- `test_beta_ai_auditor_preview.js`
- `test_stoppage_return_to_unallocated_111.js` — unrelated
- `test_workshop_planner_station_work_preview.js` — unrelated

The evidence backup contains exact tracked patches, copied Auditor candidate files, Git status, base HEAD and SHA-256 inventory. The original dirty worktree remains unchanged.

## Reusable concepts

- Separate staging Auditor navigation/view
- Persistent BETA/read-only status language
- Disabled decision controls
- Summary-card and evidence-card visual direction
- Deterministic board-advisor concepts
- Staging-only table-family naming proposal

## Unsafe or incomplete parts replaced

- Preliminary migration mixed Stage A findings with Stage C decision concepts.
- It lacked complete actor-to-dealer authorization and durable operational dealer proof.
- It did not provide the required sanitized authoritative snapshot.
- It did not model run provenance, risk projections, internal reports or a revision-only Realtime boundary completely.
- Recommendation uniqueness was not safely dealer-scoped.
- Booking-to-work relationships could not be treated as established authority.
- The UI still depended on the legacy Board Advisor adapter, which builds vehicle DTOs from browser/local board state.
- The draft did not include the full deterministic catalogue, risk formula, 150+ fixtures, lifecycle tests or rollback/non-mutation proof.

Stage A therefore reuses visual and explanatory concepts but replaces the authority, database and rule-engine implementation cleanly from the tracked base HEAD.
