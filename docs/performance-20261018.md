# Planner and calendar performance, 18 October 2026

Returning to a recently viewed planner can reuse its in-memory snapshot after a new authenticated station revision confirms freshness. The cache holds at most eight scopes for 90 seconds, is cleared on mutations, revision events and lost authority, and never persists to browser storage. A revision probe has a 1.5-second deadline before falling back to the normal full read. Permission failures cannot restore retained rows. First visits, changed revisions and expired entries still load full snapshots.

The background calendar availability helper reads its six settings in one query instead of six. Its calendar predicates, access grants and function properties are retained. The migration refuses a different source definition or a non-staging environment. No scheduling cadence, email-import interval, booking, source hour or role is changed.

Validation: 1,835 Node tests passed, including 17 new return-navigation, authority and race tests. Frontend secret scan and Pages allowlist validation passed. In a disposable loopback staging copy, 10,080 minute samples, seven edge calendars, null input and the current clock plan matched the previous implementation. Calendar sample time fell from 400.428 ms to 300.666 ms in that run. Clock-plan time fell from 8,814.248 ms to 4,854.772 ms, but this sequential benchmark includes warming/order effects and is not a guaranteed live speedup. The backup's older clock was aligned using the already-published clock migrations inside the disposable transaction. The monitor still records that original backup/live version gap; these results are targeted coverage, not an all-clear.

`tests/calendar_settings_parity_rollback_20261018.sql` retains the original calendar as a temporary oracle for future loopback regression checks. It compares eight full weeks of minute samples with rollback-only setting variations. Do not run operational experiments against the working board.

A separate station projection experiment was withheld: exact payload parity passed but timing gains were inconsistent. Existing advisor findings and access rules were not relaxed for performance.
