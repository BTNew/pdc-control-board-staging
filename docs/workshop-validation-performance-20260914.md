# Workshop validation performance

The automatic clock was taking 60.9–64.2 seconds every minute, holding booking and revision locks that blocked approvals and Navision imports.

The planner mutation guard rebuilt the full station queue and calculated every vehicle’s hours for each individual booking move. It only used membership in that queue. The replacement checks the identical active, visible, location, ETA and outstanding-work predicates for the single vehicle. All synthetic exceptions and other guards remain intact.

The duration lookup now materializes its existing estimate once. Calendar counting uses the canonical minute predicate at interval boundaries, with the original minute scan as a fallback for unusual legacy windows. Calendar settings and scheduling rules do not change.

Measured on current staging data, inside transactions that rolled back all changes:

| Check | Before | After |
| --- | ---: | ---: |
| Full clock, 95 moves / 3 linked components | 60.9–64.2 seconds (current cron) | 4.40 seconds |
| Calendar predicate calls in matched clock workload | 126,771 | 921 |
| Estimated hours calculations | 1,796 | 898 |

Both candidate full runs completed with no reported scheduling issues and passed immediate deferred constraints. The clock scheduling algorithm, five-hour vehicle gap, booking and assignment validation, resource locks, protected fields, and source-hour rules are unchanged.

`tests/workshop_booking_validation_performance.sql` passed 520 comparisons with no failures, including 386 eligible vehicle/station memberships, every active outstanding duration estimate, fractional-minute endpoints, closed days, breaks, overtime, missing settings, and malformed windows for both matching and unrelated dates. Temporary copies of settings isolate the calendar scenarios from customer configuration.

The migration fingerprints both replaced functions and their eligibility/calendar predicate dependencies. Owners, security modes and execution grants are retained with `CREATE OR REPLACE`.

An additional same-snapshot test compared the original dry-run plan with the optimized applied clock: all 95 movements and issue results matched exactly, the optimized run took 4.347 seconds, and protected booking/assignment field changes were both zero. Deferred constraints passed before the transaction rolled back. `tests/workshop_clock_movement_parity.sql` repeats this dry-run/apply comparison after deployment.

No customer booking was permanently moved by these tests. No migration was applied during investigation.
