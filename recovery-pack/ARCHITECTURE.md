# Architecture and authority

## Layer 1 — evidence-only intake

`backend/pdc_email_ai_successor_intake.py` accepts RFC822/provider evidence, retains immutable source and attachment digests, records mailbox/message/thread/provider metadata and never classifies PDC work or performs a business write.

## Layer 2 — Hermes/AI typed interpretation

`backend/pdc_email_ai_successor_planner.py` receives complete correspondence, bounded PDF extraction and authoritative vehicle context. It emits only `pdc-email-ai-plan-v1`: one independently accounted instruction per vehicle/action, identity evidence, expected versions and explicit version metadata. It cannot provide SQL, table names, RPC names or credentials.

## Layer 3 — canonical command boundary

`public.apply_pdc_email_ai_transaction_successor(jsonb)` is the only successor apply boundary. The authenticated dedicated runtime is checked first; Administrator/service-role/browser/direct-DML/arbitrary-SQL paths fail closed. Identity-to-vehicle binding, source receipt/digest, version binding, action allow-list, stable action keys, locks and readback confirmation precede canonical RPC dispatch.

## Layer 4 — independent authoritative readback

`backend/pdc_email_ai_successor_executor.py` calls the command once and separately reads the authoritative Board/read model. Expected and actual values, IDs, versions, operation/hour tuples, Parts, Sublet, location, lifecycle and revisions are compared. HTTP 200, `ok=true`, a receipt row or visual UI state is not proof.

## UI projection

The successor Intake UI is read-only and uses `get_pdc_email_ai_transaction_successor_inbox_v2(jsonb, integer)` with composite cursor `(sort_time, created_at, id)`. It renders one parent row per email and child vehicle/action results. Realtime is invalidation followed by authoritative refresh; stale generations are suppressed. Raw message bodies and secrets are excluded.

## Rollback

`.68` remains the rollback lane. Rollback disables/revokes only successor runtime capability, preserves successor evidence and does not delete receipts or rewrite migrations. Production is outside the pack.
