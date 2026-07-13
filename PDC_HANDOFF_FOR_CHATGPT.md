# PDC Control Board handoff for another ChatGPT/Hermes

Use this file to brief another ChatGPT/developer on the current PDC Control Board work.

## Project

- Local repo: `C:\Users\nwmgr\pdc-control-board`
- GitHub repo: `https://github.com/BTNew/pdc-control-board`
- Branch: `main`
- Public/demo URL only: `https://btnew.github.io/pdc-control-board/` — GitHub Pages is unauthenticated and must not serve the operational baseline.
- Synthetic 75-vehicle test board: `https://btnew.github.io/pdc-control-board/test-75.html?clearLocalData=1`
- Package demo URL after an explicitly approved synthetic-data deployment: `https://btnew.github.io/pdc-control-board/?v=2026.07.13.21-autocare-pmb`

## Current package state

- Package version: `2026.07.13.21-autocare-pmb`.
- Package source commit: not recorded in this standalone working-copy snapshot; inspect repository status after placing the files.
- The package changes have been validated locally but are not committed, pushed or deployed from this handover ZIP.
- The bundled live dataset now contains 321 current vehicles from `Master2021 (1).xlsx` / visible `EOS` worksheet.
- The Control Board column-heading row itself is selectable for PMB age order, buckets, work status, Required Yes/No and stoppages, and floats while scrolling.
- Daily full Navision uploads update visible and back-end-only vehicles. Non-PDC Navision rows remain back-end-only; manual/PD/PO/PDC-promoted rows are protected from missing-dump cleanup.
- Broome Toyota PO PDFs are read from inside the document. Unknown stock numbers create active protected PO vehicles; matching back-end rows are promoted and enriched with the PO vehicle and work details.
- Back End Data activation follows the latest Navision location, with Body Builder / PMB landing in PMB Unallocated. Navision-derived locations refresh until staff manually lock the vehicle's location.
- Navision free text no longer infers non-Parts work ticks. **EMAIL UPDATE** prepares a salesperson status draft with Parts ETA and workshop/bay history for one selected vehicle. The saved salesperson directory resolves known staff, Toyota order is omitted and the triggering change is prominent.
- Sublet providers are seeded from `DEFAULT_SUBLET_PROVIDERS`; preserve casing normalization/deduplication and the one-time seed migration.
- Exactly one vehicle search match auto-opens/highlights. Kewdale age colours are fixed blue→yellow→orange→red with no animation.
- Missing/ambiguous vehicle lookups fail closed. Multi-key imports, removal and restore use a recovery journal with rollback and startup recovery.
- Operational health shows the latest imports/backup; management visibility shows third-party work, stagnation, capacity, RFT gate and history metrics. Secondary filters are grouped under **More filters**.
- `test_all.js` auto-discovers regressions and reports fixture-dependent tests as skipped when appropriate.
- Zebra/QZ label printing is implemented from vehicle rows, Vehicle Detail and selected-row actions. It uses the bundled QZ client, validates VIN length and prints two 68 mm × 45 mm labels per vehicle.
- A matched AutoCare despatch activates the vehicle at PMB `Unallocated`, starts its PMB arrival time and locks the PMB location against later Navision regression. Repeat scans preserve an existing PMB bay/bucket and do not reopen RFT/Completed vehicles. Unknown notices remain review-only.
- The full packaged regression result is 22 passed, 0 failed and 0 skipped.
- Hermes should read `HERMES_START_HERE.md` before this longer historical handoff.
- Read `MASTER_SHEET_IMPORT.md` and `master-import-audit.json` before changing the migration mapping.

Historical commit notes later in this file describe earlier PMB movement work and should not be mistaken for the current package version.

## What Craig wants preserved

Craig uses this as a live PMB/PDC control board. Keep reports concise: changed files, tests, live/deploy status, and any clear next step.

Important workflow rules:

- Navision import drives the main tracker.
- Navision storage and PDC Sheet visibility are separate: unpromoted Navision-only rows stay in Back End Data until promoted or retired by a later full dump.
- Manual, PD check-form, PO and PDC-promoted vehicles must never be removed merely because they are absent from Navision.
- Manual Yard Hold / PMB / RFT overrides take priority over Navision.
- Back End activation must use the most current Navision location; Body Builder / PMB must enter PMB Unallocated.
- Navision comments/location wording must not automatically tick non-Parts work boxes.
- Keep **EMAIL UPDATE** available for one selected vehicle and inside Vehicle Detail.
- After a successful single-vehicle RFT transfer, offer a separate reviewable salesperson draft without silently sending or blocking the completed transfer.
- Missing or ambiguous vehicle lookups must stop safely and must never update the first/wrong row.
- Imports and backup restore must be recoverable across all affected saved keys; a failed operation must roll back and report an error.
- PMB transfer lands in `Unallocated`.
- PMB vehicles must be movable between work buckets/bays and back to `Unallocated`.
- Craig specifically needs to move a vehicle back to `Unallocated` when work is done and it is waiting for another bay/process.
- Numbered bays are physical capacity: do not allow a second active PMB vehicle into an occupied numbered bay.
- If drag/drop is unreliable, use visible direct buttons instead of relying only on drag/drop.
- Current PMB work/stage order: `TINT`, `HOIST`, `FITTING`, `FAB`, `ELEC`, `TYRE`, `PIT`.
- Parts issued/completed vehicles should be hidden from the default open Parts queue.
- `FIX FIRST` should only show PMB/Parts stoppages.
- Completed/RFT collected vehicles should be locked from being accidentally unticked back into active work.
- Parts still gates RFT until issued or not required.
- Do not change DNS, Pages source/domain/CNAME, repo visibility/access, secrets, dependencies, destructive git/file ops, analytics/tracking, privacy-sensitive storage, or dangerous settings without explicit approval.

## Test-board requirement

When updating the PDC Control Board, keep/provide a separate 75-vehicle random/varied-position test board so changes can be tested across all statuses.

Current test files:

- `test-75.html`
- `data-test-75.js`

Current test board link:

- `https://btnew.github.io/pdc-control-board/test-75.html?clearLocalData=1`

The test board should remain separate from the live/normal data.

## Recently completed user checklist

The following was implemented before this handoff:

- Parts screen hides vehicles once Parts are issued/completed from the active list.
- Control Board has work-type filters/tick boxes for `TINT`, `HOIST`, `FITTING`, `FAB`, `ELEC`, `TYRE`, `PIT`.
- Navision import no longer auto-ticks PMB work based on bad assumptions; required PMB work is manually confirmed.
- Parts ordered is separated from issued; `partsOrdered()` ignores JITA `Yes`.
- Manual override allows vehicles to move to PMB from Yard Hold/In Transit when Navision glitches.
- Parts screen shows ETA to Kewdale and days until/since ETA.
- Completed vehicles/RFT collected vehicles are locked.
- Parts and completed tables are full-width/scrollable.
- `FIX FIRST` is a collapsible row-style list restricted to PMB/Parts stoppages.
- Vehicle card PMB work stream dropdown was removed/simplified into job chips/status indicators.
- Required/completed work display uses grey/red/green job indicators.
- JC Jobcard Number was added near Key Number and should be searchable/editable.
- `pmbAgeDays()` uses PMB entered timestamp, not Kewdale ETA.

## Latest specific issue/fix

Craig reported he still could not move vehicles to/from bays and back to `Unallocated`.

Fix pushed in commit:

- `24509a9 Fix PMB bay move controls`

Expected behavior now:

- PMB vehicle cards show clear `Move:` buttons.
- Vehicles can move:
  - from a work bucket/bay back to `Unallocated`
  - from `Unallocated` into `TINT / HOIST / FITTING / FAB / ELEC / TYRE / PIT`
  - between work buckets
- Numbered bay view should always expose `Unallocated` and `No bay` controls.

Verified after fix:

- On 75-vehicle test board, vehicle `TEST032` moved from `TINT Bay 02` to `Unallocated`.
- Then moved from `Unallocated` to `HOIST`.
- Browser console had no errors.

## 2026-07-08 visibility follow-up

Craig reported the updates were not visible even after Ctrl+F5. The likely causes found were:

- The previous answer overstated completion; several follow-up patches had not actually been pushed yet.
- `pdFlagsFromTasks()` still marked `FITTING` required for any imported PD task.
- PO upload inference still marked `FITTING` required for any uploaded file/task.
- PMB card job sign-off still blocked completion unless the job was already marked required.

Patch applied for version `2026.07.10.04-data-integrity`:

- Removed broad “any task/file means fitting” inference.
- PMB card sign-off can now mark the job required and complete in one confirmed action.
- Completed/RFT-collected vehicles remain locked from removing sign-offs.
- Cache-busted `index.html`, `test-75.html`, and `app.js` to visible version `2026.07.10.04-data-integrity`.

## Files most likely involved

- `index.html` — shell, version marker, asset cache-busting, UI fields.
- `app.js` — core PMB/Parts workflow logic, movement functions, renderers.
- `styles.css` — PMB card/button/status styling.
- `desktop-operations.css` — desktop monitor layout, Parts queue, modal and accessibility refinements.
- `data.js` — live/default data source.
- `test-75.html` — separate 75-vehicle test board page.
- `data-test-75.js` — 75-vehicle synthetic fixture data.

## Validation commands

From `C:\Users\nwmgr\pdc-control-board`, run:

```bash
node --check app.js
node --check data.js
node --check data-test-75.js
node test_all.js
git diff --check
git status --short --branch
```

The runner auto-discovers regressions. The external real-PO PDF integration test reports an optional skip when its fixtures or `pdftotext` are unavailable.

For UI changes:

1. Start local server:

```bash
python -m http.server 8765 --bind 127.0.0.1
```

2. Open:

```text
http://127.0.0.1:8765/test-75.html?clearLocalData=1
```

3. Browser-test movement between PMB stages/bays and `Unallocated`.
4. Check browser console for errors.
5. Push only after tests pass.
6. Verify a GitHub Pages URL only when it contains synthetic/non-sensitive data. Operational data requires authenticated private hosting.

## Reporting to Craig

Keep responses short. Include only:

- changed files
- tests/browser status
- GitHub/live status
- link to test board or fresh live URL
- any next step needed

Do not give long internal reasoning unless asked.

For production architecture and cutover requirements, read `BACKEND_MIGRATION_PLAN.md`. It intentionally does not select a vendor.
