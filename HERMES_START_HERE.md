# Hermes Start Here — PDC Control Board

This is the current standalone handoff snapshot of the PDC Control Board. Start with this file, then read `BUSINESS_RULES.md`, `CURRENT_STATE.md`, `MAINTENANCE_INSTRUCTIONS.md`, `ZEBRA_LABEL_PRINTING.md`, and `BACKEND_MIGRATION_PLAN.md` before changing workflow behaviour.

## Current snapshot

- Application version: `2026.07.13.21-autocare-pmb`.
- Static HTML/CSS/JavaScript application; there is no build step or dependency install.
- `data.js` contains the bundled 321-vehicle operational baseline.
- Browser changes are layered over that baseline in `localStorage`.
- This ZIP is a working-copy snapshot. It was not committed, pushed, or deployed by the session that created it. After placing it in a Git repository, inspect `git status`, the branch, and the remote before committing anything.
- Do not publish the operational dataset to an unauthenticated public website.

## Run it

On Windows, double-click `start-preview.bat`, then open:

```text
http://127.0.0.1:8124/
```

On macOS/Linux, run:

```bash
./start-preview.sh
```

If the script is not executable, run `bash start-preview.sh`.

## Verify before and after changes

From this folder:

```bash
node --check app.js
node --check data.js
node test_all.js
```

Expected handoff result: 22 passed, 0 failed, 0 skipped. A fixture-dependent PDF test may be reported as skipped on a machine without its external fixture or extraction utility.

## Workflow rules that must be preserved

- A full Navision import stores all recognised vehicles in Back End Data. It updates active and back-end-only records but does not automatically promote new Navision-only rows to the PDC Sheet.
- A PO, job card, work file, manual activation, or recognised AutoCare arrival may promote a vehicle to the active PDC Sheet.
- Manual, PO, job-card/PD, master-sheet, AutoCare-arrived, and operator-promoted vehicles must not be removed merely because they are absent from a later Navision file.
- Navision location/comment text must not automatically tick Tint, Hoist, Fitting, Fab, Electrical, Tyre, or Pit work requirements.
- Activating a Back End vehicle uses its latest Navision location. `At Body Builder`, PMB, and equivalent body-builder statuses land in PMB `Unallocated`, not `Other`.
- A matched AutoCare despatch notice is authoritative evidence that the vehicle has arrived at PMB. It activates the record, places it in PMB `Unallocated`, records the PMB arrival time, and protects that location from later Navision location regression.
- Re-importing the same AutoCare vehicle must preserve its current PMB bucket/bay and original PMB arrival time.
- AutoCare must not reopen a vehicle already at RFT or Completed. An unmatched AutoCare row remains in review and must not create an unidentified active vehicle silently.
- PO/job-card imports must show the editable review card, list detected work such as Tint or Tray, and let the operator confirm or amend work before saving.
- Parts still gates RFT until issued or marked not required. Completed/RFT vehicles must be protected from accidental reopening.
- Numbered PMB bays are physical capacity and may contain only one active vehicle.
- Vehicle notification emails are prepared for review; do not silently send them. Salesperson identity must be resolved from the saved directory or left editable rather than guessed.

## Zebra label printing

- QZ Tray must be installed and running on the printing PC.
- Labels use raw ZPL, 68 mm × 45 mm at 203 DPI, and print two copies per vehicle using `^PQ2`.
- Preferred printer identities are `BT-Zebra-EricComp`, `dc-01\\BT-Zebra-EricComp`, and `192.168.0.164`, with a Zebra fallback where configured.
- VINs that are not 17 characters must produce a warning before printing. Printing may continue only after operator confirmation.
- Keep the bundled `vendor/qz/qz-tray.js`. Full implementation details and the exact ZPL template are in `ZEBRA_LABEL_PRINTING.md`.

## Important implementation notes

- Main entry point: `index.html`.
- Main application logic: `app.js`.
- Baseline vehicles: `data.js` as `window.VEHICLE_TRACKING_DATA`.
- Styling: `styles.css`, followed by `desktop-operations.css`.
- Regression runner: `test_all.js`, which discovers `test_*.js` files.
- QZ Tray client: `vendor/qz/qz-tray.js`.
- Test/demo boards: `test-50.html`, `test-75.html`, `test-100.html`, and `no-vehicles.html`.

Whenever application assets change, bump `APP_VERSION` and every matching cache-busting query string in the HTML/test fixtures. Run `node test_version_consistency.js` through the full suite to catch drift.

Never clear, rewrite, or migrate the operator's `localStorage` without an explicit backup and approval. This ZIP cannot include unsaved browser-local operational changes; if the operator has newer live-browser edits, obtain an in-app backup JSON separately.

## Recommended Hermes continuation prompt

```text
Continue the PDC Control Board from this handoff. Read HERMES_START_HERE.md,
BUSINESS_RULES.md, CURRENT_STATE.md, MAINTENANCE_INSTRUCTIONS.md,
ZEBRA_LABEL_PRINTING.md, and BACKEND_MIGRATION_PLAN.md first. Preserve the
documented vehicle lifecycle rules and operational data. Run node test_all.js
before and after changes, report changed files and exact test results, and do
not commit, push, deploy, clear local data, or publish the operational dataset
without explicit approval.
```
