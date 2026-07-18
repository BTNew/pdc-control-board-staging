# Stage 2B C4 — Real-Data Readiness Assessment

## Scope

C4 is assessment-only. It does not import or upload vehicle data, call Supabase, mutate browser storage, clear fallback data, change frontend authority, retire direct `SELECT`, merge, deploy, or begin AI work.

The executable assessment has two separated stages:

1. `scripts/stage2b_c4_browser_export.js` reads the current browser-local vehicle families and downloads a narrow, sanitized JSON snapshot.
2. `scripts/stage2b_c4_assessment.py` validates that snapshot offline, produces the readiness report/manual-review CSV/import plan, and builds a deterministic checksum-verified ZIP.

Generated real-data artifacts live only under ignored `_c4_assessment/` and `_c4_packages/` directories. They must not be committed or uploaded.

## Browser-local inventory

| Family | Storage/source | Current role | C4 treatment |
|---|---|---|---|
| Static vehicles | `window.VEHICLE_TRACKING_DATA.vehicles` | Base list before overlays | Narrow identity rows; currently zero in the private cutover-hold build |
| Added/imported vehicles | `vehicleTrackingCoreNavisionOnlyVehicles:v1` | Browser-local vehicle rows appended to the base list | Narrow identity rows only |
| Vehicle edits and workflow | `vehicleTrackingCoreNavisionOnlyEdits:v1` | Overlay selected by `vehicleKey`; also holds `pmb*`, `pdc*`, and `workshop*` workflow fields | Identity overlay plus workflow field names; values/content excluded |
| Deleted vehicles | `vehicleTrackingCoreNavisionOnlyDeleted:v1` | Removes matching base/added rows from the effective set | Narrow deletion key only |
| Parts tasks | `vehicleTrackingCoreNavisionOnlyPoTasks:v1` | Vehicle-keyed Parts/task attachment | Key and count only |
| Parts files | `vehicleTrackingCoreNavisionOnlyPoFiles:v1` | Vehicle-keyed Parts/file attachment | Key and count only; names/content excluded |
| Notes | `vehicleTrackingCoreNotes:<vehicle-key>` | Vehicle-keyed notes | Key and count only; note text excluded |
| Workshop plans/bookings | `vehicleTrackingCoreWorkshopPlan:v1` | Browser-local planner bookings while legacy fallback exists | Booking reference, vehicle key and stage only |
| Workshop view | `vehicleTrackingCoreWorkshopView:v1` | UI preference, not vehicle identity | Inventoried but excluded from readiness matching |
| Workshop bay setup | `vehicleTrackingCoreWorkshopBaySetup:v1` | Legacy planner setup, not a vehicle row | Inventoried but excluded from vehicle identity matching |
| Navision import result | `vehicleTrackingCoreNavisionOnlyImport:v1` | Import diagnostics/source payload already reflected in added vehicles | Presence only; full payload excluded |
| AutoCare result | `vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1` | Dispatch diagnostic data | Presence only; full payload excluded |
| Audit log | `vehicleTrackingCoreNavisionOnlyAuditLog:v1` | Browser-local audit trail | Count only; details excluded |
| Operator/UI preferences | operator/role, column order/width, view-width keys | UI/session metadata | Key inventory only; excluded from vehicle assessment |
| Legacy roster keys | mechanics, salespeople and sublet-provider keys retained for Stage 2A reconciliation | Non-authoritative transitional evidence | Excluded from C4 vehicle matching; no read/write by the exporter |

Effective vehicle precedence matches `buildVehicleData()` in `app.js`: static rows plus added rows, deleted-key filtering, edit overlay, then Parts task/file attachment. `vehicleKey()` uses a non-placeholder stock number first, otherwise order, otherwise ID/stock.

## Current read-only assessment snapshot

The local Edge profile for `http://127.0.0.1:8124` was read through a copied LevelDB snapshot. Two consecutive snapshots were byte-identical before sanitization. Source browser files were not modified.

- Effective vehicles: **210**
- Static vehicles: **0**
- Added/imported vehicles: **210**
- Edit rows: **6**
- Deleted rows: **0**
- Audit rows: **16**
- Notes: **0**
- Parts attachment rows: **0**
- Workflow attachment rows: **6**
- Workshop bookings: **0**
- Parse errors: **0**
- Browser-local before/after SHA-256: `ceed898872fe154728072ec264d60a3cd045696f355a436b1200c1fedf4edb62`
- Sanitized assessment SHA-256: `7d862abbe37b5ccc42315195e8ab43bd6ee44f088fece4c33275f19e3c6e3661`

The final aggregate results and narrow record references are inside the generated package. No customer names, contact details, note text, Parts content, file content, audit details or full Navision payloads are included.

## User-run export

Run from the actual Control Board tab whose browser-local data is being assessed:

1. Open browser DevTools **Sources → Snippets**.
2. Create a snippet containing the complete tracked file `scripts/stage2b_c4_browser_export.js` and run it.
3. In the Console run:

```js
PDC_STAGE2B_C4_EXPORT.downloadAssessmentExport()
```

The tool downloads `PDC-Stage2B-C4-Browser-Assessment-<checksum>.json`. It reads local state, computes before/after checksums, and refuses success if any localStorage byte changes. It contains no storage-write, fetch, XHR, beacon, WebSocket or Supabase client call.

Build and verify the offline package:

```bash
python3 scripts/stage2b_c4_assessment.py \
  --input /path/to/PDC-Stage2B-C4-Browser-Assessment-<checksum>.json \
  --output-dir _c4_packages/final

python3 scripts/stage2b_c4_assessment.py \
  --verify-zip _c4_packages/final/PDC-Stage2B-C4-Real-Data-Readiness-<checksum>.zip
```

## Classification contract

- `clean`: no invalid, duplicate, conflict, ambiguity or attachment-link issue.
- `conflicting`: duplicate normalized stock/VIN/job-card or another canonical identifier ownership conflict.
- `ambiguous`: no deterministic unique match or an attached record resolves to multiple vehicle keys.
- `invalid`: placeholder stock, malformed VIN, missing identity or malformed browser family.

Issue counts can overlap. A malformed VIN duplicated across records is both conflicting and invalid. The machine-readable summary also records a deterministic primary classification, with conflict taking precedence over invalid, then ambiguity.

## Safety verification

- JavaScript tests use a storage object whose write methods throw and assert zero write attempts.
- Static tests reject storage-write and network primitives in the browser exporter.
- Python tests prove strict schema/checksum enforcement, prohibited broad-data rejection, deterministic output ordering, reproducible ZIP bytes and package re-verification.
- The offline analyzer has no browser, Supabase, database or HTTP client.
- The package verifier recomputes the summary, manual-review CSV and report from the packaged sanitized assessment.
