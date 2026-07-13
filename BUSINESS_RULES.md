# PDC Control Board Business Rules

This file records established PDC Control Board behaviour independent of any chat history.

## Core purpose
- Track Toyota/Navision vehicles through Yard Hold, PDC/PMB work, Parts, and RFT readiness.
- The site is a static GitHub Pages app backed by bundled `data.js` plus browser `localStorage` overrides.
- Do not expose private customer/business data publicly without login/security. Current bundled data is random/test data.

## Data import and identity
- Import only real Navision rows that contain a usable Batch/Stock number or Toyota Order identity.
- Batch/Stock number is the primary display identity where available.
- Do not import fake rows, totals, headers, blanks, or non-vehicle rows.
- Manual user changes in `localStorage` override the bundled/imported Navision baseline.
- Manual deletes must remove only the selected vehicle; do not use broad fuzzy keys that can delete unrelated vehicles.

## Navision ETA rules
- Dashboard/Kewdale ETA must come only from Navision `ETA At Kewdale Yard` / `ETA to Kewdale` / `ETA To Kewdale`.
- If Kewdale ETA is blank, dashboard ETA remains blank.
- Other ETA fields such as `ETA At Dealer/BB`, `Port/Plant ETA Date`, and `ETA Date` may be stored for context but must not replace Kewdale ETA.

## PDC locations
- Supported manual PDC locations: follow Navision/blank, `YH`, `PMB`, `RFT`.
- `YH` means Yard Hold.
- `PMB` means Perth Motor Bodies.
- `RFT` means Ready for Transport.
- Manual YH/PMB/RFT overrides Navision automatic location.
- Navision can auto-detect PMB/RFT only when no manual location/lock exists.

## PMB transfer and allocation
- First PMB entry must land in PMB Unallocated.
- PMB transfer must not silently allocate a bay or work bucket.
- Job ticks never auto-allocate a PMB bay.
- PMB bucket/bay movement is manual.
- PMB bay capacities to preserve:
  - Tint: 2 bays
  - Hoist: 3 bays
  - Fitting: 5 bays
  - Fabrication: 13 bays
  - Electrical: 10 bays
  - Tyre: 2 bays
  - Pit Inspection: 1 bay
- Internal PMB stage keys must remain enum-like values: `TINT`, `HOIST`, `FITTING`, `FABRICATION`, `ELECTRICAL`, `TYRE`, `PIT_INSPECTION`; do not store display labels like `Tyre bay` or `Pit Inspection` as stage keys.

## Workflow and production rules
- PDC required/complete jobs are explicit boolean fields on each vehicle.
- Completion ticks must record completed timestamp and operator where possible.
- Parts tick visuals are special and must not leak into non-Parts jobs.
- Completed/issued Parts vehicles should not stay in active Parts queues.
- Stoppage/Fix First lists should surface blockers before RFT.

## Parts rules
- Parts page active filters show open work only by default.
- Issued/received Parts vehicles are removed from active/all Parts page filters.
- Parts search must not match salesperson/staff fields.
- Parts page must not render a general Sales column or expose salesperson names in the table.
- Parts status precedence:
  1. Not Required if Parts are not required.
  2. Misc Acc override.
  3. Issued if Parts job is complete or parts received.
  4. Stoppage if active stoppage flag/reason exists and Parts required/not complete.
  5. On Order if ordered.
  6. Not Ordered otherwise.
- Parts ETA field is `pdcPartsWorstEta` (also accepts legacy `partsWorstEta`).
- Previous Parts ETA field is `pdcPartsPreviousWorstEta` (also accepts legacy `previousPartsWorstEta` for email display).
- Parts ETA countdown must show:
  - `N days to Parts ETA` for future dates.
  - `Due today` for today.
  - `N days overdue` for past dates.
- Updating Parts ETA records previous ETA in `pdcPartsPreviousWorstEta`, updated timestamp, updated operator, and audit log.
- Parts ETA email button appears on rows with a Parts ETA and prepares a `mailto:` draft.
- Parts ETA email must include vehicle details, previous ETA if available, new ETA, revised countdown, current stage and blocker note.
- Parts ETA email currently routes to the central salesperson contact constant via `salespersonEmail(vehicle)`.

## RFT rules
- RFT transfer requires required jobs complete, including Parts when required.
- Transfer to RFT must not ask for salesperson notification confirmation.
- RFT email notification uses the RFT salesperson email constant.
- RFT email includes completed jobs and outstanding jobs at transfer.

## User-data safety
- Do not clear localStorage during normal development or live verification.
- `?clearLocalData=1` intentionally clears tracked app storage; use only for isolated testing and say when used.
- Never commit secrets, API keys, credentials, real private customer lists, `node_modules`, or unnecessary generated artifacts.
- Backup/export files should remain local unless explicitly requested.

## Live deployment expectations
- GitHub Pages serves from the repository. Push to `main` for deployment.
- Version/cache strings in HTML and JS must match so browsers fetch new assets.
- Verify both local and live sites after deployment.
