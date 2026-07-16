# AI Email Monitoring and Vehicle Intelligence Timeline — Stage 1 Plan

## Goal
Build the shared-Supabase foundation for staging-only AI email monitoring and per-vehicle intelligence timelines without touching production or enabling unsafe automatic mutations.

## Current-state findings
- `backend/imap_bridge.py` and `backend/outlook_bridge.py` already ingest email metadata/body/attachments into `public.ai_email_intake`.
- `backend/email_board_publisher.py` is first-generation and static-file based: it converts intake rows into `email-board-data.js` review proposals rather than shared vehicle timeline/review records.
- `supabase/migrations/004_ai_intake_foundation.sql` already provides core AI intake tables:
  - `ai_intake_config`
  - `ai_trusted_senders`
  - `ai_mapping_rules`
  - `ai_email_intake`
  - `ai_email_attachments`
  - `ai_extracted_fields`
  - `ai_proposed_actions`
  - `ai_workshop_commands`
  - `label_print_events`
  - `ai_undo_actions`
- `supabase/migrations/005_lock_down_direct_writes.sql` already revokes direct browser writes to those AI tables and expects protected RPCs / bounded backend writes instead.
- The shared workshop rollout already uses the protected-RPC + snapshot + realtime-revision pattern; this feature should follow the same architecture.

## Stage 1 scope
Stage 1 is foundation only:
- shared database entities for monitored mailboxes, analysis results, vehicle match candidates, review queue, immutable timeline events, ETA history, intelligence summaries, response drafts, and per-vehicle intelligence revision counters
- protected RPCs for read snapshot, list review queue, approve/reject review items, add immutable timeline events, and rebuild summary
- synthetic test email fixtures
- staging-only integration tests validating role enforcement and the new contract

## Non-goals in Stage 1
- live production mailbox processing
- broad automatic vehicle mutation from AI
- production deployment
- full timeline UI / review queue UI / response-drafting UI
- model-provider wiring beyond schema placeholders and synthetic fixtures

## Role mapping
Existing backend roles remain authoritative:
- `administrator`: configuration, approvals, evidence access, review decisions
- `operator`: controller-equivalent; may review/approve permitted items and read intelligence snapshots
- `viewer`: read-only snapshot access to sanitized summary/timeline data
- `importer`: backend/service role for ingestion and analysis persistence

## Data model decision
Reuse existing `ai_email_intake` as the evidence/ingestion root. Extend around it rather than creating a parallel intake table.

### New foundation entities
1. `monitored_mailboxes`
   - configurable source mailboxes
   - stores mailbox key/address/provider/active flags
   - referenced by `ai_email_intake`
2. `ai_email_analysis_results`
   - one or more analysis passes per intake record
   - separate confidence dimensions (vehicle match, relevance, classification, action)
   - extracted facts/classifications/warnings
3. `vehicle_match_candidates`
   - ranked per-analysis candidate list
   - stores match type, normalized value, rank, evidence, and score
4. `vehicle_timeline_events`
   - immutable per-vehicle chronological intelligence events
   - combines email/system/manual/workshop/AI events
   - stores evidence link/reference, prior/new values, confidences, approval metadata
5. `vehicle_intelligence_summaries`
   - current synthesized per-vehicle summary (sanitized JSON + text)
   - rebuilt from authoritative timeline + vehicle state
6. `vehicle_intelligence_revisions`
   - per-vehicle revision counter for realtime/snapshot refresh
7. `vehicle_eta_history`
   - preserves ETA changes with type/source/original wording and whether confirmed/calculated/predicted
8. `ai_review_items`
   - manual review queue entries tied to intake/analysis/proposed actions/candidate vehicles
9. `email_response_drafts`
   - salesperson ETA/update draft storage, review state, and evidence linkage

## Privacy boundary
- `ai_email_intake.raw_body` remains backend/importer evidence only.
- Viewer-facing reads should go through sanitized snapshot RPCs rather than direct table access.
- Timeline events may store structured extracted facts and concise AI summary, but not blindly expose raw email bodies to viewers.

## Stage 1 protected RPC contract
1. `get_vehicle_intelligence_snapshot(p_vehicle_id uuid)`
   - viewer+ read
   - returns summary, revision, sanitized timeline rows, ETA history, open review count, and draft count
2. `list_ai_review_queue(p_status text default 'pending')`
   - operator+ read
   - returns review queue rows with confidences, proposed vehicle, other candidates, and reasons
3. `approve_ai_review_item(...)`
   - operator+ mutation
   - marks review item approved / partially approved, updates selected `ai_proposed_actions`, writes audit, appends immutable correction/approval timeline event, bumps revision, rebuilds summary
   - Stage 1 does **not** auto-apply arbitrary vehicle mutations yet; it records the reviewed decision boundary
4. `reject_ai_review_item(...)`
   - operator+ mutation
   - marks review item rejected/irrelevant, audits, appends timeline event where appropriate, bumps revision
5. `append_vehicle_timeline_event(...)`
   - importer/admin mutation
   - immutable append-only write used by bounded backend services/tests
6. `rebuild_vehicle_intelligence_summary(p_vehicle_id uuid)`
   - importer/admin mutation
   - internal/service-facing summary rebuild function

## Summary generation rule for Stage 1
Keep summary deterministic and conservative:
- derive current location/stage/status from authoritative vehicle/workshop data
- derive latest important update from newest relevant timeline event
- derive current parts ETA from newest non-superseded ETA history row
- include key risks only when deterministically detectable from stored data
- never generate a fake completion ETA if none exists

## Synthetic fixtures
Add synthetic JSON fixtures covering:
- exact stock-number match
- VIN match
- thread-context match
- ambiguous stock/customer match
- parts in stock
- parts delayed with relative ETA
- parts dispatched with tracking
- salesperson ETA request

## Test strategy
### Unit / fixture tests
- validate fixture shape and synthetic-only content
- validate deterministic classification fixture expectations where added

### Staging integration tests
- mailbox + analysis + review/timeline foundation tables exist
- viewer can read intelligence snapshot but cannot mutate review items
- unapproved user cannot read intelligence snapshot
- operator can approve/reject review items
- immutable timeline append creates revision bump and audit entry
- direct table mutation remains blocked for browser-authenticated users
- summary rebuild reflects timeline/ETA changes

## Rollback notes
- new entities are additive after migration 013
- no production project or live website changes
- Stage 1 test data uses synthetic mailbox names and synthetic emails only
- if rollback is needed in staging, remove the new tables/functions and delete synthetic rows by foreign-key root (`ai_email_intake`, `vehicle_timeline_events`, `ai_review_items`, `email_response_drafts`)
