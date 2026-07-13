# Authenticated Backend Migration Plan

## Decision

The production PDC Control Board should move from browser-only `localStorage` to an authenticated hosted application with one shared database. This plan deliberately does not select a hosting, identity, API or database vendor. Selection should follow a short requirements and support review.

The existing static build remains useful for isolated workflow and import testing. It is not the production source of truth for multiple users.

## Required outcomes

- Approved staff sign in before viewing vehicle or customer data.
- Every workstation reads and writes the same current vehicle records.
- Each vehicle has one permanent internal ID; stock, Toyota order, VIN, frame and legacy IDs are aliases.
- Imports, PO/job-card promotion, location changes, Parts updates, RFT changes and restores are atomic and auditable.
- Simultaneous edits cannot silently overwrite newer work.
- Server-side backups, retention and tested recovery replace reliance on one browser profile.
- The current desktop workflows and business rules remain recognizable during migration.

## Architecture contract

The browser should call a versioned authenticated API instead of writing operational data directly to `localStorage`. The API owns validation, identity matching, permissions, transactions and audit events. The database is the system of record.

`localStorage` may retain non-sensitive display preferences and a short-lived cache, but it must not be authoritative for vehicles, imports, email recipients, audit history or workflow status.

Minimum server-side entities:

- Vehicle: permanent ID, current source and operational fields, lifecycle/visibility state, row version and timestamps.
- Vehicle alias: alias type, normalized value, source, active/history state and uniqueness/conflict status.
- Work requirement and completion: job type, required/complete state, operator, time, bay, mechanic/provider and hours.
- Location and bay movement: from/to, derived/manual lock, stage, bay, reason, operator and time.
- Import run: source type, file metadata, counts, warnings/rejections, status, idempotency key and receipt.
- Purchase order/job file: source reference, parsed work lines, vehicle match decision and promotion result.
- Parts update/stoppage: status, current/previous ETA, blocker and audit metadata.
- Salesperson: code, display name, email, active state and update history.
- Audit event: actor, action, vehicle, before/after summary, timestamp and correlation/import ID.
- Deleted/retired record: deletion type, reason, actor and permitted restoration path.

## Authentication and permissions

Agree the identity source and access administration before vendor selection. At minimum define:

- Viewer: read operational screens and reports.
- Operator: update work, Parts, location and RFT state.
- Importer: run and confirm Navision, PO and job-card imports.
- Administrator: manage salespeople/reference lists, restore data and manage access.

Every write must record the authenticated person. Sensitive exports, restore, deletion and access administration require explicit permission. Session expiry and access removal must be centrally enforceable.

## Migration phases

### 0. Stabilize the static build

- Keep missing-vehicle lookups fail-safe.
- Make current multi-key imports and restores recoverable.
- Add import receipts and identity-conflict reporting.
- Reconcile `BUSINESS_RULES.md` with regression tests.
- Remove real operational data from unauthenticated public hosting.

### 1. Confirm requirements and choose the platform

Document expected users, devices, availability, identity integration, data region, retention, attachment size, email integration, audit/report needs, support ownership, budget and recovery objectives. Compare candidate platforms against those requirements; do not choose from familiarity alone.

Deliverables: approved requirements, threat/privacy review, platform decision record, data owner, support owner and rollback plan.

### 2. Introduce the API and canonical identity

- Define versioned API contracts and validation errors.
- Assign permanent vehicle IDs and migrate aliases.
- Detect alias collisions for manual review instead of choosing the first match.
- Add row versions or equivalent optimistic concurrency.
- Implement server-side transactions and append-only audit events.

Keep the existing read-only bundled/static data path available behind a test configuration while the API is verified.

### 3. Migrate imports and operational writes

Move one workflow at a time:

1. Daily Navision import and receipt.
2. PO/job-card matching and PDC promotion.
3. Vehicle details, location and bay movements.
4. Parts ETA/stoppage and work completion.
5. RFT and completed/deleted lifecycle.
6. Salesperson/reference-list administration.
7. Backup, restore and reporting exports.

Each import is idempotent: retrying the same file must not duplicate vehicles or work. A failed batch commits nothing.

### 4. Rehearse data migration

- Export a clean static-app backup and source baseline.
- Transform records into canonical vehicles, aliases and audit/history tables.
- Produce counts for migrated, merged, rejected and unresolved records.
- Resolve identity conflicts with an operator-reviewed report.
- Re-run migration in a non-production environment until counts and sample histories reconcile.
- Test full backup restore and document recovery time.

### 5. Pilot and cut over

- Pilot with a small approved staff group using production-like data and permissions.
- Run the old board read-only in parallel for a short, agreed reconciliation period.
- Freeze browser-local writes at cutover, take a final export, migrate the delta and verify totals.
- Publish the authenticated staff URL and remove/block any public copy containing real data.
- Keep a documented rollback window; do not run two writable systems of record.

## Acceptance criteria

- Unauthorized users cannot load HTML data, API data, files or exports containing operational information.
- Two authenticated users see committed updates without manual backup exchange.
- Stale concurrent edits receive a visible conflict and do not overwrite newer work.
- Missing or ambiguous identity lookups mutate no vehicle.
- A PO-created/order-only vehicle is enriched later without changing its permanent ID or duplicating it.
- Navision, PO/job-card and restore failure tests prove all-or-nothing behavior.
- RFT gates, PMB capacity, manual location locks, deletion/return rules and salesperson routing match `BUSINESS_RULES.md`.
- Audit history identifies who changed what and when.
- Backup restoration is tested, timed and signed off by the data owner.
- Desktop workflow regression tests pass at the supported monitor sizes.

## Decisions still required

- Identity provider and who administers access.
- Hosting, API and database platform.
- Data residency, retention and deletion policy.
- Availability, backup frequency and recovery objectives.
- Whether email remains a reviewed client draft or becomes a server-sent message with an approval step.
- Attachment/file retention for source PO and job-card uploads.
- Reporting/export requirements and who may access them.
- Operational support, monitoring and incident ownership.

No production platform should be selected or deployed until these decisions and the security review are approved.
