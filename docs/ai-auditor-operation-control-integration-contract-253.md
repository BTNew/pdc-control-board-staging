# AI Auditor operation-control integration contract — draft 253

**Status:** source-only, rejected until exact-SHA integration and independent reviews complete. No deployment or migration application is authorised.

## Frozen origin and exclusions

- Origin SHA: `094daf78fcb77cceaf5a5c0c2c1e368df932549d`.
- Installed migration 250 remains byte-identical.
- Migration 251 remains untouched and is not used, copied, installed, or modified by this task.
- New source is append-only draft migration 253 or later if 253 is found reserved.
- No generic mutation path from migrations 176, 178, 189, or 201 may become callable.
- No mutation of vehicles, bookings, dates, locations, Parts/Sublet, completed work, users, lifecycle state, source operation evidence, or history.

## One cross-language contract

Runtime and SQL share these versioned schemas:

1. Canonical gateway envelope and signing bytes.
2. Typed planning request containing ordered operation-item intents; no caller before-state, proof, disposition, current version, or authoritative row value.
3. Immutable final proposal containing proposal namespace/ID/version, ordered final typed items, final scope, expected namespaced row versions and their hashes.
4. Apply selection containing only the final proposal bindings, never the earlier natural-language planning scope.
5. Run/receipt/revision and Undo selection using domain-qualified namespaced references.

The exact canonical bytes, instruction hash, typed-item-set hash, final-scope hash, expected-version hash, proposal hash, Apply selection and signature are executable shared golden vectors. A proposal change produces a new proposal version/hash and invalidates every earlier confirmation.

## Typed operation items

Supported operation actions are exactly:

- `add`
- `edit`
- `split`
- `combine`
- `reorder`
- `remove_duplicate`

Every item carries an explicit namespaced selector and typed desired values. The database resolves effective rows, operation membership, current values, protected fields, duplicate evidence, ambiguity and expected row versions. It rejects client attempts to supply authoritative old values or proofs.

Natural language may only emit bounded desired intent. Structured data that language cannot safely infer—split children/hours, combine members/survivor, complete reorder set, add department/hours and exact operation references—must come from trusted structured context or produce clarification.

## Atomic Apply

Apply verifies one immutable final proposal:

- proposal ID and version;
- exact ordered typed-item-set hash;
- final-scope hash;
- proposal hash;
- complete expected-row-version hash;
- new signed Apply delivery and non-replayed nonce.

It locks and validates the complete scope before operational writes. Any stale, protected, ambiguous outside-policy, malformed, unauthorised or diverged item aborts the transaction. Success writes controlled overlays/non-completed required-work projection, immutable receipts/audit and exactly one sanitized run revision. There is no partial-success result.

## Exact logical Undo

Undo first compares the entire authoritative after-state:

- namespaced operation membership and identifiers;
- descriptions/codes/departments/hours/order;
- manual/protected state;
- aggregate and per-department totals;
- effective required-work identifiers;
- every expected physical overlay/version needed for restoration.

Any divergence aborts before the first Undo write. Successful Undo restores the exact logical before-state while retaining immutable history, verifies the complete result, appends one Undo receipt and one sanitized run revision, and never returns partial success.

## Realtime authority

`public.pdc_auditor_workshop_revisions` is an append-only invalidation ledger.

- Controlled database functions alone insert rows.
- Browser principals receive only column-scoped SELECT when both active approved human-site role and active dealer scope authorize the row.
- Viewer, Monitor, Importer, service Auditor, ordinary authenticated and revoked/inactive users are denied reads.
- All clients are denied INSERT/UPDATE/DELETE/TRUNCATE and sequence access.
- Browser consumers validate dealer, staging environment, event-specific namespaced run identity and monotonic revision; then refetch authoritative state.
- Two independent consumers, coalescing, failure retention, reconnect reconciliation and stale-generation teardown are executable source tests. Real delivery remains a later authorised staging acceptance item.

## Required evidence before source verdict

- Shared Python/PostgreSQL golden vectors, including Unicode, null, booleans, numbers, ordering and timestamp boundaries.
- Runtime-to-SQL payload integration tests.
- Focused PostgreSQL 17 execution in a disposable local database only.
- All six operation shapes and exact Apply/Undo round trips.
- Diverged Undo proving zero mutation.
- ACL/RLS positive and negative role probes.
- Two-browser executable Realtime harness.
- Full repository regression with zero failures and only the existing zero-data skip.
- One frozen commit reviewed independently for database/security, runtime/signature, Realtime/frontend and atomic Undo, followed by parent integration review.
