# Non-Navision Department 138 booking lookup

Bhavesh reported that keys 509 and 405 showed “Bookings could not be checked”. The native board had approved, active Tune PMG vehicles for both keys, but the frontend dealer resolver returned an empty scope when the authenticated vehicle lacked a Navision link. Search therefore omitted their requests before contacting the booking RPC.

For authenticated, visible Tune PMG rows with an exact UUID and Stock identity, known sole Department 138 membership now supplies the PMG request scope 14450. Explicit Navision or exact bound dealer evidence retains precedence; conflicting identities/dealers, unknown membership and mixed departments still fail closed. This does not authorize a booking: the unchanged server RPC validates the actor and native approved active vehicle/job relationship.

The root runtime and cache versions change only. No Karratha assets, database functions, bookings, job hours, parts confirmations, conversion or QC gates change. Regression coverage exercises the native DTO mapper, both reported identities, the actual planner/data-service request, denial propagation and negative scope cases. A separate read-only database fixture using the verified delegated identity returned successful empty booking lists for both vehicles; this is not a browser session test.
