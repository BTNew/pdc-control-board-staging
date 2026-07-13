# PDC Control Board Supabase Pilot Rollout

## Goal
Move the PDC Control Board from single-browser `localStorage` operational storage to a secured multi-user Supabase deployment with Microsoft 365 login, role-based access, audit history, conflict protection, and realtime updates.

## Current project

- Supabase project URL: `https://vjdtsswhroyguxyfjdkt.supabase.co`
- Project reference: `vjdtsswhroyguxyfjdkt`
- Current static app remains available for offline/testing.
- Online deployment must not include operational vehicle records in `data.js`.

## Secrets policy

Safe in browser/developer config:

- Supabase project URL
- Supabase project reference
- Supabase publishable key beginning with `sb_publishable_`
- Microsoft tenant ID
- Microsoft client/application ID

Never commit or send through ordinary chat:

- Supabase database password
- Supabase secret key
- legacy service_role key
- Microsoft client secret
- MFA recovery codes

## Build separation

The pilot must keep two modes separate:

1. **Offline tester**
   - Current static/localStorage app.
   - May keep fixture pages such as `test-75.html`.
   - Used for parser/UI regression tests.

2. **Online pilot**
   - Supabase auth + database.
   - `data.js` must be empty/fallback only.
   - localStorage only for UI preferences: filters, column widths, print preferences.
   - source uploads stored in private Supabase Storage buckets.

## Implementation phases

### Phase 1 — Database foundation

- Apply `supabase/migrations/001_initial_schema.sql`.
- Apply `supabase/migrations/002_rls_policies.sql`.
- Apply `supabase/migrations/003_rpc_functions.sql`.
- Create private Storage bucket for source documents after project access is available.

### Phase 2 — Auth foundation

- Configure Supabase Authentication → Providers → Azure/Microsoft.
- Redirect URI in Microsoft Entra app:
  - `https://vjdtsswhroyguxyfjdkt.supabase.co/auth/v1/callback`
- Supabase Site URL during development:
  - `http://localhost:8765/`
- Supabase Redirect URLs during development:
  - `http://localhost:8765/`
  - `http://localhost:8765/**`
- Disable unused login providers after Microsoft login is confirmed.

### Phase 3 — Browser adapter

- Add Supabase login and signed-out screen.
- Replace manually entered operator name with authenticated identity.
- Load the approved PDC role from `pdc_user_roles`.
- Block authenticated-but-unapproved users from vehicle data.
- Subscribe to vehicle changes via Supabase Realtime.

### Phase 4 — Data conversion

- Keep existing Navision, PO and job-card parsers.
- Send validated import results into protected database functions.
- Store permanent vehicle IDs and aliases for stock/VIN/Toyota order/job card matching.
- Use version checks so stale browser tabs cannot overwrite newer changes.
- Write audit events for moves, imports, role changes, deletes, restores and RFT actions.

### Phase 5 — Pilot testing with synthetic data

Required before live vehicle/customer data:

- Signed-out users cannot retrieve vehicle records.
- Microsoft-authenticated but unapproved users cannot retrieve vehicle records.
- Viewers cannot move or edit vehicles.
- Operators cannot import, restore, delete, or administer users.
- Importers can run approved imports but cannot administer users.
- Administrators can manage users and reference lists.
- Refreshing the page preserves changes.
- Two computers see a vehicle move without refreshing.
- Two simultaneous edits to the same vehicle produce a conflict.
- Reimporting the same Navision file does not create duplicates.
- RFT rules remain enforced.
- Required boxes are not automatically ticked.
- Audit history identifies the authenticated operator.

## Required inputs still needed

- Supabase publishable key (`sb_publishable_...`).
- Microsoft tenant ID.
- Microsoft client/application ID.
- Pilot users with email and role.
- Decision on Netlify pilot URL after first clean deployment.
