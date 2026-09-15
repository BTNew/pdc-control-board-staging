# Emergency vehicle priority — 15 September 2026

Control Board now accepts an exact stock number for an active vehicle at PMB. Preview lists its proposed station bookings and the other bookings that will move. Apply performs the reviewed schedule atomically and refreshes the board.

The scheduler creates missing approved workshop requirements through the existing booking API, chooses the earliest finishing eligible bay for each remaining station, and moves conflicting planned work later, including dependent stations on affected vehicles. It preserves running/fixed work, operation hours, bay efficiency, workshop calendar, technician availability, Sublet absence and the one-hour vehicle handover. Pending reviews or unresolved scheduling conflicts stop the action without partial changes.

Operator/administrator authorization, staging-project checks, resource locks, expiring state-bound previews and actor-bound retry receipts protect the mutation. The public RPC uses SECURITY INVOKER. Internal helpers and receipts are in a private schema. Receipt RLS has no policies and no client table grants by design; the advisor reports that as informational. No new public security-definer warning was introduced.

Applied staging migrations:

- `20260915092243` workshop_emergency_priority (source file 20260915091650)
- `20260915092530` workshop_emergency_priority_cache (source file 20260915092523)
- `20260915093019` workshop_emergency_priority_validation (source file 20260915092930)

Validation: 18 main rollback assertions, 8 edge-case rollback assertions, and 9 client tests passed. Covered priority/ripple behavior, cyclic updates, efficiency, cross-station handover, unchanged running jobs, missing requirements, after-hours scheduling, inactive bays, pending reviews, stale preview, preview rollback, authorization and idempotent retry. Final synthetic graph calculation: 1.46 seconds; this is not a guarantee for every schedule size. All synthetic database changes were rolled back; receipt count remained zero. Browser fixture checked preview and apply layout. No customer vehicle was prioritised during deployment.

Known operating limits: vehicles must already be at PMB and have approved workshop work. Running stoppages with unknown release times can prevent a safe plan. Emergency priority is a deliberate action, not a permanent override of subsequent scheduling edits.
