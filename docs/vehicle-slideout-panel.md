# Vehicle Locations — slide-out panel, Parts loc, resizable columns (r462, F75)

Change request from Craig, 22 Oct 2026 (slide-out with Option A drops approved;
operations layout 08:07, Parts loc 08:08, resizable columns 08:09 AWST).
Staging only. Frontend only — no database change. Builds on the r461 Table view
(`docs/vehicle-locations-table-view.md`).

## Where it applies

**Table view only.** The Drop-down view stays the default and is unchanged
(a test renders the drop-down board with and without the new modules and
requires byte-identical HTML).

## Slide-out panel

* Click a row (or Enter) in the Table view: a panel slides in from the right
  over the table (scrim behind it). Close with ✕, Escape or a click on the scrim.
* Contents, top to bottom: header (stock, model, key, job cards, departments,
  the card's own **Open** button), the vehicle's station strip and status
  (the board's own HTML), **Jobs & bookings**, then the full existing card
  (operations, parts, buttons).
* **Jobs & bookings** lists each booking by station with category, bay,
  start → end (Perth), hours and status. It uses the existing Workshop detail
  read (`get_vehicle_workshop_detail_scoped`, the same cached read the card
  uses); if that is not loaded yet it shows the board's own booking list and
  fills in when the detail arrives. Technician names appear only once the
  station's planner data is loaded (the detail read has no technician).
* The card's buttons are the r461 ones (`bindBoardHandlers` export); the panel
  adds no new actions.

### Dragging a booking to another bay

* Grab ⠿ on a booking: the station's bay tiles appear. Each tile says
  **Fits**, **Asks to confirm** (it breaks the Dept 138 bay guide,
  bus_bay_guide_447, or Bay 3's no-Coaster rule) or **Current bay**.
  Dept 139 / shared stations have no bay rules.
* **Option A (normal path).** On drop the panel loads that station's planner
  data in the background with the planner's own loader
  (`renderWorkshopPlannerWhenReady` modules, `initWorkshopSharedServicesIfEnabled`,
  the data service's `setScope`) and calls the planner's existing
  `moveWorkshopDroppedPlan(planId, station, bay, date, startMinutes)` with the
  booking's own date and start time. Everything after that is the planner's
  existing behaviour: its bay-rule warn-and-confirm (Cancel leaves everything
  as it is; OK books it and the override is logged with the user's name), its
  live-move confirm for started / STOPPAGE jobs, its own checks and messages.
  The panel never calls an RPC itself.
* **Started / STOPPAGE jobs**: a drop onto a bay that breaks the bay rule is
  refused in the panel ("use the planner", with an Open in planner button);
  an allowed drop goes through the planner's live-move confirm.
* **Fixed (no drag)**: Completed, Pit - external and Sublet bookings; a
  Bus 4x4 booking waits until its category has loaded.
* **Same bay**: nothing moves (reordering within a bay stays in the planner).
* **Option B (fallback)**: if the station data cannot load or is not ready in
  15 s, the panel closes, the station planner opens on that booking with the
  bays around it (`openVehicleWorkshopBooking`) and the target bay is outlined
  for a minute, with a message to drag it there.

## Operations section in the panel

Category panels are full width and stacked. Each operation line is one row
(PD line, description, hours, GP / PO chips). A long description ends in an
ellipsis; the full text shows on hover (title and a small popover) and on
keyboard focus. Chips, icons, ticks and colours are unchanged. All rules are
scoped to `#vso-shell`, so the Drop-down card is not affected. The panel also
overrides the 1510 px minimum width `styles.css` gives the card grid, which made
the r461 panel overflow to the right.

## Table: Parts loc column

The **Loc** column is replaced by **Parts loc**: the card's own
`Parts location: …` span (`pdc-service-locations.js`, PMB vehicles on staging),
moved into its own cell; "—" when there is none. It sorts naturally
(`5A < 05E2A < 05E10`, blanks last) and the search box matches it.

## Table: resizable columns

* Drag a header's right edge (or focus it and use ← / →; double-click resets
  that column). Minimum widths keep every heading readable; the station column
  keeps its width so its symbols and colours never change; long text is cut
  with an ellipsis and a hover title.
* Pinned Key / Stock keep working: their sticky offsets follow the widths.
* Widths are saved per signed-in user per device, like the view switch:
  `localStorage["pdc.vehicle-locations-columns.v1:<user id>"]`. Bad or blocked
  storage = default widths.
* **Reset columns** (beside the work-status key) clears the saved widths.

## Parity

`await PDC_VEHICLE_LOCATIONS_TABLE.parity()` now also draws each vehicle's
panel station strip off-screen and compares it with the drop-down strip
(`panelVehicles`, `panelStationCells`). Local harness on a read-only staging
snapshot (22 Oct 2026): 400 vehicles, 3,573 station cells, 3,573 panel cells,
0 mismatches at default widths and after a resize.

## Files

* `pdc-vehicle-slideout.js` / `.css` — new (`2026.10.22.r462`).
* `pdc-vehicle-locations-table.js` / `.css` — r462 (Parts loc, resizing,
  panel hook, parity extension).
* `canonical-entry.js`, `index.html` — cache-bust tags; `pdc-auto-reload.js`
  stays first. `scripts/build_pages_runtime.js` ships the new files.
* `test_karratha_release_boundary.js` — approved hashes updated.
* `styles.css`, `app.js` — untouched.

## Undo

Revert the r462 commit: the r461 Table view and side panel come back. Saved
column widths are ignored by r461 and can stay.
