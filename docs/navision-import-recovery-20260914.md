# Navision import recovery — staging

A retained 269-row Broome snapshot reproduced the reported clean-preview/apply rejection. Preview returned 269 changed rows and no invalid/conflicting rows. Apply failed with SQLSTATE `55P03` while the vehicle projection trigger waited for `workshop_station_revision`, held by the automatic workshop clock. The diagnostic used a three-second lock timeout; the API's inherited lock timeout is eight seconds. Existing clock runs were holding those rows for roughly a minute.

The workshop validation performance migration fixes the long-running clock. No Navision identity, dealer, source, retention, lifecycle or deferred commit guards were removed.

The upload screen now reports lock contention, cancellation, uncertain connection results, and safety blockers accurately. It retries at most twice for explicit PostgreSQL transaction rollback errors (`55P03`, `40P01`, `40001`), with one- and two-second pauses. Retries reuse the same source rows, approved preview and idempotency key. A changed importer/preview cancels further dispatch. Timeouts, validation failures and unconfirmed network outcomes are not automatically retried. Failed or uncertain submissions retain the preview.

Verification against staging, entirely inside rollback:

- Retained 269-row snapshot: preview 2.28 seconds, zero flags.
- Apply, forced deferred commit constraints, and exact receipt replay: 13.05 seconds combined.
- Exact replay returned the same import batch.
- All workshop bookings were unchanged; canonical Navision parity reported zero mismatches.
- The Navision-specific JavaScript suite passed all 17 tests, including bounded retries, unchanged request identity, authority cancellation, and uncertain-result handling.

`tests/navision_import_recovery_rollback.sql` contains the repeatable rollback check and additionally asserts vehicle lifecycle preservation. The actual rejected 266-row paste was not retained by the website, so the successful reproduction used the current retained dealer snapshot. No customer import was permanently approved by this diagnostic.

An explored vehicle revision suppression change was omitted because planners can rely on refreshed vehicle versions for optimistic concurrency. The release keeps those invalidations intact.
