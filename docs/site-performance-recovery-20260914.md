# Navision and workshop performance recovery

A clean Navision preview could fail during apply because the minute workshop clock held station revision locks for 61–64 seconds. This also consumed database capacity during normal browsing. The fix keeps the scheduling algorithm and all conflict guards, but checks the affected vehicle's eligibility directly, evaluates its duration estimate once, and counts calendar intervals through the existing availability predicate.

The complete clock ran in 4.4 seconds for 95 booking moves across three linked groups in a rollback test, compared with recent 61–64-second scheduled runs. Membership, duration and calendar parity passed 521 checks, including 386 eligible vehicle/station memberships, weekends, closures, breaks, overtime and malformed settings. No customer scheduling changes were committed by these tests.

After deployment, the first two automatic staging clock runs finished in 4.287 and 4.400 seconds. The post-deployment Navision rollback check previewed 269 rows in 2.321 seconds, applied them with deferred constraints in 10.645 seconds and replayed the same receipt in 2.315 seconds. Booking and lifecycle data remained unchanged.

The vehicle-location snapshot contains about 6.5 MB for 101 vehicles. Concurrent reads now keep one fresh trailing request instead of downloading that snapshot for each caller. A 41-call stress scenario made two downloads with one same-session request in flight. Later mutations still require a fresh read; old-session results cannot be reused. Vehicle-only revision events retain vehicle and eligibility refreshes while skipping unrelated Navision and workshop reference reloads. Manual refresh remains comprehensive, and queued full refreshes cannot be downgraded by a later vehicle-only event. The coordinator also avoids an intermediate duplicate board render.

Navision recovery retains the same preview and idempotency key. Only explicit database lock, deadlock or serialization rollbacks receive bounded automatic retries. Source conflicts, uncertain transport outcomes and timeouts receive specific explanations instead of a generic rejection.

Validation: 584 Node tests passed before release, plus the database parity and complete Navision preview/apply/replay checks documented in `navision-import-recovery-20260914.md`. Release checks verify staging identity, referenced assets, changed-file contents and deployment. Existing permissions, source identity checks, booking conflicts, five-hour vehicle handovers and workshop opening hours are preserved. No production changes are included.
