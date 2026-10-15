# Fitter assignments after bay moves

Moving an unstarted booking between bays could leave its primary fitter attached to the previous bay's default mechanic. The destination mechanic's iPad therefore had no job to display, although the booking was visible in that mechanic's bay.

The central move function now follows the destination bay's active default mechanic when the current assignment came from the previous bay default. This applies to planned/queued work with no recorded start or fitter progress. Explicit reassignment/team history and a different manually selected mechanic are preserved. Same-bay time changes and work already underway retain their fitter. Existing locks, leave checks, overlap checks, assignment history and helper handling remain in place.

A separate booking validator query counted unreleased historical assignments even when their booking was soft-deleted. It now requires a non-deleted, active parent booking, matching the dedicated technician conflict helper. A lifecycle trigger releases the reservation when an enabled-planner booking becomes deleted or inactive, and the migration releases any existing stale reservations. Assignment rows remain for history. The active-assignment exclusion constraint remains intact, and real fitter conflicts still reject atomically.

The rollback-only destination-bay regression exercises the restricted fitter queue/detail refresh after a cascade move, manual assignment protection, retained history, same-bay moves, active fitter conflicts and deleted-booking conflicts. It runs only in the owned loopback database and is included in the full functional monitor. Database and browser-code checks do not establish actual iPad/browser interaction.
