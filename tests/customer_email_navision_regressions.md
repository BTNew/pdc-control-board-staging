# Customer-email import regressions

Run these files **separately and serially** against staging. Each opens its own transaction, sets a 60-second statement limit, and rolls back every fictional fixture. Database execution belongs to the release reviewer.

| File | Real import cycles | Coverage |
| --- | ---: | --- |
| `customer_email_navision_commit_rollback.sql` | 1 | Current deployment baseline, newly added order baseline, changed production month, approved importer without Sales access, private ACL/RLS, status inference, role metadata/sign-out spoof rejection, PDC fingerprints |
| `customer_email_navision_offline_rollback.sql` | 2 | Built then shipping/ETA captured from two immutable batches deferred together, pending built preserved, no Sales page reads, idempotent replay and unique drafts, PDC fingerprints |
| `customer_email_navision_retry_rollback.sql` | 1 | Failed private observer cannot reject a true Navision import, exact retained retry facts, review/save cannot skip a failed milestone, recovery and obsolete ETA protection, PDC fingerprints |
| `customer_email_navision_scope_rollback.sql` | 2 | True import creates a review draft, identity-conflict protection, optimistic versions, true import reassignment removes prior salesperson read/write access, role metadata cannot bypass scope, PDC fingerprints |

The prior combined regression repeated whole-dealer imports to establish every setup step and exceeded the postdeployment request timeout. These files establish fictional previously known backend/observation records under the current successful authoritative Broome receipt, then use the unchanged approved public preview/apply path for every transition under test. The first-new-order case still uses a genuinely new importer-created backend row. Existing current dealer rows stay in every import payload; no dealer import guard is disabled or weakened.

All generated customer updates remain drafts. No external email is sent. Every feature compares vehicle operational fields, workshop bookings and isolated ordering state before/after, then rolls back.
