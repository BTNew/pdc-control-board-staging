# BETA – AI Auditor · Stage A architecture

Persistent status: **BETA – READ ONLY / APPROVAL REQUIRED**

## Scope

Stage A audits canonical PMB Control Board state with deterministic rules. It may store audit runs, findings, evidence, risk projections and manually generated internal report projections. It cannot approve, deny, snooze, mutate operations, activate schedules or deliver reports externally.

PMB PDC Monitor remains the only authority for mailbox intake, document interpretation, exact vehicle matching, activation, initial canonical work, confirmed labour evidence, Parts/Sublet requirements and source-evidence preservation.

## Authority graph

1. **Actor authority** — one approved active `pdc_user_roles` identity bound to `auth.uid()` and normalized JWT email; exact role must be viewer, operator or administrator.
2. **Dealer authority** — one active `pdc_auditor_user_dealer_scopes` assignment. Zero or multiple assignments fail closed. Administrators do not receive implicit cross-dealer authority.
3. **Vehicle dealer authority** — each vehicle must have exactly one durable approved dealer provenance. Legacy/unscoped or conflicting rows are excluded and reported as coverage limits.
4. **Read authority** — one explicit backend snapshot projection; no broad row serialization, browser-local merges or fallback.
5. **Persistence authority** — only auditor-owned tables through a bounded finding-submission RPC. No auditor trigger or function touches operational tables.

## Snapshot contract

The Stage A snapshot is dealer-scoped, revision-bearing, bounded and sanitized. It contains:

- environment, dealer, generated time, auditor and operational revisions, snapshot version and coverage limits;
- active canonical vehicles: UUID, Key Number, Stock Number, model, location, lifecycle/workshop state, QC/RFT/Completed flags, ETA, version and timestamps;
- canonical work requirements and bounded operation lines: stable identity, department/station, required/completed state, estimate hours, classification, provenance type, source reference token and revisions;
- bookings: stable IDs, vehicle/stage/bay/resource IDs, half-open times, status, versions and explicit/candidate work linkage counts;
- active bays/stations and explicit compatibility configuration;
- job-specific Parts evidence where available and clearly labelled lower-confidence vehicle-level Parts evidence otherwise;
- Sublet status/provider display name without contact details or notes;
- stoppage status and timing fields without arbitrary free text or staff/customer PII;
- allowlisted working calendar and deterministic rule settings.

It excludes customer names, registration/VIN, actor/sender/provider email, telephone, mailbox identifiers, raw email or document text, source payloads, audit before/after JSON, arbitrary metadata and operational mutation capability.

A booking-to-work relation is accepted only when an explicit durable relation exists. Where only stage/vehicle candidates exist, the snapshot exposes candidate IDs and match count. The rule engine reports zero or multiple candidates and does not create a link or fuzzy backfill.

## Finding lifecycle

A stable fingerprint binds dealer, rule version, rule ID, canonical entity IDs and revisions, and normalized evidence hash. Exact unchanged evidence reuses the same recommendation. The first-detected timestamp is preserved; last-detected updates on subsequent runs; last-evidence-change updates only when evidence changes. A finding resolves only when the deterministic condition disappears. Reappearance after resolution creates a new occurrence while retaining history.

Stage A findings contain no executable operation, mutation payload, approval state or external-delivery instruction.

## Deterministic rule families

- Booking authority: missing/ambiguous work relation, duplicate booking, multiple active bookings, completed/cancelled/inactive work booked.
- Time/resource conflicts: vehicle, bay, technician and default-deny station compatibility using half-open intervals.
- Labour estimates: missing, zero, negative, missing provenance and provisional department-configured duration mismatch.
- Parts: explicit job-level or lower-confidence vehicle-level readiness horizons, booked/started stoppage, received-but-stopped and ready-without-future-booking.
- Forgotten work: no future booking, no replacement after cancellation, next department absent, stagnation, stale stoppage review, QC/RFT/Collected, IT ETA and Yard Hold readiness.
- Workflow integrity: QC/RFT/Completed prerequisites, active stoppage in terminal workflow, protected-location regression, booking used as work authority and Sublet shown as a physical planner.
- Data quality: missing stoppage owner/next action/review/expected resolution and authority/coverage gaps.

Working-day calculations use the allowlisted calendar. The initial proposed calendar is Monday–Friday, 08:00–16:00 Australia/Perth, matching the tracked Planner default; the separate 07:00 briefing is pre-opening. No holiday exclusions are assumed until approved dates are configured. Runtime snapshots use authoritative Workshop settings when available. This limitation is disclosed.

## Deterministic risk score

The total is 0–100 and the response exposes every component. Weights are administrator-configurable within bounded Stage A ranges:

- Parts risk
- Imminent booking
- Active stoppage
- Booking conflict
- Missing booking
- Overdue work
- Workflow violation
- Repeated rescheduling
- Missing ETA
- Missing estimated hours
- Days at PMB

The same evidence contributes once to a component. Severity floors keep critical conditions visibly critical. Stage A contains no model call and no mechanism for AI to alter the score.

## Internal reports

Morning Workshop Briefing, Midday Risk Review, End-of-Day Carryover and Critical Issues are deterministic page projections. They are manually generated/viewed and not scheduled, emailed, sent to Telegram or otherwise delivered.

## Stage A limitations

- Existing operational vehicle/work/booking tables do not have a universal first-class dealer column. Dealer proof must remain fail-closed and may exclude legacy records.
- Existing bookings do not universally have an explicit work-item FK. Ambiguous relationships remain findings.
- Parts evidence is often vehicle-level, reducing confidence.
- Stoppage owner, next action, review and expected resolution may be missing; absence is reported, not fabricated.
- Holiday exclusions require an approved date list.
- Approve, Deny and Snooze are disabled and reserved for a separately approved Stage C.
