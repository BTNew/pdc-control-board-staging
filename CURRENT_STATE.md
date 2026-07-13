# Current State

Generated for handover on 2026-07-13.

## What currently works
- Current package version is `2026.07.13.07-zero-filter-recovery`.
- Static GitHub Pages app loads from `https://btnew.github.io/pdc-control-board/`.
- Baseline bundled dataset contains 321 current vehicles imported from the visible `EOS` worksheet in `Master2021 (1).xlsx` on 13 July 2026.
- The imported location split is 276 PMB, 17 WPC/RFT and 28 IT/in-transit vehicles.
- The workbook's test row, empty numbered placeholders and hidden copy/test sheets were intentionally excluded.
- Vehicle Locations and the operational views load the imported master-sheet vehicles and their mapped work states.
- Control Board view renders without browser-console errors in smoke testing.
- The Control Board column-heading row is selectable: Age / ETA controls oldest/newest order, each work heading controls Yes/No/outstanding/complete, and Status controls bucket/stoppage filtering.
- A synchronized floating copy of that same heading row stays visible during vertical scrolling and follows horizontal row scrolling.
- Zero-result filters retain the headings and clear actions; Parts intentionally omits `Not required` because every PMB row requires Parts.
- Filtered row counts are shown beside the unchanged real lane totals/capacity warnings, and all PMB lanes remain available as drag targets.
- Parts is a desktop-focused eight-column work queue with status filters, ETA countdown labels, blocker visibility and context actions.
- Vehicle Locations and Control Board include a work-status legend; Control Board highlights capacity and stoppage exceptions.
- The vehicle modal keeps Save and Cancel available in a sticky footer and isolates deletion in a confirmed danger zone.
- Direct per-row delete controls have been removed from Parts and RFT.
- The local-data reset query parameter is limited to test pages unless explicitly enabled by a developer.
- Parts ETA update stores current ETA in `pdcPartsWorstEta` and previous value in `pdcPartsPreviousWorstEta`.
- Parts ETA email draft includes vehicle details, previous ETA, new ETA and revised countdown.
- Navision import, Parts/production, data integrity, stage matrix, production-grid, desktop-operations, workflow-filter and master-sheet import tests pass locally.
- Desktop browser checks pass at 1920×1080 and 1440×900 without page-level overflow or console errors.
- PMB stage data uses internal keys including `TYRE` and `PIT_INSPECTION`.

## What is partially working
- Salesperson email routing is centralised through `salespersonEmail(vehicle)` and currently returns the configured RFT salesperson email constant. If true per-salesperson email mapping is required, add fields/mapping and tests.
- `CHATGPT_HANDOVER.md` in the committed repo may not contain its own final commit hash because Git commit hashes are content-addressed. The handover ZIP includes a generated copy with the final commit hash filled in.
- The app is static and browser-local; it has no server-side user accounts, database, or multi-user sync.

## What is broken
- No known broken automated tests at handover.
- No known live deployment blocker at handover.

## What was being worked on at handover
- Selectable floating Control Board column filtering, regression verification and packaging.

## Exact next action for another agent
1. Unzip the handover package.
2. Read `CHATGPT_HANDOVER.md`, `BUSINESS_RULES.md`, `MAINTENANCE_INSTRUCTIONS.md`, and this file.
3. Clone or open `https://github.com/BTNew/pdc-control-board` on branch `main`.
4. Run the test commands in `CHATGPT_HANDOVER.md` before making changes.
5. Validate the updated Control Board density and Parts queue on the actual workshop display before changing sizing further.

## Local cleanup note
- A pre-existing untracked backup ZIP may exist in Craig's local repo folder. It is not part of the committed repository and is intentionally excluded from the handover ZIP.
