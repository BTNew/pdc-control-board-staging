# Reviewed Department 138 operation categories

The private owner-review workflow applies a reviewed category to an exact existing Department 138 line. It preserves the source operation, job-card identity, original and effective hours, staff adjustments, reservations and completed work. It does not approve vehicles or operation updates.

Only a staging management connection with no impersonated user can submit a review. App users continue to use the normal versioned category editor. The review binds each vehicle/version and complete current line, rejects stale or duplicate identities, records the original line and reason, and returns one outcome per line. An identical request is idempotent; changed intent under the same key is rejected. Customer payloads and receipts remain in the private database schema, not in this repository.

Existing explicit category choices, completed stages and booked scopes remain protected. An unstarted whole-job reservation can retain category labels within its existing physical station; moving its lines to another physical station requires the normal booking review. Logistics entries without a supported workshop category are held. Native initial intake and operation-update gates remain in place.

Later explicit staff category choices take precedence. Changing hours alone retains the reviewed category and the new staff hours. A change to the operation identity/description or a later staff station choice invalidates the older review's automatic application. Required-work flags are recalculated through the existing native function, with transaction guards protecting all source operations, staff adjustments, bookings and completed work.

The regression include runs after the existing category fixture setup in a disposable database transaction. It covers exact routing, explicit zero hours, later staff hours and overrides, stale/replayed intent, department isolation and protected reservations. It must not be run against live operational records.

## Approved email-import split, 17 October 2026

The owner's approved review supplies 299 normalized description matches: 283 category rules and 16 deliberately held packages. The database stores only normalized description hashes and categories; the source descriptions, affected jobcards, approval manifest and receipts stay in the private review directory outside Git.

New Department 138 operation identities, and changed descriptions on existing identities, use these rules through the canonical operation projection. Required-work recalculation and planner category estimates already consume that projection. Case and repeated whitespace are normalized. Unknown descriptions and held packages become `UNALLOCATED_MAPPING_REVIEW`; they do not silently default to Mechanical. Nominal or missing internal-bay hours also require review, while an explicitly represented zero-hour QA task remains QA. Source hours are never invented, multiplied or redistributed.

The approved examples retain pre-delivery in Electrical and conversion-specific super-single tyres in Mechanical. Normal tint and tyre work use the existing shared stages. Supplier work uses Sublet; external pit inspections use Pit. Combined packages and externally fulfilled tyre fitting remain held until their labour/fulfilment is clarified.

Existing operation signatures are captured privately at deployment and retain their current projection. Completed or rejected lines, staff category overrides, manual station choices, matching owner reviews and booked scopes remain protected. The migration asserts that every pre-existing Department 138 vehicle projection is identical before and after installation. It neither moves existing bookings nor changes vehicle approval, import schedules, email processing identity or completion history.

Synthetic PostgreSQL tests are in `tests/dept138_import_split_fixture.sql` and `tests/dept138_import_split_assertions.sql`. Run only in an empty disposable database: install the fixture, the migration's marked RULE STORAGE and CANONICAL PROJECTION sections, then the assertions. The fixture is not a migration for any working database. Tests cover category precedence, normalization, department isolation, missing/nominal estimates, baseline preservation, updated descriptions, staff overrides, booking scopes, completed stages and restricted helper access.
