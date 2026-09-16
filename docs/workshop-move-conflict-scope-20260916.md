# Booking move conflict scope repair

Date: 16 September 2026

## Problem and change

Dragging an existing planned booking into another bay called a cascade that shifted every future planned booking in that destination by the same amount. A distant booking after a sufficient gap could therefore be moved unnecessarily into its own vehicle's next station booking, rejecting the entire drag with vehicle_overlap.

The repaired cascade plans only the overlapping sequence after the dropped booking and stops at the first gap that absorbs the delay. Each displaced booking moves only as far as needed. The target and affected followers use authoritative destination-bay capacity, including reduced efficiency. Unaffected bookings retain their exact schedule, version and history. Returned shifted IDs and counts include only bookings actually moved.

Vehicle conflict checks continue to compare canonical vehicle UUIDs. Real same-vehicle overlaps, occupied bays, mechanic clashes, running/stopped work, admin blocks and stale versions retain their existing protections. This update does not weaken conflict checks or change existing automatic one-hour handover rules. Genuine conflicts in affected bookings can still reject a move atomically.

The website now adds available conflicting stock, department, bay and Perth time to the warning. It resolves server booking IDs only against a trusted snapshot or canonical server booking details, never by stock/key text. Missing or ambiguous details fall back to the generic warning.

## Verification

- Reproduced the old failure using synthetic A/B/C bookings: A's two-hour move shifted B correctly but also shifted distant C into C's booking at another station despite spare capacity in between.
- After repair, 41 database rollback assertions passed, covering gap absorption, exact boundaries, unequal shifts, reduced bay efficiency, unchanged distant/parallel work, real resource conflicts and atomic failure.
- Controller receipt behavior was checked using a transaction-local copy that removes only the non-website SQL transport prerequisite. Approved-actor, version, receipt, idempotency and underlying booking logic remain intact; the installed endpoint's transport denial was also verified. This is not a browser/HTTP drag test.
- 1,011 JavaScript regression tests passed, including ten conflict-message cases.
- Database checks confirmed no pre-existing vehicle, booking, assignment, admin-block or receipt changes. All synthetic records rolled back; no temporary test accounts or vehicles remain.
- Independent implementation reviews found no release blocker. Function owner, security mode, search path and execute grants are unchanged; security-advisor findings match the pre-update baseline.

Applied staging migration: `20260916111044_workshop_move_cascade_affected_chain.sql`. The migration was created with the CLI and its filename aligned with the version recorded by the staging migration tool. Production and outbound email delivery were not changed.
