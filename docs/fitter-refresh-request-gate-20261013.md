# Fitter job refresh repair — 13 October 2026

The mechanic roster advertised the incremental job endpoint, but the PostgREST pre-request gate omitted that endpoint from its fitter allowlist. Selecting a mechanic therefore failed before reading their assigned jobs. The inner read authorization had already supported this endpoint since September; the outer gate had not been updated with it.

The migration adds only get_fitter_refresh to the existing POST allowlist. The exact UID/email, active approved role, existing command paths, inner read-only authority and controller restrictions remain. It changes no accounts, grants, vehicles, operations, bookings, hours or Department135 functions.

The PMG fitter screen now distinguishes load failures from failed writes, and clears a previous loading error after a successful read. The isolated Karratha fitter asset is pinned independently at its original baseline.

Validation: reproduced roster success followed by refresh denial in a disposable local restore of the staging backup. The restored eight relevant public functions matched live fingerprints. The repair passed John queue loading, disabled/mismatched/anonymous denial, wrong-method and unrelated-route denial, existing fitter/controller permissions, incremental scope/timer checks and fitter lifecycle/progress checks. Synthetic accounts and work were local and rolled back; the server stopped and plaintext files were removed. The older incremental test initially lacked an assigned booking; it passed with a synthetic local fixture. All 1,727 Node tests and the frontend secret/runtime artifact checks passed.

Staging migration 20261013042847 was applied and read back. The inner authorization and seven unchanged public function hashes still match. John had zero assigned active jobs at readback; this repair does not allocate a vehicle. Actual iPad interaction remains to be confirmed by the workshop. No signed-in staff session was impersonated on the working database.
