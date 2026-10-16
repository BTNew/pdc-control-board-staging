# Reviewed Department 138 operation categories

The private owner-review workflow applies a reviewed category to an exact existing Department 138 line. It preserves the source operation, job-card identity, original and effective hours, staff adjustments, reservations and completed work. It does not approve vehicles or operation updates.

Only a staging management connection with no impersonated user can submit a review. App users continue to use the normal versioned category editor. The review binds each vehicle/version and complete current line, rejects stale or duplicate identities, records the original line and reason, and returns one outcome per line. An identical request is idempotent; changed intent under the same key is rejected. Customer payloads and receipts remain in the private database schema, not in this repository.

Existing explicit category choices, completed stages and booked scopes remain protected. An unstarted whole-job reservation can retain category labels within its existing physical station; moving its lines to another physical station requires the normal booking review. Logistics entries without a supported workshop category are held. Native initial intake and operation-update gates remain in place.

Later explicit staff category choices take precedence. Changing hours alone retains the reviewed category and the new staff hours. A change to the operation identity/description or a later staff station choice invalidates the older review's automatic application. Required-work flags are recalculated through the existing native function, with transaction guards protecting all source operations, staff adjustments, bookings and completed work.

The regression include runs after the existing category fixture setup in a disposable database transaction. It covers exact routing, explicit zero hours, later staff hours and overrides, stale/replayed intent, department isolation and protected reservations. It must not be run against live operational records.
