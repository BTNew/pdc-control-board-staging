# Dealer delivery completion and compact operation reviews

Confirmed current Navision `Delivered - At Dealer` now closes an exactly linked PMB vehicle, even when its collection was not recorded. It moves to Completed Vehicles and its queued, planned, running and stopped bookings are cancelled. Allocations and timers are released; booking history, operation lines, recorded hours, Parts, QC and collection evidence remain intact. No work completion, QC sign-off or transport duration is inferred from the Navision status.

The rule runs during source updates, canonical linking and explicit reconciliation. Replays are idempotent; completed vehicles cannot receive new active bookings. Other dealer statuses, missing rows, ambiguous links and unrelated vehicles do not qualify. The existing import preview authorization and exact-preview hash checks remain in place; the preview now discloses the final-delivery effect.

The staging backfill reconciles only current, exactly linked final-delivery records using the same audited rule. Stock 12311009 is Completed and has no active PMB bookings. The post-repair audit found no remaining qualifying linked vehicles with active allocations or an open lifecycle. Booking cancellations are retained rather than purged.

Sales PMB summaries give Completed precedence over stale booking summaries. The updated operation review stylesheet is scoped to PMB New Vehicles: compact padding and comparison panels, workshop/hours/actions together, wrapping descriptions and visible validation. Smaller screens stack the controls. Karratha's native runtime and existing styles remain frozen.

## Verification

- 1,701 JavaScript regression tests passed.
- Six staging rollback scenarios passed before the committed backfill: queued, planned, running, stopped, newly linked and direct repair. They checked cancellation audit, assignment release, rebooking prevention, replay, retained work/Parts/QC and unrelated booking lifecycle.
- Seven completed-history rollback checks passed after the backfill: replay, non-final status protection, missing source, retained milestones, immutable receipts, statistics and lifecycle history. No elapsed dealer-transit fixture was available; null transit data was retained without manufacturing a duration.
- Broome and Pilbara preview checks passed, with the new rule included in the preview hash. No import was committed by these tests.
- Runtime Pages allowlist validation passed. The new cancellation audit table is private, has RLS, and deliberately has no browser policies. The security advisor reported no warning for the new private functions/table.

The Service Codes history was verified independently: 6 October 2026, 4:40 pm Perth; 6,855 source lines, 6,419 accepted and 436 held for review across 42 committed batches. Held lines still require review and were not automatically approved by this change.

All database repairs and rollback checks targeted staging. No production restore or email send was performed.
