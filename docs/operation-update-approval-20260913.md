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

## Concurrent booking updates repaired

The first release passed isolated scheduling scenarios but missed a lock inversion with the automatic workshop clock. Approval could own a station revision row while waiting for a booking row; the clock owned the booking row and waited for that revision. An exact pending-vehicle rollback reproduced PostgreSQL deadlock 40P01.

Migration 20260913063859 coordinates with the existing clock lock before operational writes, acquires booking locks before vehicle and required-work updates, and uses non-waiting row locks to avoid contention cycles with other planner or import actions. Scheduling calculations and the clock itself are unchanged. Transient contention returns a specific busy result after rolling back; the browser retries that result twice using the same request and approval key. Network errors and ordinary protected conflicts are not automatically retried. Session or permission changes cancel retries.

A failed approval also no longer labels a successfully loaded, empty search result as Queue unavailable. Pending operation updates remain visible below the new-vehicle list.

Follow-up verification: 477 Node checks passed, all 38 database regression assertions passed, and approval against the actual pending vehicle succeeded in rollback both before and after applying the repair: Hoist increased from 7 to 9 hours and two dependent bookings moved. An independent session holding a booking row produced a prompt retryable busy result with zero booking writes. A separate clock-holder experiment did not establish overlapping sessions and is not counted as a passed concurrency test. All verification transactions rolled back; the customer operation remains pending for approval.
