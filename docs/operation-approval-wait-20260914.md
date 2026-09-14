# Operation approval while the workshop clock is busy
The automatic workshop clock was observed taking 46–47 seconds each minute. Approval waits up to five seconds for its lock per request; two retries often expired while the same clock cycle was still running. An exact stock 12379669 rollback probe reproduced lock timeout 55P03. Outside that contention, approving the 0.2-hour fuel line succeeded and extended the started Bus 4×4 booking from 72.5 to 72.7 hours without changing its start.

The browser now tolerates one clock cycle using a 65-second retry deadline and at most 12 retries. It shows a waiting message and retains the exact change, snapshot, station, hours and idempotency key. Only the server's explicit rolled-back busy response permits another attempt. Unknown network outcomes and genuine scheduling conflicts are not automatically retried. Sign-in, token, role or request changes cancel waiting. A confirmed receipt still validates all operation and booking details before showing success.

Validation covers successful approval after a simulated 47-second lock, elapsed deadline, request cap, identical request reuse, cancellation, duplicate clicks, uncertain responses and protected scheduling conflicts. The actual customer approval was exercised only inside rollback transactions; it remains pending for the operator.

A calendar-count optimization was explored and tested but did not sufficiently reduce the full clock runtime. It is not part of this release. No database functions, locking rules, schedule calculations or customer records are changed by this release.

