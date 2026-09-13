# Updated operation approval and bay rescheduling

An imported addition or changed operation for an existing board vehicle remains pending in **New Vehicles → Updated operation lines** until an operator approves it. Previously, approval rolled back when the changed hours resized an existing bay booking, and the browser also rejected any receipt showing changed bookings.

**Approve change & update bookings** now saves the accepted operation, recalculates the station's complete estimate, extends its existing bay booking and shifts affected later bookings in one transaction. The result lists the affected stock numbers, stations, bays, dates and hours.

Scheduling preserves the existing chronological queue, technician assignments and actual job history. It follows each affected vehicle into later stations, including further vehicles displaced along the way. It allows five wall-clock hours between a vehicle's jobs, then uses the next open workshop time: Monday–Friday 07:00–17:00, Saturday 08:00–12:00, Sunday closed. Admin blocks, technician leave, Sublet absence and existing location/ETA rules still apply.

Started or stopped jobs keep their original start and lifecycle. A conflict requiring a different already-started job to move holds the approval with a clear message; the operation remains pending and nothing is partly saved. Duplicate approval requests return the same receipt. Sublet and stations without an existing bay booking do not create workshop bookings.

The new authenticated approval endpoint is deployed separately from the previous endpoint, so cached older pages cannot accept the new scheduling result incorrectly. Its internal scheduling helper is not callable by browser roles. The existing generic scheduler and previous approval endpoint are unchanged.

Verification on 13 September 2026:

- 469 Node checks passed across the full existing suite and the new approval checks.
- 38 database integration assertions passed inside a transaction that was rolled back, including added and modified imports, 7 + 2 = 9 Hoist hours, recursive queue shifts, technician conflicts, weekend hours, started/stopped/queued jobs, invalid approvals and repeat requests.
- Seven isolated browser workflow checks passed with no external requests and no browser errors, including success, conflict/retry and session changes.
- All pre-existing vehicle and booking rows matched their before-test snapshots. No customer operation was approved for testing.
- Staging migration 20260913060848 was applied and its functions and execution privileges were read back. The new endpoint intentionally permits approved authenticated operators; anonymous callers and direct calls to its internal helper are denied.

The Supabase advisor reports the new endpoint as an intentional authenticated security-definer RPC. Its actor, role, snapshot and staging checks are covered by the integration tests. See the [Supabase authenticated security-definer guidance](https://supabase.com/docs/guides/database/database-linter).

