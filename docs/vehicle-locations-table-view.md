# Vehicle Locations — Table view (r461, F74)

> **r485 (F98):** Table view is the only view. The "Drop-down view | Table
> view" switch is gone; see the r485 section at the end.

> **r462 (F75):** the side panel is now a slide-out panel with bookings and
> bay drag, the Location column is now **Parts loc**, and columns can be
> resized. See `docs/vehicle-slideout-panel.md`.
>
> **r463 (F76):** Job Card column between Stock and Customer; the panel's
> drag-to-bay is withdrawn.

Change request from Craig, approved 22 Oct 2026 07:28 AWST (release 1 of the
Vehicle Locations plan). Staging only. Frontend only — no database change.

## What it is

A second way to look at the same Vehicle Locations board, modelled on the Sales
site: one compact row per vehicle instead of a tall drop-down card.

* **Switch** — a "View: Drop-down view | Table view" button pair beside the
  Vehicle Locations search. The highlighted button is the current view.
* **Default** — today's drop-down view. Nobody sees the table unless they press
  **Table view**. If browser storage is blocked or holds anything unexpected the
  drop-down view is used.
* **Remembered** — per signed-in user, per device/browser
  (`localStorage["pdc.vehicle-locations-view.v1:<user id>"]`). Another person on
  the same iPad keeps their own choice. Switching back is one click.
* **Tiles** (table view) — All, Other, In transit (IT), Yard Hold, Non-Navision,
  PMB, QC, PIT, RFT, STOPPAGES. Clicking a tile filters the table (same filter as
  the drop-down view's bucket). STOPPAGES is the board's own stoppage list, so its
  number is exactly the count the drop-down view shows.
* **Table** — 32 px rows in that journey order: Key, Stock / JC / Customer
  identity, Vehicle, Location, the station strip (Parts, Tint, Bus 4x4, Hoist,
  Fitting, Fab, Elec, Tyre, Sublet), Age, Status, Booking. RFT rows show their
  RFT controls in the station area, as today. Column sort uses the existing
  board sort.
* **Side panel** — click a row (or press Enter on it) to open that vehicle's
  existing card, already expanded, in a panel on the right with its Open button
  and every action it has today. Close with ✕ or Escape.
* **Live refresh** — the chosen tile, search text, scroll position and open
  vehicle stay as they are when the board refreshes. While someone is typing in
  the panel it is not redrawn under them.
* **iPad landscape (1100 px)** — narrower identity/vehicle columns and a
  narrower side panel (at most 70% of the screen); checked at 1100 px.

## Why it cannot change what a station shows

The table does not re-draw station cells. It calls the same
`incomingVehicleDetailRow()` the drop-down view uses, then moves the pieces of
that card's summary row (station strip, RFT controls, age, status, booking
buttons, identity) into table cells verbatim. In table view the drop-down board
is not drawn at all (no double render). The new CSS changes only size and
spacing; a test fails if any rule touching a station cell sets a colour,
background, border colour, opacity, filter or content.

## Parity gate

* **In the suite** — `test_vehicle_locations_table_461.js` renders the board in
  the VM harness with the synthetic fixture `qa/vehicle-locations-table-461-fixture.cjs`
  (48 synthetic vehicles `SYN-0001…`, blank customers, every location bucket,
  every station state: not required, required, booked, complete, stoppage and
  each parts colour) and requires 0 differences per station cell (classes,
  symbol, tooltip, aria label, full HTML) between the two views, plus identical
  RFT controls, age, status, booking and identity pieces.
* **In the page** — signed in on staging, open Vehicle Locations and run in the
  browser console: `await PDC_VEHICLE_LOCATIONS_TABLE.parity()`. It draws both
  views in turn, compares every cell including computed colours and
  ::before/::after, restores the user's view and saves nothing.
  `mismatchCount` must be 0 and `dropDownCardsInTableView` 0.
  Result on live staging data (22 Oct 2026 07:40 AWST, 400 vehicles):
  3,573 station cells, 12 RFT controls, 1,753 other items, 0 mismatches at
  1366 px and at 1100 px.

## Files

* `pdc-vehicle-locations-table.js` / `.css` — new (version `2026.10.22.r461`).
* `canonical-entry.js` — loads the module after `pdc-key-number.js` (on load or error).
* `index.html` — `vehicle-locations-table=2026.10.22.r461` cache-bust on canonical-entry.js;
  `pdc-auto-reload.js` stays the first script.
* `scripts/build_pages_runtime.js` — ships both files.
* `test_karratha_release_boundary.js` — approved hashes for canonical-entry.js and index.html.
* `styles.css` and `app.js` — untouched.

## Undo

Revert the PR. Until then, anyone can press **Drop-down view** (the default for
everyone who has not switched).

## r476 (F89): columns bunched up (Craig, 22 Oct 2026 10:56 AWST)

Display only, Table view only. Before r476 every column, fixed ones too, was
stretched in proportion to fill a wide screen (`table-layout: fixed` spreads
spare width over every column), so Key, Stock, Job Card, Parts loc, Stations and
Age / ETA had large empty gaps at 1920 px, and at 1366 px the table was wider
than the screen (horizontal scroll).

| Column | Default | Kind |
|---|---|---|
| Select (first, unlabelled) | 0 px, 22 px when a row on screen has a checkbox | — |
| Key | 42 px | fixed |
| Stock | 82 px | fixed |
| Job Card | 78 px (stacked job cards ellipsis, full text on hover) | fixed |
| Customer | 104 px base, weight 1 | flex |
| Vehicle | 112 px base, weight 1 | flex |
| Parts loc | 60 px (heading wraps to two lines) | fixed |
| Stations | 276 px (9 × 27 px cells, 8 × 3 px gaps, padding) | fixed |
| Age / ETA | 72 px | fixed |
| Status | 112 px base, weight 1.2 | flex |
| Booking | 160 px base, weight 0.4 | flex |

* Flex columns get their base plus a weighted share of the spare width
  (`layoutWidths()`), recomputed when the table area changes size. The bases add
  up to exactly the 1,098 px table area of a 1366 px screen with the side menu.
* **The left gap** Craig marked is the drop-down card's own multi-select checkbox
  cell (`.incoming-card-select`, app.js). Editable vehicles get a checkbox there
  (bulk selection bar); read-only email / Navision vehicles get an empty
  placeholder, so on today's board the whole column is empty. It now takes 0 px
  unless a row on screen has a checkbox (then 22 px). The cell stays in the
  markup, so parity is unchanged.
* Station headings: 7.5 px labels, "Parts Jita" on one line.
* Saved widths move to `pdc.vehicle-locations-columns.v2:<user id>`. r462-era v1
  widths were saved as rendered widths (often the stretched widths of a wide
  screen) and would otherwise hide the new defaults. v1 values stay on the
  device untouched, so reverting r476 brings them back. **Reset columns** clears
  v2 and restores these defaults; a dragged width still applies and fixes that
  column.
* Undo: revert the r476 commit.

## r481 (F94): search shows where the vehicle is

Craig (22 Oct): with the QC tile selected, searching a stock number that is in
PMB showed "No vehicles match this tile and the search filters".

* While the search box has text, the selected tile (or STOPPAGES) no longer hides
  matches. When every match is in one tile, that tile is selected for the
  search; otherwise **All vehicles** is. Tiles holding a match get a green
  outline; the tile picked before the search gets a dashed outline.
* Panel note: "Found in PMB · showing every tile while you search · QC tile
  comes back when you clear the search". Summary: "… · search “…” · found in PMB".
* Clicking a tile during a search narrows the search results only. Clearing the
  search brings back the tile picked before (kept in memory, as before).
* The Department selector still applies. A match in another department shows an
  amber note "Found in Department 138 — Bus 4×4 · <tile> · <stock>" with a
  **Switch to 138** button (the same as choosing it in the Department box). This
  note also appears in the Drop-down view, which has no tile filter.
* A search narrowing to one vehicle still opens it once (slide-out panel).
* Pure helpers `searchScope()` and `departmentElsewhere()` are exported for the
  tests. Display only: nothing is written or saved.
* Undo: revert the r481 commit.

## r485 (F98): Table view only (Craig, 22 Oct 2026)

Craig: "Let's remove the dropdown view and only keep the table view for PMG.
It's been good. It's working well."

* The **View: Drop-down view | Table view** switch is not drawn. Everyone gets
  Table view when Vehicle Locations opens.
* A saved choice (`localStorage["pdc.vehicle-locations-view.v1:<user id>"]`) is
  **ignored, not rewritten**: someone who had picked Drop-down view gets Table
  view, and the stored value stays on the device so an undo brings it back.
  Blocked storage also gives Table view. Nothing is written.
* **Hidden, not deleted.** One flag in `pdc-vehicle-locations-table.js`:
  `const DROPDOWN_VIEW_ENABLED = false;`. Setting it to `true` restores the r481
  behaviour exactly (switch, drop-down default, saved choice). The drop-down
  render branch, `switchHtml()`, `dropdownSearchElsewhere()` (the r481 note
  "Drop-down view has no tile filter") and the r461 `readView()` / `writeView()`
  rules are all still there.
* `PDC_VEHICLE_LOCATIONS_TABLE.parity()` (read-only self-check) still draws the
  drop-down board for a moment to compare station cells, then puts Table view
  back. It never saves the view.
* Unchanged in Table view: search across tiles and the other-department note
  with its Switch button (r481), the Department box, tiles, column sort / resize,
  the slide-out panel (row click, Enter on a focused row, Escape closes), Parts
  ETA / Parts loc columns. Narrow screens: there was never a drop-down
  fallback. Between 901 and 1180 px the table keeps its 860 px minimum and
  scrolls sideways inside its own area (at 960 px: Age / ETA, Status and
  Booking are off to the right). At 900 px and below the app shows the phone
  QC page instead of Vehicle Locations, before and after r485.
* **Clear stoppage moved to the slide-out panel** (Craig's go-live condition,
  22 Oct: "first add Clear stoppage to the Table view so nothing is lost when
  the drop-down is hidden"). Open a stopped vehicle (from any tile, including
  STOPPAGES, whose rows open the panel like every other row): a **STOPPAGE**
  box above the card lists each stoppage reason (the same label and detail as
  the drop-down's STOPPAGES list) with that list's own button: **Clear
  stoppage**, or **Return to QC** for a QC-rework vehicle that is ready for
  re-inspection (pdc-qc-rework.js). Same code path: `bindFixFirstRows()` ->
  `clearPriorityStoppage()` (note prompt, server-authority check, messages) ->
  `clear_vehicle_stoppage_422`; Return to QC -> `markVehicleReadyForQualityControl()`.
  No new SQL. The buttons show only for **operator** and **administrator**
  (the roles `clear_vehicle_stoppage_422` accepts); other roles see the reasons
  and "Only an operator or administrator can clear a stoppage." Details in
  vehicle-slideout-panel.md.
* **Only in the Drop-down view (not reachable now):** the highlight of
  imported vehicles after a work-file import (`focusVehiclesAfterWorkImport()`
  in app.js opens drop-down cards only).
* Undo: set the flag to `true`, or revert the r485 commit (tree = main 1343900).
