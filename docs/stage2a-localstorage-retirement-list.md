# Stage 2A — localStorage Key Retirement List

Final classification of every browser-local storage key touched by this
project, as of Stage 2A (shared workshop reference/lookup data).

## Retired operational keys (Supabase is now sole authority)

These keys' underlying data is now served **exclusively** from Supabase
via `workshop-reference-data-service.js`. The frontend never reads or
writes these keys anymore. They are left untouched on disk (not deleted)
purely so the Stage 2A browser-data importer
(`scripts/import_stage2a_reference_data.py`) can still read a given
staff computer's pre-migration local roster during the one-time
import/reconciliation step. No other code path treats them as
authoritative, and clearing them has zero effect on live data.

| Key | Was used for | Now served by |
|---|---|---|
| `vehicleTrackingCorePdcMechanics:v1` | Mechanic/technician roster | `workshop_technicians` via `workshop-reference-data-service.js` |
| `vehicleTrackingCorePdcMechanicsRosterSeed:v1` | One-time seed marker for mechanics | n/a — seeding is now a DB migration concern |
| `vehicleTrackingCorePdcSubletProviders:v1` | Sublet provider roster | `sublet_providers` via `workshop-reference-data-service.js` |
| `vehicleTrackingCorePdcSubletProvidersSeed:v2` | One-time seed marker for providers | n/a |
| `vehicleTrackingCoreSalespersons:v1` | Salesperson roster | `salespeople` via `workshop-reference-data-service.js` |
| `vehicleTrackingCoreSalespersonsSeed:v1` | One-time seed marker for salespeople | n/a |

Workshop bays and workshop settings never had a browser-local key at
all prior to Stage 2A (no `WORKSHOP_BAYS_KEY`/`WORKSHOP_SETTINGS_KEY`
constant exists anywhere in the codebase) — the hardcoded
`PMB_STAGE_BAY_COUNTS` structural config remains a separate,
intentionally-unmigrated concern (bay *count* per stage, not bay
*records*); the 38 real `workshop_bays` rows and `workshop_settings`
rows were introduced directly in Supabase by migrations 022/023 and
have never had a local fallback.

## Import-only legacy keys (read once, never written, never authoritative)

Same six keys as above, when accessed specifically by
`scripts/import_stage2a_reference_data.py` for the one-time browser-data
import. The importer treats them as read-only historical input; it never
writes to them and the running application never reads them.

## Retained harmless preference/UI keys (unaffected by Stage 2A)

These remain genuinely browser-local, per-device UI preferences with no
shared-authority concern. Untouched by Stage 2A:

| Key | Purpose |
|---|---|
| `vehicleTrackingCoreColumnOrder:v4` | Per-device vehicle table column order |
| `vehicleTrackingCoreWorkflowWidthMode:v1` | Per-device layout width preference |
| `vehicleTrackingCoreRowWidthMode:v1` | Per-device row width preference |
| `vehicleTrackingCoreCurrentOperator:v1` / `...OperatorRole:v1` | Legacy operator-name UI convenience (pre-Supabase-auth), not RLS-relevant |

## Not yet retired (outside Stage 2A scope — tracked for Stage 2B)

The workshop *planner booking* data itself
(`vehicleTrackingCoreNavisionOnlyEdits:v1`, `...Vehicles:v1`, and the
in-memory `workshopSavePlans()` local plan rows) remains browser-local
by default and is **only** bypassed when `workshopSharedModeActive()`
is true (an explicit staging opt-in flag). This is deliberately outside
Stage 2A's scope, which covers shared *reference/lookup* data
(technicians, salespeople, sublet providers, bays, workshop settings)
only, not the vehicle/booking master data migration itself (Stage 2B).

## Verification performed

- `loadMechanics()`, `loadSalespersons()`, `loadSubletProviders()` in
  `app.js` read exclusively from `window.__workshopReferenceDataService`
  and never fall back to `localStorage` under any code path.
- `workshopBayMechanic()` in `workshop-planner.js` prefers the Supabase
  `default_technician_id` and only falls back to the legacy
  `workshopLoadBaySetup()` local mapping when no Supabase row/default
  exists for that bay — this fallback is intentional and harmless (it
  can never override a real Supabase default, only fill a genuine gap).
- `CRM_BACKUP_STORAGE_KEYS` (the general browser-local backup/export
  list) explicitly excludes all six retired keys, with an inline
  comment recorded at the exclusion site explaining why.
- Confirmed via live two-browser Realtime acceptance testing (this
  session) that add/edit/deactivate for technicians, salespeople, and
  sublet providers propagate correctly through Supabase alone — a local
  roster on one device cannot diverge from or override the shared
  Supabase-backed roster after page load, because the running
  application never reads these keys once the page has loaded.
