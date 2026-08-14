# Backend Contract Requests

## Active requests

None. The initial assessment did not change behavior and did not require a new backend interface.

## Decision-dependent candidates

These are not requests and do not authorize backend work. Promote one to an active numbered request only after Craig decides the workflow and a frontend requirement cannot be met with the current reviewed interface.

### Candidate BCR-C1 — QC sign-off and label-outcome presentation

Trigger: Craig requires a server-visible print state, acknowledgement, retry receipt or rollback behavior after the atomic QC-to-RFT save. If the decision is simply “QC remains saved; retry printing locally,” this may remain frontend-only.

Needed from Craig first: CD-003 and CD-004.

Security/data implications to review with Hermes if promoted: actor/role, exact vehicle/version binding, response receipt, idempotency, separation of authoritative QC success from untrusted local printer outcome, Realtime projection and safe retry semantics.

### Candidate BCR-C2 — Cross-surface freshness metadata

Trigger: WD-010 requires authoritative timestamps or freshness fields not already present in reviewed snapshots/responses.

Needed from Craig first: CD-009.

Security/data implications to review with Hermes if promoted: whether timestamps/revisions disclose protected activity, per-role projection, event ordering and reconnect behavior.

## Required request format

### BCR-NNN — Title

- Status: Draft / Submitted to Hermes / Reviewed / Accepted / Rejected / Superseded
- Website backlog item:
- Craig decision:
- Required behavior:
- Inputs and validation:
- Outputs and stable error codes:
- Tables/RPCs/events involved (read-only discovery; Hermes confirms):
- Allowed roles and denied behavior:
- Security/privacy implications:
- Realtime and stale/out-of-order semantics:
- Idempotency/concurrency requirements:
- Offline/retry behavior:
- Rollback/recovery behavior:
- Frontend fixture interface while pending:
- Required unit/integration/two-user tests:
- Hermes reviewed contract SHA:
- Integration notes:

## Boundary rule

The Website Development Lead may inspect existing interfaces and build safe fixtures, but must not create/alter migrations, tables, functions, grants, RLS, Supabase client/config, Realtime authority or deployment/release controls. Integration uses only the exact interface and SHA reviewed by Hermes.
