# Combined Navision upload

The default upload choice is **Combined · 014450 + 001234 + 002345**. A single
file can contain any of these dealers. The original Dealer column determines
each row's scope; the filename does not. Individual-dealer choices remain.

Preview shows the three dealer totals and any excluded rows. Craig's supplied
example contains 598 rows for 014450, 46 for 001234, 25 for 002345 and one for
090000. The first 669 belong to this combined upload; the 090000 row is explicitly
excluded. A dealer absent from the file is not treated as an empty snapshot.

One confirmation applies the included groups in a single database transaction.
Existing per-dealer validation, initial-scope administrator approval, retention,
duplicate checks and revision checks still apply. A failed group rolls back all
groups; replaying the same request returns its original receipt. First uploads
to previously empty scopes still require the existing administrator baseline
approval step. Other dealer uploads are unaffected.

An exact, unambiguous match to a vehicle already on the board establishes its
Navision link and invokes the existing detail/location refresh rules. This path
does not create vehicles or activation approvals. Existing job cards, manual
salesperson overrides and PMB/progress location latches remain protected.

Large-file support uses set-based dealer partitioning and indexes for the exact
stock predicates. Deferred parity checks use the original parity predicate for
the vehicles affected by a changed row, including its previous/new stock and
canonical links. The full-board parity report remains unchanged. RPC timeouts
are scoped to these combined endpoints, not account-wide database settings.

Validation includes the JavaScript regression suite, synthetic transaction tests
for failure rollback, replay, changed requests, stale previews, role restrictions,
dealer exclusions, existing-vehicle linking and parity rejection. Full-file
verification uses the supplied example only in transactions that are rolled back;
customer data is not included in this repository.

Release checks passed: 1,016 JavaScript tests, frontend secret scan (zero
findings), synthetic rollback/authorization/identity tests, and the complete
669-vehicle sample apply including deferred constraints in under 55 seconds.
The full sample test rolled back all data changes and created no vehicles.

Security review: combined receipts are in a private schema with RLS and no client
grants. The three authenticated SECURITY DEFINER endpoints have explicit active
application-role and staging checks; anonymous calls are denied. The private
receipt table intentionally has no client RLS policies.
