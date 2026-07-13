# Vehicle Tracking Core

Static browser-based PDC / PMB control board. The app uses plain HTML/CSS/JavaScript, `data.js`, and browser localStorage. There is no backend database in this package.

## How to run

Open `index.html` directly, or serve the folder with a static file server:

```bash
python -m http.server 8765 --bind 127.0.0.1
```

Then open `http://127.0.0.1:8765/?v=2026.07.13.21-autocare-pmb`.

The bundled main dataset contains 321 operational vehicles imported from the visible `EOS` worksheet of `Master2021 (1).xlsx`. It is for controlled/private use only and must not be served from unauthenticated GitHub Pages. See `MASTER_SHEET_IMPORT.md` and `master-import-audit.json` for the migration rules and counts.

## Main workflow

1. Go to **Uploads** and import or paste the latest Navision export.
2. Use **Vehicle Locations** for the daily location list, search, filters and bulk movement controls.
3. Transfer Yard Hold vehicles into PMB. They must land in **Unallocated** first.
4. Use **Control Board** to assign the PMB station, drag vehicles between station queues and open physical bay scheduling.
5. Use **Parts** to order or sign off parts and manage parts stoppages.
6. Use **RFT** to review final gate readiness and mark collection only after all required jobs are complete.
7. Use **Completed vehicles**, **Deleted vehicles** and **Back End Data** for history and supporting records.

## Zebra labels

Vehicle rows, vehicle details, selected rows and Autocare despatch results can print two 68 mm × 45 mm Zebra labels through QZ Tray. QZ Tray must be installed and running on the Windows printing PC. See `ZEBRA_LABEL_PRINTING.md` for setup and troubleshooting.

## Daily Navision lifecycle

- A normal full Navision upload updates every matched active vehicle, including back-end-only rows, with Kewdale ETA, JITA and other approved Navision fields.
- Every new normal Navision row is retained as **Back end only** and hidden from the PDC operational sheets until a job/work file, PO, PD form or operator promotes it.
- A separate job/work file, manual vehicle entry, PD check-form upload or purchase-order PDF upload makes the vehicle visible on the PDC Sheet; Navision wording alone does not.
- PO PDFs are read from inside the file. If Stock # is not in Navision, the importer creates a protected active PO vehicle and fills the available vehicle, salesperson, department and PMB work details.
- PO and job-card/PD uploads open an editable review card before saving. Detected work is listed in plain language and can be preselected or replaced with manual work choices.
- A matched AutoCare despatch notice is an authoritative PMB arrival: it activates the vehicle at PMB Unallocated, while preserving an existing PMB bucket and never moving RFT/Completed vehicles backwards.
- Manual, PO, PD check-form, master-sheet and already-promoted PDC vehicles are protected if absent from a later Navision upload.
- Only unpromoted Navision-only back-end vehicles may be automatically retired when they disappear from a later full dump.
- A Navision-only vehicle retired for being absent may return if it reappears. A vehicle explicitly deleted by an operator is not recreated by Navision.

## Production Grid V2

The current package keeps the aligned vehicle-row system throughout the application. Key, Stock and Job Card use fixed tracks; Customer uses the flexible track and wraps without truncation. The eight station columns are identical 52 px × 30 px status cells, while their full names appear once in a 45-degree sticky header. Individual vehicle rows do not have their own horizontal scrollbars. See `PRODUCTION_GRID_V2_UPDATE.md` and `UNIFORM_STAGE_MATRIX_UPDATE.md` for the implementation and validation record.

## Current PMB stages and capacities

- Tint: 2 bays
- Hoist: 3 bays
- Fitting: 5 bays
- Fabrication: 13 bays
- Electrical: 10 bays
- Tyre Bay: 2 bays, including 1 wheel-alignment bay
- Pit Inspection: 1 bay
- Sublet: external provider queue with a 12-vehicle WIP target and no numbered internal bays

Unallocated uses a 12-vehicle triage target for attention only; it is not a physical bay-capacity limit.

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

- A normal daily Navision upload stores all new vehicles in Back End Data and refreshes approved source fields on matching records.
- Navision status, PMB, tray or PO wording alone never promotes a new vehicle to the PDC Sheet.
- A separate PDC work/job file, purchase order, PD check-form or manual PDC update promotes the matching vehicle.
- The Uploads screen presents daily Navision first, followed by job-card/PD work and PO uploads.
- Back End Data includes identity/customer search, state filtering and a confirmed Move to active button for back-end-only vehicles.
- A single Vehicle Locations or Control Board search match opens and highlights automatically for quick movement.
- The Sublet provider dropdown is seeded with the approved outside-work list using normal company-name casing and uppercase acronyms.
- Kewdale age uses a fixed blue/yellow/orange/red scale and never flashes.
- Move to active uses the latest Navision location: Body Builder / PMB goes to PMB Unallocated, Yard Hold goes to YH, and ready/dealer states go to RFT. A later manual staff location remains protected.
- Navision notes, dealer comments and location descriptions do not infer non-Parts work requirements. Work boxes come from explicit files, purchase orders or operator choices.
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
- Setup includes an editable salesperson directory. An explicit vehicle email is preferred, followed by the saved salesperson mapping and then an editable fallback.
- Stoppages, completed work, Parts ETA changes and a successful single-vehicle RFT transfer open a separate review box with a prepared salesperson email draft. **EMAIL UPDATE** on one selected vehicle or in Vehicle Detail prepares a full update with Parts ETA and workshop/bay history.
- Sales drafts omit Toyota order numbers, prominently label the triggering change and are never sent silently by the browser.
- A missing or ambiguous vehicle identity must stop safely; it must never fall back to or update the first vehicle in the dataset.
- Multi-key Navision, PO/job-card, vehicle-removal and restore operations use a recovery journal and roll back to the previous saved state if a write fails.
- Operational health shows the last Navision import, work/PO import and backup. The management view summarizes third-party work, stagnant vehicles, capacity alerts, RFT gate issues and recent history.
- Sales Rep and Work Type are under **More filters**; PMB Unallocated overflow is presented as a triage backlog rather than a permanent critical failure.

## Backup / restore

Use **Export Backup** before replacing the website files. Restore the JSON backup in the new package to reload saved vehicles, edits, notes, PO records, Autocare results, deleted vehicles, column order, and column widths.

CSV export is for reporting only. It is not a full restore backup.

Imports and restores involve several saved application keys. The current build journals the pre-change values and rolls them back if a write fails; startup also recovers an interrupted transaction before loading the board. A failed operation leaves the prior saved state available and reports an error instead of success.

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
node test_all.js
```

The runner discovers `test_*.js` automatically and reports a summary. The real-PO PDF integration test reports an optional skip when its three external fixtures or `pdftotext` are unavailable, so an extracted handover package can still complete its core suite.

## Known limitations

- This remains a static localStorage app. It is suitable for a controlled workstation or lightweight internal workflow, but not a true multi-user source of truth.
- Browser/device storage can be lost or diverge. Use backup JSON exports regularly.
- The bundled operational dataset must not be published through unauthenticated GitHub Pages. Azure Static Web Apps configuration is not enforced by GitHub Pages.
- The production target is an authenticated hosted backend with a shared database, permissions, server-side audit log, conflict-safe writes and central backups. No vendor has been selected; see `BACKEND_MIGRATION_PLAN.md`.
