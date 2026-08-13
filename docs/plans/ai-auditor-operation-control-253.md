# AI Auditor operation-control source plan

## Locked baseline and safety

- Baseline: `094daf78fcb77cceaf5a5c0c2c1e368df932549d`
- Branch: `feat/ai-auditor-operation-control-20260813`
- New work is source-only in a later unreserved draft migration. Migration 251 remains untouched and unused.
- No migration, staging record, database head, Pages runtime, pdc-monitor resource, production resource or `main` branch is touched.
- Revoked generic migrations 176/178/189/201 remain revoked and are not reused as client execution surfaces.

## Architecture

1. Add staging-only draft migration 253 with independent RPC-only tables for signed deliveries, immutable typed plans/items, runs, full ordered-set receipts, aggregate/work-requirement receipts and strict atomic Undo.
2. Keep the Auditor as an ordinary scoped authenticated Viewer identity. It receives EXECUTE only on the new controlled proposal/query, Apply and Undo RPCs; every table remains RLS-enabled with no direct role grants.
3. Use HMAC-SHA256 gateway keys provisioned later by a separately authorised server-side ceremony. No key material is committed. Verify one exact canonical envelope in both the bounded Python ingress and database RPC boundary. It contains gateway instance, delivery UUID, key ID, nonce, issued/expiry timestamps, instruction hash, selected scope, Telegram evidence and signature; delivery UUID and gateway/key/nonce are reserved globally.
4. Parse natural language only into allowlisted typed operations. Review creates an immutable proposal without operation mutation. Mutation language creates a proposal and stops at an Apply-confirmation response. Apply uses a distinct signed delivery bound to the exact plan hash and selected scope; one confirmation authorizes the selected batch without line-by-line approval.
5. Apply derives current values and protections server-side, then preflights every authorised unambiguous item under locks. Ambiguity may be isolated only when the signed selected scope explicitly authorizes the safe subset. It rejects protected/manual/completed/current-state conflicts, mutates only `vehicle_workshop_line_adjustments` plus non-completed `vehicle_work_items`, captures one complete run-level ordered effective-set/aggregate/work-requirement before and final-after receipt per affected vehicle/job card, and emits exactly one `pdc_auditor_workshop_revisions` row.
6. Split creates bounded child overlays and conserves hours; combine deterministically edits one survivor and supersedes the remaining exact members; reorder covers the complete effective set; duplicate removal requires server-proven duplicate evidence and preserves one deterministic survivor. Source-line edits create a source-linked overlay instead of altering imported source.
7. Strict Undo preflights every final run-level scope receipt and aborts before writes on any mismatch. A successful Undo restores every overlay in reverse order, recalculates and verifies the exact complete pre-run state before sealing the run as undone and emitting one run revision. No partial-success result exists.
8. Browser Realtime consumes `pdc_auditor_workshop_revisions` through narrow authenticated dealer/environment SELECT/RLS, accepts both legacy 226 and typed 253 Apply/Undo run events, coalesces invalidations, advances its revision cursor only after a successful authoritative refetch, and never treats payload data as authority.

## Verification

- Focused static SQL contracts for migrations 225–231 and 253.
- Python runtime tests for typed grammar, proposal-only review, explicit confirmation, canonical signatures, expiry and scope binding.
- Browser harness proving two independent consumers each process one run revision once.
- Full `npm test` and `npm run check`; only the existing clean-import zero-data skip is allowed.
- Frozen exact-SHA independent reviews: database/RLS/RPC authority, functional/Undo, gateway/replay, Realtime/frontend, regression/migration immutability.

## Later staging acceptance (not part of this work)

Install into an isolated coordinated staging window only after pdc-monitor acceptance and separate approval. Provision a fresh gateway key and scoped Viewer identity through an audited ceremony, then run rollback-only SQL/database tests, negative-role tests, signature/replay tests, exact Apply/Undo fixtures, two-session Realtime checks, readback/parity checks and immutable migration-ledger evidence before considering activation.
