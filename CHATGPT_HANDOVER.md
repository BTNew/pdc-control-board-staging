# ChatGPT/Codex Handover — PDC Control Board

This package is intended to allow a new ChatGPT/Codex session to continue development without access to prior conversation memory.

## Project purpose
PDC Control Board is a static browser application for tracking Toyota/Navision vehicles through Yard Hold, PDC/PMB work, Parts blockers, and Ready For Transport (RFT). It is used to visualise vehicle status, manage manual workflow overrides, import Navision data, track production bay/work completion, and prepare operational emails.

## Current architecture
- Static site hosted on GitHub Pages.
- Main application logic: `app.js`.
- Desktop operations refinements: `desktop-operations.css`, loaded after `styles.css`.
- Baseline vehicle data: `data.js` loaded as `window.VEHICLE_TRACKING_DATA`.
- HTML entrypoint: `index.html`.
- Test/demo entrypoints: `test-50.html`, `test-75.html`, `test-100.html`, `no-vehicles.html`.
- Automated tests: `test_*.js` files run with Node.
- User edits and operational state are stored in browser `localStorage`, layered over bundled Navision/static data.
- No build step is required. No package install is required for current tests.

## Repository, live site and branch
- Repository: `https://github.com/BTNew/pdc-control-board`
- Live site: `https://btnew.github.io/pdc-control-board/`
- Current branch: `main`
- Handover package source branch: `main`
- Latest commit hash: `e97f98d36996d9dc5ee47555139dd0bdb16b4285`
- Current version/cache-busting identifier: `2026.07.13.07-zero-filter-recovery`

## Local setup
1. Open a shell in the repo folder:
   ```bash
   cd /c/Users/nwmgr/pdc-control-board
   ```
2. Serve the static site:
   ```bash
   python -m http.server 8025 --bind 127.0.0.1
   ```
3. Open:
   ```text
   http://127.0.0.1:8025/index.html?v=2026.07.13.07-zero-filter-recovery
   ```
4. Use `?clearLocalData=1` only on a test page when you intentionally want to clear app localStorage in that test browser. The live index ignores it by default.

## Test commands and expected results
Run from repo root:
```bash
node --check app.js
node --check data.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_data_integrity.js
node test_review_update_alignment.js
node test_production_grid_v2.js
node test_uniform_stage_matrix.js
node test_desktop_operations.js
node test_master_sheet_import.js
git diff --check
```
Expected success includes:
- no syntax output/errors from `node --check app.js`
- no syntax output/errors from `node --check data.js`
- `Navision confirmation tests passed`
- `Parts/production principle tests passed`
- `Data integrity checks passed`
- `Review update alignment tests passed`
- `Production grid v2 tests passed` if that test remains unchanged
- `Uniform stage matrix tests passed` if that test remains unchanged
- `Desktop operations regression checks passed`
- `Master sheet import regression checks passed`
- no output/error from `git diff --check`

## Deploy instructions
1. Make code/docs changes.
2. Update version/cache strings everywhere they appear.
3. Run tests and browser checks.
4. Commit:
   ```bash
   git status --short
   git add <changed files>
   git commit -m "Clear concise commit message"
   ```
5. Push:
   ```bash
   git push origin main
   ```
6. Verify live:
   ```text
   https://btnew.github.io/pdc-control-board/index.html?v=<commit-or-version>
   ```
7. Poll if GitHub Pages serves old assets. Verify the app footer/header shows the new version and console resources load `app.js`/`data.js` with the new query string.

## Vehicle data schema
Vehicles are plain objects. Common fields include:

### Identity and customer
- `id`: stable internal id, often `navision-<stock/order>` or generated fixture id.
- `sourceRow`: original spreadsheet row number.
- `stock`: stock/batch number; primary display identity.
- `batch`: stock/batch number alias.
- `order`: Toyota order number.
- `keyNumber`: key tag/number.
- `client`: customer name.
- `toyotaCustomer`: Navision/dealer customer.
- `contact`: contact details, usually blank.
- `vehicle`: display vehicle/model string.
- `toyotaVehicle`: Navision model description.
- `suffix`, `trim`, `colour`: vehicle descriptors.
- `owner`, `consultant`: salesperson/consultant display name.
- `source`: e.g. `Navision`.

### Navision/import fields
- `prodMth`: production month.
- `compPlate`: compliance date.
- `arrivalPort`: arrival port.
- `toyotaStatus`: Navision/sub-location status display.
- `etaAtDealer`: dashboard Kewdale ETA derived only from Kewdale ETA field.
- `navisionEtaAtDealerBB`: raw ETA At Dealer/BB.
- `navisionPortPlantEta`: raw Port/Plant ETA Date.
- `navisionKewdaleEta`: raw Kewdale ETA.
- `navisionEtaDate`: raw ETA Date.
- `navisionTransportLoadNo`, `navisionTransportPriority`.
- `navisionLocationStatus`, `navisionSubLocationDescription`.
- `navisionBuildStatus`, `navisionRavStatus`.
- `navisionDealerComments`, `navisionVehicleNote`.
- `epodReceipt`, `jitQty`, `jitaPartsOrdered`.
- `wmi`, `vdsNumber`, `frame`, `vin`, `engine`.
- `dealerCustomer`, `dealerCustomerCategory`, `salesType`, `listPrice`, `suburb`, `pma`.
- `trayOrdered`, `trayFitmentComplete`.
- `navisionCutButVehicle`, `navisionCutButVehicleSource`.
- `importedAt`: ISO timestamp.

### PDC location/workflow
- `pdcLocation`: `''`, `YH`, `PMB`, or `RFT`.
- `manualLocation`: manual override such as `YH`, `PMB`, `RFT`.
- `pdcLocationLocked`: true when manual/transfer state should override Navision.
- `pdcLocationUpdatedAt`: ISO timestamp.
- `pmbTransferredAt`, `pmbEnteredAt`, `rftTransferredAt`.
- `pmbStage`: PMB bucket internal key.
- `pdcWorkStage`, `workStage`: legacy/current work stage fields.
- `pmbStageEnteredAt`, `pmbStageUpdatedAt`.

### PMB bay fields
- `pmbBayStage`: internal PMB bay stage key.
- `pmbBayNumber`: bay number.
- `pmbBayEstimatedHours`: estimated hours.
- `pmbBayEnteredAt`, `pmbBayScheduledStartAt`.
- `pmbBayCompletedAt`, `pmbBayCompletedBy`, `pmbBayCompletedStage`.
- `pmbBayMechanic`: mechanic/person assigned.
- `pmbSubletProvider`: sublet provider.

### Job requirement/completion pattern
For each PDC job definition there are paired fields:
- Required: `pdcRequires<Work>` boolean.
- Complete: `pdcComplete<Work>` boolean.
- Completed timestamp: `pdcComplete<Work>At`.
- Completed operator: `pdcComplete<Work>By`.
Examples include Parts, Build, Fitting, Tint, Hoist, Fabrication, Electrical, Tyre and Pit Inspection depending on definitions in `PDC_JOB_DEFS`.

### Parts fields
- `pdcRequiresParts`: Parts required.
- `pdcCompleteParts`: Parts signed off/issued.
- `pdcCompletePartsAt`, `pdcCompletePartsBy`.
- `pdcPartsOrdered`: ordered flag.
- `pdcPartsOrderedAt`, `pdcPartsOrderedBy`.
- `pdcPartsReceived`: received/issued compatibility flag.
- `pdcPartsMiscAcc`: Misc Acc override.
- `pdcPartsStoppage`: active stoppage flag.
- `pdcPartsStoppageReason`: blocker reason.
- `pdcPartsStoppageAt`, `pdcPartsStoppageBy`.
- `pdcPartsStoppageClearedAt`, `pdcPartsStoppageClearedBy`.
- `pdcPartsWorstEta`: current Parts ETA date.
- `partsWorstEta`: legacy alias.
- `pdcPartsPreviousWorstEta`: previous Parts ETA captured when current ETA changes.
- `previousPartsWorstEta`: legacy alias for email display.
- `pdcPartsWorstEtaUpdatedAt`, `pdcPartsWorstEtaUpdatedBy`.

## localStorage keys
Important keys defined in `app.js`:
- `vehicleTrackingCoreNavisionOnlyEdits:v1`: manual edits keyed by vehicle identity.
- `vehicleTrackingCoreNavisionOnlyVehicles:v1`: manually added vehicles.
- `vehicleTrackingCoreNavisionOnlyAuditLog:v1`: audit entries.
- `vehicleTrackingCoreCurrentOperator:v1`: current operator name/initials.
- `vehicleTrackingCoreCurrentOperatorRole:v1`: current operator role.
- `vehicleTrackingCorePdcMechanics:v1`: PMB/PDC mechanics list.
- `vehicleTrackingCorePdcSubletProviders:v1`: sublet provider list.
- `vehicleTrackingCoreColumnOrder:v4`: vehicle table column order.
- `vehicleTrackingCoreWorkflowWidthMode:v1`: workflow width mode.
- `vehicleTrackingCoreRowWidthMode:v1`: row width mode.
- `vehicleTrackingCoreNavisionOnlyPoTasks:v1`: PO task state.
- `vehicleTrackingCoreNavisionOnlyPoFiles:v1`: PO file references/names.
- `vehicleTrackingCoreNavisionOnlyDeleted:v1`: manual deleted vehicle identities.
- `vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1`: Autocare dispatch/import result state.
- `vehicleTrackingCoreNavisionOnlyImport:v1`: Navision import results.
- `vehicleTrackingCoreQzPrinter:v1`: remembered QZ/Zebra printer.
- `vehicleTrackingCoreColumnWidths:*`: table width preferences.
- `vehicleTrackingCoreNotes:<vehicle>`: per-vehicle notes.

## Navision import rules and mappings
- Import only real vehicle rows with usable identity.
- Batch/Stock fields map from `Batch`, `Stock`, `Stock Number`, `SN`, `Stock No`.
- Order maps from `Order`, `Toyota Order`, `Toyota Order Number`, `Order Number`.
- Customer maps from `Customer Surname` or `Dealer Customer Name`/similar.
- Vehicle maps from `Model Description` plus suffix/variant fields.
- Consultant maps from `Salesperson`, `Sales Person`, `SP`, `Consultant`.
- Kewdale ETA maps from `ETA At Kewdale Yard`, `ETA to Kewdale`, `ETA To Kewdale` only.
- Location uses `Location Status` and `Sub Location Description` for auto PMB/RFT detection only when no manual lock exists.
- PMB-only import skips rows without PMB work/PO signal.
- Explicit PDC fields from import may update required/complete job flags, blocked state, location and PMB stage, but first PMB landing must be protected to Unallocated.

## PMB/Yard Hold transfer rules
- Vehicles follow Navision until Yard Hold unless manually overridden.
- Manual YH/PMB/RFT overrides Navision.
- First PMB entry lands Unallocated.
- PMB stage and bay assignment are manual.
- PMB internal stage keys must be enum values, not display strings.

## Workflow, production-bay and completion rules
- Required jobs gate completion and RFT.
- Completion ticks record timestamp/operator.
- Parts visual tick states apply only to Parts.
- PMB bay capacity rules are in `BUSINESS_RULES.md` and must be preserved.
- Production-bay grid/UI is sensitive to CSS/table widths; run production grid tests if touching layout.

## Parts-page rules and email behaviour
Current status: completed, tested locally, pushed live after this handover commit.

Implemented behaviour:
- Parts page shows Parts ETA countdown using `partsWorstEtaCountdownLabel(vehicle)`:
  - future: `N days to Parts ETA`
  - today: `Due today`
  - overdue: `N days overdue`
- Parts ETA date input stores `pdcPartsWorstEta`.
- Updating ETA also stores the previous value in `pdcPartsPreviousWorstEta`.
- Rows with a Parts ETA show `Email sales`.
- Email draft uses `mailto:` and includes:
  - greeting to salesperson/consultant name
  - stock/customer/vehicle details
  - Toyota order
  - job card
  - current stage
  - previous Parts ETA or `Not recorded`
  - new Parts ETA
  - revised countdown
  - Parts blocker note when present
- Automated coverage is in `test_parts_production_principles.js`.

Caveat:
- The recipient currently comes from `salespersonEmail(vehicle)`, which returns the configured central RFT salesperson email constant. If per-salesperson emails are needed, add a safe mapping/field and tests.

## RFT rules
- RFT requires required jobs complete, including Parts.
- RFT transfer must not prompt for salesperson notification confirmation.
- RFT email includes completed/outstanding job detail and uses the RFT salesperson email constant.

## Important business rules from Craig
See `BUSINESS_RULES.md`. Critical highlights:
- Work only inside the repo for code changes.
- Inspect before edits.
- Keep changes small/reviewable.
- Verify local site, console, imports, buckets/statuses before commit when relevant.
- Push verified updates to GitHub for Craig to view.
- Do not change DNS, Pages source/domain/CNAME, repo visibility/access, secrets, dependencies, destructive git/file operations, analytics/tracking, privacy-sensitive storage or dangerous settings without explicit approval.
- Preserve compact UI.
- Preserve 75-vehicle fixture/test expectations where applicable.

## Recent completed changes
- Made the Control Board column-heading row selectable, with oldest/newest sorting in Age / ETA and Yes/No/outstanding/complete filtering in each work heading.
- Added a synchronized floating copy of the column headings for vertical and horizontal scrolling; the separate filter toolbar was removed.
- Zero-result column filters keep the headings and Clear buttons visible. Parts does not offer `Not required` because all PMB rows require Parts.
- Kept real lane capacity totals visible while filtered/total row counts show exactly what is on screen.
- Replaced the random live dataset with 321 current vehicles from `Master2021 (1).xlsx` / visible `EOS` sheet.
- Imported PMB, WPC/RFT and IT/in-transit location groups plus current work and blocker states.
- Refined the desktop operational layout at 1920×1080 and 1440×900.
- Rebuilt Parts as an eight-column internally scrolling work queue.
- Added work-state guidance, stronger exception visibility and safer modal-based deletion.
- Corrected accessibility issues involving ARIA nesting, nested controls and contrast.
- Excluded the workbook's test row, empty key placeholders and hidden historical/test sheets.
- Version bumped to `2026.07.13.07-zero-filter-recovery`.
- Added/captured previous Parts ETA when Parts ETA is updated.
- Parts ETA email now explicitly includes previous ETA, new ETA and revised countdown.
- Added handover documentation files.

## Known bugs and incomplete work
- No known failing tests at package creation.
- Per-salesperson email routing is not implemented; current routing is centralised.
- The app is static/localStorage-based, so simultaneous multi-user edits are not synchronised.
- `app.js` is large and should be refactored carefully only with strong tests.

## Recommended next work, priority order
1. Confirm whether Parts ETA emails should go to a central contact or actual per-salesperson addresses.
2. If per-salesperson routing is needed, add an explicit safe mapping and tests.
3. Refactor duplicated Parts/PMB/RFT helper code only after adding coverage.
4. Add more browser-level regression tests for import → PMB → Parts → RFT workflows.
5. Consider private/authenticated hosting before using real customer data publicly.

## Browser-cache and GitHub Pages troubleshooting
- Always bump version/cache query strings when changing JS/data/CSS/HTML.
- Use `?v=<commit-or-version>` on the live URL.
- GitHub Pages can serve mixed old/new files during propagation; poll until `index.html`, `app.js`, and `data.js` all show the expected version.
- In browser console verify:
  ```js
  document.querySelector('#app-version')?.textContent
  window.VEHICLE_TRACKING_DATA.vehicles.length
  performance.getEntriesByType('resource').map(r => r.name).filter(n => /app\.js|data\.js/.test(n))
  ```
- Avoid `?clearLocalData=1` in real user browsers unless intentionally clearing user-local edits.

## Fragile or duplicated areas
- `app.js` combines many concerns in one large file.
- Version strings are duplicated in several files.
- localStorage schema has no migration framework beyond constants and compatibility aliases.
- Parts/RFT/PMB business rules overlap; change one area only with test coverage.
- GitHub Pages propagation/caching can mislead verification if not cache-busted.

## Handover package contents
- Source code, HTML, CSS, JS and data files.
- Automated tests.
- Documentation: this file, `BUSINESS_RULES.md`, `MAINTENANCE_INSTRUCTIONS.md`, `CURRENT_STATE.md`.
- Required assets/config/package files present in the repo.
- Excludes `.git`, `node_modules`, `.env*`, backup zips and unnecessary generated files.
