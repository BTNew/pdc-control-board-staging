# Vehicle Tracking Core

Static browser-based PDC / PMB control board. The app uses plain HTML/CSS/JavaScript, `data.js`, and browser localStorage. There is no backend database in this package.

## How to run

Open `index.html` directly, or serve the folder with a static file server:

```bash
python -m http.server 8765 --bind 127.0.0.1
```

Then open `http://127.0.0.1:8765/?v=2026.07.10.23-uniform-stage-matrix`.

## Main workflow

1. Go to **Uploads** and import or paste the latest Navision export.
2. Use **Vehicle Locations** for the daily location list, search, filters and bulk movement controls.
3. Transfer Yard Hold vehicles into PMB. They must land in **Unallocated** first.
4. Use **Control Board** to assign the PMB station, drag vehicles between station queues and open physical bay scheduling.
5. Use **Parts** to order or sign off parts and manage parts stoppages.
6. Use **RFT** to review final gate readiness and mark collection only after all required jobs are complete.
7. Use **Completed vehicles**, **Deleted vehicles** and **Back End Data** for history and supporting records.

## Production Grid V2

Build `2026.07.10.23-uniform-stage-matrix` uses one aligned vehicle-row system throughout the application. Key, Stock and Job Card use fixed tracks; Customer uses the flexible track and wraps without truncation. The eight station columns are identical 52 px × 30 px status cells, while their full names appear once in a 45-degree sticky header. Individual vehicle rows do not have their own horizontal scrollbars. See `PRODUCTION_GRID_V2_UPDATE.md` and `UNIFORM_STAGE_MATRIX_UPDATE.md` for the implementation and validation record.

## Current PMB stages and capacities

- Tint: 2 bays
- Hoist: 3 bays
- Fitting: 5 bays
- Fabrication: Refer Dan / non-fixed capacity
- Electrical: 10 bays
- Tyre Bay: 2 bays, including 1 wheel-alignment bay
- Pit Inspection: 1 bay

## Current required job model

The app uses these PDC job definitions consistently for the main board, PMB workflow, imports, CSV export, and RFT gate:

- Tint
- Hoist
- Fitting
- Fabrication
- Electrical
- Tyre Bay
- Pit Inspection
- Parts

Legacy spreadsheet aliases for older Fitting wording are still accepted during import so older files do not fail, but the visible workflow is now aligned to the current stage list above.

## Business rules to preserve

- Navision drives source vehicle data up to Yard Hold.
- Manual Yard Hold / PMB / RFT decisions override imported status.
- PMB transfer lands in Unallocated.
- Job ticks do not auto-allocate PMB stages or numbered bays.
- Numbered bay assignment is manual physical capacity.
- A numbered bay cannot hold two active vehicles in the same stage.
- Waiting/no-bay vehicles remain unassigned until a bay is available.
- PMB key tags are only active while the vehicle is active in PMB.
- Duplicate active PMB key tags are blocked.
- RFT is blocked until every required job is signed off, including Parts and Pit Inspection when required.
- Parts stays production-focused and avoids salesperson/finance clutter.

## Backup / restore

Use **Export Backup** before replacing the website files. Restore the JSON backup in the new package to reload saved vehicles, edits, notes, PO records, Autocare results, deleted vehicles, column order, and column widths.

CSV export is for reporting only. It is not a full restore backup.

## Applied review update — 2026-07-05

- Renamed the staff-facing navigation to **Control Board**, **PMB Workflow**, **Parts**, **RFT**, **Reports**, and **Uploads**.
- Added a **Fix First** exception strip to the Control Board and PMB Workflow.
- Hid quick import widgets from the Control Board so imports live under Uploads.
- Updated the default vehicle-table column order to the current stage columns: Tint, Hoist, Fitting, Fabrication, Electrical, Tyre, Pit Inspection, Navision Notes, JITA, Action.
- Bumped the saved column-order key to avoid stale old column layouts.
- Added explicit Parts import support for required and completed columns.
- Made CSV export job headers dynamic from the current PDC job definitions.
- Removed the separate mobile page; the main board is the single maintained interface.
- Updated visible wording away from the older stage model.
- Removed external CDN script tags so the package remains self-contained; optional QZ/PDF integrations fail gracefully when not available.

## Checks

Run these after code changes:

```bash
node --check app.js
node --check data.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_review_update_alignment.js
node test_production_grid_v2.js
node test_uniform_stage_matrix.js
```

## Known limitations

- This remains a static localStorage app. It is suitable for a controlled workstation or lightweight internal workflow, but not a true multi-user source of truth.
- Browser/device storage can be lost or diverge. Use backup JSON exports regularly.
- A backend with login, shared database, permissions, server-side audit log, and central backups is the later-phase option once multiple staff need simultaneous editing.
