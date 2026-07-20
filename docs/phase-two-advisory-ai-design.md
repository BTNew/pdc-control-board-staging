# Phase Two — advisory AI board oversight

Date: 2026-07-20

## Authority boundary

Phase Two is a read-only decision-support surface. It may detect, rank, explain and recommend human review. It must not change vehicles, Parts, bookings, workflow stages, local/shared operational storage, audit records, users, roles, configuration or Supabase data. It must not call mutation RPCs, send messages, approve proposals, or transfer business data to an external model/provider.

The initial implementation is deliberately deterministic. Every advisory is produced by a named rule with a stable code, severity, evidence and recommendation. This makes the result reviewable without trusting a generative model. A later explanatory model may only summarize already-produced deterministic findings and requires a separate design and approval.

## Inputs

The UI adapter builds a minimal read-only DTO from current in-memory vehicle data and, when safely available, a revision-bearing workshop snapshot returned by the data service's narrow `getTrustedSnapshot()` accessor:

- stable vehicle identity and stock label
- current stage/location and stage age
- blocked and Parts state/reason/ETA
- delivery date
- required/completed stages
- manual job-line confirmation state
- booking ID, stable vehicle identity, stage, bay, status, start/end and stoppage reason

Raw email/file contents, credentials, access tokens, notes beyond the explicit reason fields, and unrelated customer data are not inputs.

## Deterministic rules

1. `DATA_*`: missing/duplicate vehicle identity, duplicate booking ID, invalid booking interval, or booking without one unambiguous vehicle.
2. `PARTS_STOPPAGE`: active Parts stoppage.
3. `PARTS_ETA_OVERDUE`: incomplete required Parts with an ETA before the analysis clock.
4. `VEHICLE_BLOCKED`: active operational blocker.
5. `DELIVERY_RISK`: delivery due within seven days while required work or Parts remains incomplete.
6. `STAGE_STALE`: active vehicle exceeds the existing configured age limit for its current stage.
7. `LABOUR_UNCONFIRMED`: manual work exists without staff-confirmed labour hours.
8. `BOOKING_STOPPAGE`: active Workshop booking is in stoppage.
9. `BOOKING_OVERDUE`: planned start or started end is materially past the analysis clock.
10. `BAY_OVERLAP`: two active bookings overlap in the same stage/bay.
11. `UNSCHEDULED_REQUIRED_STAGE`: outstanding required physical work has no active booking, but only when booking coverage is authoritative and the vehicle identity is unambiguous.

Rules fail closed: ambiguous identities produce data-quality advisories and suppress identity-dependent scheduling advice. Missing/invalid timestamps never become “now”. Retained planner fallback data is never advisory authority. Snapshot trust is invalidated before revision reloads, during debounce/in-flight refresh, after permission or network failure, and on service teardown; only a successful authenticated response with a revision restores trust. Booking rules are omitted whenever that trusted snapshot is unavailable, and the UI discloses the coverage limitation and the accepted shared revision.

## Output contract

Each advisory contains only serializable display data:

- stable finding ID and rule code
- severity and category
- vehicle/booking identity labels
- concise title and explanation
- evidence strings
- human recommendation

Ordering is deterministic: severity, category, rule code, stable finding ID. No output contains a callback, command, RPC name, mutation payload or automatic action.

## UI contract

The AI Intake Review screen receives a separate “Phase 2 · Board advisor” section with:

- explicit **Advisory only** status
- a summary by severity
- booking-coverage disclosure
- rule code and evidence on every finding
- refresh/recalculate only; no Apply, Move, Complete, Approve, Send or workflow buttons
- accessible live summary and semantic finding list
- immediate rendered-data clearing on every auth session revalidation, sign-out, expiry or lockout

## Verification

- Pure-rule tests use a fixed clock and frozen inputs.
- Tests prove deterministic ordering, identity fail-closed behavior and no input mutation.
- Static authority tests prohibit storage writes, network APIs, mutation RPC names and mutating UI controls in the advisor module/surface.
- Data-service tests prove retained snapshots are rejected after `401/403`, while a newer revision is pending and after teardown.
- Auth-lock tests prove prior-session advisory business data is removed from the DOM.
- Browser tests use only synthetic fixture data and block non-local network requests.
- Aggregate repository tests, syntax checks and independent security/functional review are required before the branch reaches its review stop point.

## Explicitly excluded

- model/provider integration
- email monitoring beyond the existing review flow
- automatic operational changes
- acknowledgement persistence
- schema/migration/RLS/RPC/role changes
- production or shared-staging deployment
- pilot activation
