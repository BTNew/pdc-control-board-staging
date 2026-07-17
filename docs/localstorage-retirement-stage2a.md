# localStorage Retirement — Stage 2A

Final report on every browser-local storage key touched by the PDC
Control Board, following the shared workshop reference-data migration
(technicians, salespeople, sublet providers, workshop bays, workshop
settings) to Supabase.

(This document supersedes the earlier draft at
`docs/stage2a-localstorage-retirement-list.md`, which is kept as
historical context only — this file is the authoritative final
version requested for Stage 2A freeze.)

## 1. Retired operational keys (Supabase is now sole authority)

The data behind these keys is now served **exclusively** from Supabase
via `workshop-reference-data-service.js`. The running application
never reads or writes these keys. They are left on disk (not deleted)
purely so the one-time browser-data importer
(`scripts/import_stage2a_reference_data.py`) can still read a given
staff computer's pre-migration local roster during manual
reconciliation. No code path treats them as authoritative.

| Key | Was used for | Now served by |
|---|---|---|
| `vehicleTrackingCorePdcMechanics:v1` | Mechanic/technician roster | `workshop_technicians` table, `list_technicians`/`add_technician`/`edit_technician`/`set_technician_active` RPCs |
| `vehicleTrackingCorePdcMechanicsRosterSeed:v1` | One-time seed marker for mechanics | n/a — seeding is now a database migration concern |
| `vehicleTrackingCorePdcSubletProviders:v1` | Sublet provider roster | `sublet_providers` table, `list_sublet_providers`/`add_sublet_provider`/`edit_sublet_provider`/`set_sublet_provider_active` RPCs |
| `vehicleTrackingCorePdcSubletProvidersSeed:v2` | One-time seed marker for providers | n/a |
| `vehicleTrackingCoreSalespersons:v1` | Salesperson roster | `salespeople` table, `list_salespeople`/`add_salesperson`/`edit_salesperson`/`set_salesperson_active` RPCs |
| `vehicleTrackingCoreSalespersonsSeed:v1` | One-time seed marker for salespeople | n/a |

Workshop bays and workshop configuration/settings **never had a
browser-local key at all** — no `WORKSHOP_BAYS_KEY` or
`WORKSHOP_SETTINGS_KEY` constant exists anywhere in the codebase, past
or present. The 38 real `workshop_bays` rows and the
`workshop_settings` rows were introduced directly in Supabase by
migrations 022/023 with no local-storage precursor to retire. The
hardcoded `PMB_STAGE_BAY_COUNTS` structural config (bay *count* per
stage) is a separate, intentionally-unmigrated concern — see Section 4.

## 2. Import-only legacy keys

Identical to the six keys in Section 1, specifically in their role as
read-only input to `scripts/import_stage2a_reference_data.py`. The
importer never writes to them; the running application never reads
them. This is a distinct usage note on the same six keys, not an
additional set of keys.

## 3. Remaining UI-only keys (unaffected by Stage 2A, genuinely harmless)

These remain legitimately browser-local, per-device display
preferences with no shared-authority concern and no migration need:

| Key | Purpose |
|---|---|
| `vehicleTrackingCoreColumnOrder:v4` | Per-device vehicle table column order |
| `vehicleTrackingCoreWorkflowWidthMode:v1` | Per-device layout width preference |
| `vehicleTrackingCoreRowWidthMode:v1` | Per-device row width preference |
| `vehicleTrackingCoreCurrentOperator:v1` | Legacy operator-name UI convenience (pre-Supabase-auth) |
| `vehicleTrackingCoreCurrentOperatorRole:v1` | Legacy operator-role UI convenience (pre-Supabase-auth) |

## 4. Explicitly out of scope for Stage 2A (tracked for Stage 2B)

- Vehicle/booking master data
  (`vehicleTrackingCoreNavisionOnlyEdits:v1`,
  `vehicleTrackingCoreNavisionOnlyVehicles:v1`) and the workshop
  planner's local booking rows (`workshopSavePlans()`). These remain
  browser-local by default and are only bypassed when
  `workshopSharedModeActive()` is explicitly enabled. Stage 2A covers
  shared *reference/lookup* data only, not vehicle/booking master data.
- `PMB_STAGE_BAY_COUNTS` (hardcoded structural bay-count-per-stage
  config) — a separate, intentionally-unmigrated concern distinct from
  the bay *record* data (active state, default technician) that Stage
  2A did migrate.

## 5. Confirmation: clearing browser storage does not remove shared data

Verified directly, both by code inspection and live testing against
the deployed staging site (`https://btnew.github.io/pdc-control-board-staging/`):

- `loadMechanics()`, `loadSalespersons()`, `loadSubletProviders()` in
  `app.js` read **exclusively** from
  `window.__workshopReferenceDataService` (backed by Supabase) and
  contain no `localStorage` fallback under any code path.
- `workshopBayIsActive()` / `workshopBayDefaultTechnicianName()` in
  `workshop-planner.js` read from the same shared service, with a
  fail-safe default (active/no-default) only when the service has
  not yet loaded — never a `localStorage` fallback.
- `getWorkshopConfiguration()`/`getCachedWorkshopConfiguration()`
  likewise have no `localStorage` involvement at any point.
- `CRM_BACKUP_STORAGE_KEYS` (the general browser-local backup/export
  list in `app.js`) explicitly excludes all six retired keys from
  Section 1, with an inline code comment recorded at the exclusion
  site.
- **Live verification this session**: on the deployed staging site,
  full create/edit/deactivate/reactivate cycles were run for
  technicians, salespeople, and sublet providers, plus workshop
  settings and bay updates — all correctly propagated through
  Supabase alone with zero page refresh. A browser holds no
  authoritative copy of this data at any point after initial page
  load; clearing `localStorage` (or even a full private-browsing
  session with no prior local data at all) has zero effect on
  mechanics, salespeople, providers, bays, or workshop settings,
  because the application never consults `localStorage` for any of
  them.

## 6. Verification method

1. Code inspection of `loadMechanics()`, `loadSalespersons()`,
   `loadSubletProviders()`, `workshopBayIsActive()`,
   `workshopBayDefaultTechnicianName()`,
   `getCachedWorkshopConfiguration()` — confirmed no `localStorage`
   read/write path exists in any of them.
2. Grep across `app.js`/`workshop-planner.js` for the six retired key
   constants — confirmed each appears only in
   (a) its own `const ..._KEY = '...'` declaration,
   (b) the one-time importer script, and
   (c) the explicit exclusion comment in `CRM_BACKUP_STORAGE_KEYS`.
   No other reference exists.
3. Live two-browser acceptance testing on the deployed staging site
   (Section 5 above) — mutations via an independent authenticated
   session propagated correctly to an open browser session with zero
   refresh, and reconnect/refresh/sleep-resume scenarios all caught up
   correctly from Supabase alone (see
   `STAGE-2A-SHARED-REFERENCE-DATA-HANDOVER.md` for full acceptance
   evidence).
