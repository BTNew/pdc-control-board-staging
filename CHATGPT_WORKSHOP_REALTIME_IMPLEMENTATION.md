# ChatGPT Workshop Planner realtime implementation

Date: 2026-07-16
Release marker: `2026.07.16.27-workshop-realtime`
Source handoff base: `a74aee1c145875cd56ce23e378dd02968c9137cb`

## Result

This package converts the Workshop Planner frontend from authoritative browser-local booking storage to the existing Supabase/PostgreSQL workshop foundation when an approved user is authenticated.

Repository integration keeps this cutover explicitly disabled by default. Set `workshop.sharedData` to `true` only after migration 009, database backup, vehicle reconciliation and legacy booking import have passed. Viewer accounts remain read-only in both shared and local review modes.

In shared mode:

- bookings are loaded from Supabase
- bays, default technicians, technicians and sublet providers are loaded from Supabase
- the workshop queue and booking vehicle cards are built from Supabase vehicle rows and `source_payload`
- create, move, resize, reassign, start, stoppage, resume, complete and return-to-queue actions use protected RPCs
- version conflicts are rejected instead of silently overwriting another controller
- bay and technician overlap checks are repeated and enforced in the database transaction
- Supabase Realtime changes trigger a fresh authoritative snapshot on every connected computer
- localStorage is retained only as a review-mode fallback and for harmless view preferences
- authenticated `viewer` users are blocked from mutating workshop data
- the UI displays whether it is using the shared database/live-sync connection or local review mode

The planner fails closed if shared mode is configured but the required database contract is unavailable. It does not silently write operational changes to localStorage.

## New files

- `workshop-data-service.js`
- `supabase/migrations/009_workshop_planner_frontend_contract.sql`
- `test_workshop_data_service.js`
- `test_workshop_data_service_runtime.js`
- `CHATGPT_WORKSHOP_REALTIME_IMPLEMENTATION.md`

## Main changed files

- `app.js`
- `workshop-planner.js`
- `pdc-supabase-config.example.js`
- `backend/build_login_static.py`
- Workshop migration and planner tests
- Versioned HTML/test pages

## Database contract added by migration 009

Migration 009 adds or strengthens:

- atomic combined booking update RPC
- one open booking per vehicle/stage protection
- case-insensitive technician/provider uniqueness
- protected technician creation and bay-default assignment RPCs
- queue booking reuse rather than duplicate creation
- live-start conflict enforcement
- optimistic version checking
- migration preflight checks that stop instead of silently discarding duplicate data
- Perth business-time calculations for Monday-Friday, 8:00am-4:00pm
- correct multi-day scheduled end calculations
- correct working-time actual duration and stoppage calculations
- recalculation of existing booking/assignment schedule ends created by the earlier continuous-clock implementation
- removal of browser execute permission from the superseded split move/resize/reassign RPCs
- a `frontend_contract_version` setting used by the browser to fail closed when migration 009 is absent

## Deployment sequence

Do this in a staging Supabase project first.

1. Preserve the current browser backup and database backup.
2. Apply migrations `001` through `009` in order.
3. If migration 009 stops on duplicate technician names or multiple open bookings for the same vehicle/stage, reconcile those rows manually and rerun it. Do not delete rows blindly.
4. Confirm every active workshop vehicle exists in `public.vehicles` with a stable `permanent_vehicle_id`. Populate canonical fields and retain current operational fields in `source_payload` during the wider vehicle migration.
5. Use `scripts/workshop_planner_legacy_extract.js` against a current CRM backup to produce a reconciliation file for existing browser-local plans. Import and verify those plans before relying on shared mode.
6. Install the real Supabase publishable key in `pdc-supabase-config.js`. Never place a service-role key, database password or Microsoft secret in the browser bundle.
7. Build and publish all frontend assets, including `workshop-data-service.js`.
8. Test with two different approved accounts in two browser profiles or computers.
9. Move a booking in browser A. Confirm browser B changes without refresh.
10. Attempt overlapping bay and technician bookings from both browsers at nearly the same time. Confirm only one succeeds and the other receives a clear conflict.
11. Test create, resize, start, stoppage, resume, completion and return-to-queue actions.
12. Keep the old browser backup until vehicle counts, booking counts and stage/status totals reconcile.

## Required two-user acceptance checks

- Browser A move appears in browser B automatically.
- Browser B resize appears in browser A automatically.
- Two simultaneous moves of the same booking produce one success and one version conflict.
- Two simultaneous bookings into the same bay/time produce one success and one bay conflict.
- The same technician cannot be scheduled in two bays at overlapping times.
- Back-to-back bookings remain allowed.
- A long Friday booking carries into Monday/Tuesday rather than into the weekend.
- A viewer can see the board but cannot change it.
- Sign-in as another user causes a fresh data snapshot rather than reusing the prior user’s cache.
- Removing network access blocks changes instead of saving a private local copy.

## Honest remaining work

This integration is not a live deployment. The uploaded archive contained unrelated mailbox attachments, so it was treated as untrusted and those files were not extracted into or added to the repository. No publishable deployment key, database access or GitHub credentials were added by this integration.

The following work is still required:

- run the migrations in the actual Supabase project
- import and reconcile the real browser-local workshop bookings
- confirm the real `vehicles` table is populated and current
- complete the broader application migration for non-workshop screens that still use browser-local edits
- replace native HTML drag/drop with the planned pointer-based interaction layer
- extract the planner rendering/interactions further out of the global application code
- consume closures, holidays, overtime, breaks and leave dynamically from `workshop_settings`; this release enforces the present Perth Monday-Friday 8:00am-4:00pm rule
- consider incremental realtime patching if the dataset grows enough that full snapshot refreshes become expensive

## Security boundaries retained

- no secrets were added
- no mailbox attachments or unrelated customer payloads from the uploaded archive were added
- browser code uses only the Supabase publishable key
- RLS remains enabled
- direct workshop table writes remain revoked
- operational mutations use role-protected security-definer RPCs
- service-role keys must remain server-side only
