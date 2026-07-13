# Changelog

## 2026-07-13 — AutoCare Means Arrived at PMB

- A matched AutoCare despatch vehicle is now promoted from Back End Data to the active PDC Sheet and placed at PMB Unallocated.
- Previously scanned AutoCare vehicles that are still before PMB are migrated to PMB automatically when this version first loads.
- An AutoCare scan starts the PMB arrival clock and locks the PMB location against later daily Navision location changes.
- Repeat notices preserve an existing PMB work bucket and original PMB arrival time.
- Late notices record the AutoCare event without moving RFT or Completed vehicles backwards.
- AutoCare results now state the PMB-arrival outcome, and the change is written to the vehicle audit trail.
- Bumped the version to `2026.07.13.21-autocare-pmb`.

## 2026-07-13 — Zebra Labels via QZ Tray

- Bundled the QZ Tray 2.2.6 browser connector locally and added direct raw-ZPL printing to the configured Zebra printer names, with Zebra-only fallback.
- Added **Label** to vehicle rows and vehicle details, plus selection-only **Print Labels** controls on Vehicle Locations, Control Board and the tracker.
- Autocare notice label controls now print directly; unmatched Autocare vehicles use Batch, VIN, Model and Version with an optional customer or `(Dealer Order)`.
- Enforced the 68 mm × 45 mm template, two copies through `^PQ2`, ZPL control-character cleaning and an informed VIN warning before printing.
- Kept the ZPL troubleshooting screen and added setup documentation and regression coverage.
- Bumped the version to `2026.07.13.20-zebra-labels`.

## 2026-07-13 — PO and Job-Card Import Review

- PO and job-card/PD files are now parsed into a vehicle review card before any tracker data is changed.
- The review card shows matched/new status and editable customer, vehicle, salesperson, job card, order, VIN, colour and trim fields.
- Detected work is summarized in plain language, for example `Tint, Tray, Electrical / 12V`, and asks whether to tick the matching work areas automatically.
- Detected work remains a suggestion: operators can accept it, choose manually or amend any non-locked work requirement before confirming.
- Cancel closes the review without saving; a confirmed import still returns to Vehicle Locations and highlights the imported vehicle.
- Added regression coverage and bumped the version to `2026.07.13.19-import-review`.

## 2026-07-13 — Production Hardening and Operational Clarity

- Vehicle lookup now fails closed when an identifier is missing or ambiguous, removing the unsafe fallback that could target the first vehicle.
- Navision, purchase-order, PD/job-card, vehicle-removal, dashboard-clear and backup-restore writes now use a rollback journal; interrupted transactions recover safely at startup.
- Added operational health for the latest Navision import, work-file/PO import and backup, and exposed the existing Operations visibility screen in the main navigation.
- Simplified the main filter bar with Sales rep and Work type under **More filters**, made Unallocated a neutral triage queue, changed capacity pressure to amber and reduced Parts rows to one primary action plus **More**.
- Added a public-static-hosting warning for bundled vehicle data, plus a vendor-neutral authenticated backend migration plan.
- Replaced repeated full-board rendering after an individual edit with active-view rendering.
- Added a self-discovering test runner and behavior coverage for lookup safety, storage rollback, operational hardening and version consistency.
- Bumped the application/cache version to `2026.07.13.18-production-hardening`.

## 2026-07-13 — Post-Import Vehicle Focus

- Successful purchase-order and job-card/work-file imports now return to Vehicle Locations with all unrelated buckets and rows collapsed.
- The imported vehicle's bucket and row open automatically, receive the existing blue focus highlight and scroll into view.
- Multi-file imports focus every successfully imported vehicle while leaving unrelated rows closed.
- Added regression coverage and bumped the version to `2026.07.13.17-import-focus`.

## 2026-07-13 — Body Builder Activation, Salesperson Directory and Flagged Emails

- Hardened Back End Data activation so `At Body Builder`, BodyBuilder/build-status variants, PMB and Perth Motor Bodies all land in PMB Unallocated instead of Other.
- Added a salesperson directory in Setup with editable initials, full name and email, seeded with SL, CW, BG, CF and JB; vehicle and manual-entry forms now use that directory as a dropdown.
- Sales email drafts now resolve the selected salesperson, omit Toyota order numbers and place a prominent `IMPORTANT UPDATE` banner around the triggering change such as Parts delay or RFT.
- A single vehicle moved to RFT now offers the reviewed salesperson email prompt automatically.
- Added regression coverage and bumped the version to `2026.07.13.16-location-sales-email`.

## 2026-07-13 — Sublet Providers, Search Reveal and Fixed Age Colours

- Added the supplied outside-work providers to the Sublet dropdown, normalized readable company casing, preserved acronyms such as ARB/PTE/MMT, and merged repeated spelling/location variants.
- Existing saved provider lists are upgraded once and merged with the defaults; staff can still add or remove providers afterward.
- Vehicle Locations and Control Board searches now auto-open the bucket and row, apply a strong blue highlight and scroll once when exactly one vehicle matches.
- Replaced flashing Kewdale/PMB ages with fixed colours: 0–5 days light blue, 6–10 yellow, 11–21 orange and 22+ red.
- Added regression coverage and bumped the version to `2026.07.13.15-sublet-search-age`.

## 2026-07-13 — Current-Location Activation and Vehicle Update Email

- Back End Data activation now reads the vehicle's latest Navision location: Body Builder / PMB lands in PMB Unallocated, Yard Hold lands in YH, and ready/dealer states land in RFT.
- A Navision-derived active location continues to refresh from the daily file until an operator manually transfers or places the vehicle, after which the manual location remains locked.
- Removed keyword inference from Navision notes, dealer comments and location descriptions so those fields no longer tick Tint, Hoist, Fitting, Fab, Elec, Tyre or Pit automatically. Explicit work files, purchase orders and operator choices still set work requirements; Parts remains the standard batch gate.
- Added **EMAIL UPDATE** for exactly one selected vehicle and in Vehicle Detail. It opens a reviewed salesperson draft containing current location, Kewdale ETA, Parts status/ETA, stoppages, bay history, completed work and outstanding work.
- Added regression coverage for activation mapping, later Navision location refresh, unwanted tick prevention and the detailed email body.
- Bumped the application/cache version to `2026.07.13.14-location-email`.

## 2026-07-13 — Broome Toyota PO PDF Import

- Added an embedded PDF reader so PO import works locally without a CDN or stock number in the filename.
- The importer now reads Stock #, PO number/due date, issuing salesperson, Broome department, vehicle/model, colour/trim, factory option, alternate model, VIN/engine/build date when present, total and all PMB work lines across multiple pages.
- A matching Navision back-end vehicle is promoted and enriched; an unknown stock number creates a protected active purchase-order vehicle in PMB Unallocated.
- Added PO metadata to vehicle details and made PO number/reference searchable.
- Verified all three supplied Broome Toyota POs, including 24 work lines and a page-two continuation, and added regression coverage.
- Bumped the application/cache version to `2026.07.13.13-po-pdf-import`.

## 2026-07-13 — Back-End Search and Manual Activation

- Added Back End Data search across stock/batch, Toyota order, VIN/frame, customer, vehicle, job card, salesperson, source and status.
- Added an All / Back end only / Active / Deleted state filter and a one-click Clear action.
- Added a confirmed **Move to active** action on back-end-only rows.
- Manual activation promotes the existing record to the PDC Sheet at its latest Navision-derived location and protects it from later missing-dump retirement.
- Added lifecycle and UI regression coverage and bumped the application/cache version to `2026.07.13.12-backend-activation`.

## 2026-07-13 — Navision Pasted-Text Repair and Upload Order

- Fixed Navision browser-copy text that expands tab characters into `U+2002` EN SPACE runs; the importer now reconstructs the original tab stops and blank columns.
- Verified the supplied 176-vehicle Navision paste with zero parser warnings and correct Order, Batch, model, customer and status alignment.
- Moved the daily Navision importer to the top of Uploads.
- Added dedicated job-card/PD work and PO upload cards immediately below Navision, followed by Autocare and backup/restore.
- Bumped the application/cache version to `2026.07.13.12-backend-activation`.

## 2026-07-13 — Salesperson Change Notifications

- Added an automatic notification box after production/Parts stoppages, PMB job completion, Parts completion, Parts ETA changes and RFT collection completion.
- The box identifies the salesperson, shows what changed and opens a prepared email draft for review.
- Vehicle-specific salesperson email fields are used when available; otherwise the configured sales email is shown as an editable fallback.
- Added regression coverage and bumped the application/cache version to `2026.07.13.12-backend-activation`.

## 2026-07-13 — Back-End-First Navision Import

- Changed normal Navision imports so every new Navision vehicle is stored in Back End Data and none are promoted by Navision wording or status alone.
- Kept daily Kewdale ETA, JITA and approved Navision source fields refreshing for both visible and back-end-only vehicles.
- Added a distinct PDC work/job-file mode; job cards, work signals, PO uploads, PD check-forms and manual PDC updates promote matching vehicles to the PDC Sheet.
- Made CSV/TSV/XLSX imports find headings below report-title rows, recognize more stock/model aliases and accept order-only Navision records.
- Added immediate row-count and parse-warning feedback after file selection plus a direct View Back End Data result action.
- Scoped full-dump cleanup to unpromoted Navision-only back-end records; manual, PO, PD, master-sheet and PDC-managed vehicles are protected.
- Distinguished automatic Navision retirement from operator deletion: automatically retired rows can return, while operator-deleted rows stay deleted.
- Added PDC Sheet / Back end only labels and counts to Back End Data.
- Added `test_navision_lifecycle.js` and bumped the application/cache version to `2026.07.13.12-backend-activation`.

## 2026-07-13 — Selectable Sticky Column Filters

- Made the Control Board column-heading row itself selectable instead of using a separate filter toolbar.
- Age / ETA now selects oldest/newest PMB ordering; Key, Stock, Job Card, Customer and Vehicle select their own sort order.
- Parts, Tint, Hoist, Fitting, Fab, Elec, Tyre and Pit headings select Yes, No, Outstanding or Complete.
- Status selects a PMB bucket or stoppage state, and Actions provides a column-filter clear button.
- Added a synchronized floating copy of the heading row that stays visible while scrolling and follows horizontal row scrolling.
- Kept the heading row and Clear controls visible when a filter returns zero matches, so users can always recover without reloading.
- Removed the impossible Parts `Not required` choice because every PMB vehicle in this board has a real batch and therefore requires Parts.
- Applied the same filter and sort rules to every PMB lane and the Fix First list while preserving the real capacity totals.
- Bumped the application/cache version to `2026.07.13.07-zero-filter-recovery`.

## 2026-07-13 — Current Master Sheet Import

- Replaced the random live dataset with 321 real vehicle rows from the visible `EOS` worksheet in `Master2021 (1).xlsx`.
- Imported 276 numbered-key PMB vehicles, 17 WPC/RFT vehicles and 28 IT/in-transit vehicles.
- Preserved customer, stock, key, date-in, model, suffix, colour, salesperson, work statuses, sublet providers and blocker signals.
- Mapped the master work columns into the current Tint, Hoist, Fitting, Fab, Elec, Tyre, Pit and Parts status model.
- Excluded the workbook's `Test` row, empty numbered placeholders and hidden copy/test worksheets.
- Added an import audit file, mapping notes and regression coverage for vehicle counts, uniqueness, locations and representative statuses.

## 2026-07-13 — Desktop Operations Refinement

- Rebuilt Parts as a focused eight-column work queue with a fixed-height, internally scrolling desktop table and clearer row actions.
- Added a shared work-status legend to Vehicle Locations and Control Board so required, complete, stopped and not-required states are explicit.
- Strengthened over-capacity and blocker warnings on Control Board while improving vehicle identity and work-cell readability for workshop monitors.
- Simplified operational top-bar controls and removed duplicate Fix First content from the supporting data pages.
- Reworked vehicle details with a persistent Save/Cancel footer and a separated danger zone for deletion.
- Removed direct row-delete controls from Parts and RFT; vehicle removal now requires opening the vehicle and confirming the action.
- Protected the live page from the test-only `?clearLocalData=1` reset parameter.
- Corrected ARIA nesting, nested interactive controls and contrast issues found during desktop accessibility checks.
- Verified the principal views at 1920×1080 and 1440×900 with no page-level horizontal overflow or browser-console errors.

## 2026-07-10 — Uniform Stage Matrix

- Standardised all eight vehicle-stage cells to the same 52 px × 30 px size across the shared production-grid pages.
- Moved the full station names into the sticky header and angled them at 45 degrees, so labels are shown once rather than repeated in every row.
- Replaced blank not-required cells with a restrained dash and retained clear symbols for complete, outstanding and blocked states.
- Reduced the station strip from 574 px to 444 px, returning the saved width to the flexible Customer column.
- Kept full accessible station/status labels and hover tooltips; no vowel-stripped labels or ambiguous abbreviations were introduced.
- Added `test_uniform_stage_matrix.js` and browser-computed validation across Vehicle Locations, Control Board, Pipeline, Schedule, Department and RFT views.

## 2026-07-10 — Production Grid V2

- Replaced card-style vehicle rows with one aligned production-grid row across Vehicle Locations, Control Board, Pipeline, Schedule, Department, RFT and Deleted views.
- Added full named station columns for Parts, Tint, Hoist, Fitting, Fabrication, Electrical, Tyre Bay and Pit Inspection.
- Made Customer the flexible identity column; long organisation names remain complete and wrap while Key, Stock and Job Card stay aligned.
- Rebuilt Parts, Completed and Back End Data as compact data-grid tables with separate identity, customer and vehicle columns.
- Removed horizontal scrolling from individual vehicle rows; each list or table now owns one scrollbar when the screen is narrower than the grid.
- Tightened page chrome, filters, KPI cards and buttons to recover usable screen space without reducing the main row text below 13 px.
- Added `test_production_grid_v2.js` and browser-render validation for all principal and supporting production views.

## 2026-07-10 — Worker review clean version

- Tightened the worker review build so row chips stay contained on the right instead of overflowing off-screen on narrower desktop views.
- Prepared a cache-busted worker review version after the Vehicle Locations and Control Board row-chip alignment update.
- Re-verified JavaScript syntax, core regression checks, whitespace checks, live asset loading, and the main worker-facing pages.

## 2026-07-09 — Coding and visual stability fix

- Added defensive startup/data guards so the board does not silently fail if data loading is delayed or malformed.
- Added visible startup error banner for runtime failures instead of leaving blank panels.
- Exposed `window.PDC_APP` / `window.app` for debugging from the browser console.
- Bumped saved table column storage keys so old wide column settings do not distort the refreshed layout.
- Tightened dashboard tables, PMB buckets, bay tiles, cards, markers and modal forms to stop boxes from overflowing or becoming disproportionate.
- Updated test page cache-busting references.


## 2026-07-05 — Review recommendations applied

- Renamed staff-facing navigation to Control Board, PMB Workflow, Reports, Parts, RFT, and Uploads.
- Added exception-led Fix First cards to Control Board and PMB Workflow.
- Hid dashboard quick-import panels so import work is focused under Uploads.
- Updated default vehicle table columns to current stage IDs and bumped saved column-order storage to v3.
- Added explicit Parts required/complete import mappings.
- Changed main CSV export to generate job columns dynamically from current PDC job definitions.
- Updated mobile stage/job model to Tint, Hoist, Fitting, Fabrication, Electrical, Tyre Bay, Pit Inspection, and Parts.
- Cleaned visible old-stage wording and updated import guidance text.
- Removed CDN script tags for QZ Tray/PDF.js so the package stays self-contained; printing/PDF extraction now use existing graceful fallbacks when those libraries are unavailable.

## 2026-06-23 — Dashboard Parts stoppage bucket
- Added a dashboard Parts Stoppage bucket for vehicles with an active Parts stoppage flag or blocker reason.
- Kept completed Parts vehicles out of the active stoppage bucket and added regression coverage.

## 2026-06-23 — Dashboard Parts tick visual states
- Added dashboard Parts tick styling for required/not ordered, ordered/confirmed and received/issued states.
- Added regression coverage so Parts visual classes stay limited to the Parts job tick.

## 2026-06-21 — Parts and production rule alignment
- Aligned Parts statuses to PDC wording: Not Required, Not Ordered, On Order, Issued, Misc Acc and Stoppage.
- Kept Parts search/table/export focused on parts and production by removing salesperson fields from those views.
- Removed the RFT salesperson notification prompt so RFT transfer stays production-only.
- Added regression coverage for parts status rules and no-salesperson RFT prompts.

## 2026-06-20 — Role-focused visual management refresh
- Reworked the Parts department page copy so it clearly hides Navision notes and production-only noise.
- Reordered Parts summary cards to surface Stoppages first, then open/order/waiting/complete work.
- Reordered Parts table columns around actionability: status, stock, ETA/age, blocker, actions, then supporting context.
- Highlighted stoppage rows and cards more strongly so blockers are visible first.
- Added focused PMB bay guidance per work stream; current visible stages are Tint, Hoist, Fitting, Fabrication, Electrical, Tyre Bay and Pit Inspection.
- Simplified PMB bay cards to show the current station status rather than all department job markers.
- Clarified PMB board guidance that vehicles land in Unallocated first and are manually assigned to production streams.
- Added documentation set: PROJECT_BRIEF, CHANGELOG, TODO, BUGS and SECURITY.

## 2026-06-20 — Startup and PMB landing fixes
- Fixed missing runtime references for status tabs/header mapping/status category labels.
- Preserved PMB first-landing behaviour so imported requirements do not auto-bucket vehicles.
- Historical note: older releases used the previous job-marker order; current marker/job order is T, H, F, Fa, E, Ty, PI, P.
- Added local browser console and Navision/PMB validation helpers.
