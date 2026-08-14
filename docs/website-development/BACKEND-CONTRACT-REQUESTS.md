# Backend Contract Requests

## Active requests

### BCR-001 — Coordinate auth and modal ownership of application-shell inertness

- Status: Submitted to Hermes — review pending
- Website backlog item: WD-003
- Craig decision: None required; this preserves the accessibility semantics of the existing Vehicle Details dialog without changing authority.
- Required behavior: Authentication lock/unlock/refresh handling must not remove `#app-shell` inertness owned by an open `#vehicle-modal`. Closing the modal must not remove an auth-owned lock. Ownership must remain correct across sign-in refresh, unlock, denial and live role/session changes.
- Inputs and validation: Current auth/session transition plus the dialog's open/closed state and inert owner(s); fail closed when ownership is ambiguous.
- Outputs and stable error codes: No new backend output or error code requested. Supply a reviewed frontend coordination interface or exact integration change in the Hermes-owned auth module.
- Tables/RPCs/events involved (read-only discovery; Hermes confirms): None requested; existing auth/session callbacks only.
- Allowed roles and denied behavior: All roles receive the same modal isolation. This request must not grant a role, enable an action or weaken denial/lock behavior.
- Security/privacy implications: Prevent background interaction during a modal while preserving the stronger auth-owned application lock.
- Realtime and stale/out-of-order semantics: Session/role refresh arriving while the dialog is open must preserve both auth authority and modal isolation; stale auth callbacks must not clear either owner's lock.
- Idempotency/concurrency requirements: Repeated lock/unlock/refresh and dialog open/close events must be idempotent; independent owners release only their own lock.
- Offline/retry behavior: Offline or failed auth refresh remains fail closed and must not make the application shell interactive.
- Rollback/recovery behavior: Removing the website modal enhancement must leave the existing auth lock behavior unchanged; a failed integration defaults to auth-owned inertness.
- Frontend fixture interface while pending: Existing `activateVehicleModal`/`closeVehicleModal` behavior is tested only while auth state is unchanged. No edit to `pdc-auth.js` is made in this tranche.
- Required unit/integration/two-user tests: Open modal then lock, unlock, refresh, deny and change role; lock then open/close modal; repeat/out-of-order transitions; verify shell inertness, modal focus containment and focus return only when authority permits.
- Hermes reviewed contract SHA: Pending.
- Integration notes: Protected boundary. Website Lead will integrate only the exact reviewed interface supplied by Hermes in a separately authorised tranche.

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
