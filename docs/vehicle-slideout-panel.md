# Vehicle Locations — slide-out panel, Parts loc, resizable columns (r462, F75)

> **r463 (F76), 22 Oct 2026 09:03 AWST:** at Craig's request the panel's
> **Jobs & bookings** list and **drag-to-bay** (both options A and B below) are
> withdrawn. r565 (F179) puts drag back on the chip list in edit mode and calls
> `moveWorkshopDroppedPlan` on a bay drop. Bay rules stay in the Workshop
> Planner. The panel shows the vehicle's own card: station strip and status,
> vehicle details (stock number, vehicle key, key number with Edit / History,
> job card, Tune report, parts location) and the operations by category (lines,
> hours, sublets / PO) as the main content, with the card's buttons as before.
> Moving an operation line to another category through *Edit jobs & hours* may
> come later; it is not part of r463.
>
> r463 also adds a **Job Card** column to the Table view, between Stock and
> Customer (the card's own job-card markup; "—" when none; sorts with the
> board's job-card sort; resizable, default 104 px, minimum 64 px). The stock
> number is larger now that the job card is not a sub-line under it. Saved
> r461 / r462 settings keep working: saved widths have no Job Card entry, so it
> shows at its default width.
>
> The sections below describe r462 as released; the drag sections are history.

Change request from Craig, 22 Oct 2026 (slide-out with Option A drops approved;
operations layout 08:07, Parts loc 08:08, resizable columns 08:09 AWST).
Staging only. Frontend only — no database change. Builds on the r461 Table view
(`docs/vehicle-locations-table-view.md`).

## Where it applies

**Table view only.** The Drop-down view stays the default and is unchanged
(a test renders the drop-down board with and without the new modules and
requires byte-identical HTML).

> **r485 (F98):** Table view is now the only view (the Drop-down view is hidden
> behind `DROPDOWN_VIEW_ENABLED` in `pdc-vehicle-locations-table.js`). The
> byte-identical drop-down test now runs with that flag set to true.

## r485 (F98): stoppage box (Clear stoppage / Return to QC)

Craig approved hiding the Drop-down view on one condition: "first add Clear
stoppage to the Table view so nothing is lost when the drop-down is hidden".

* When the open vehicle has an active stoppage (any row app.js
  `workflowPriorityRows()` gives for it: Workshop booking, Parts or PMB), a
  **STOPPAGE** box sits under the header, above the card (outside `.vso-body`,
  so `parity()` and the card are unchanged). Each row shows the reason exactly
  as the drop-down STOPPAGES list does.
* The action button is the list's own markup, taken from
  `fixFirstRowsHtml()` (as wrapped by pdc-qc-rework.js), and bound with app.js
  `bindFixFirstRows()`: **Clear stoppage** runs the same
  `clearPriorityStoppage()` (server-authority check, note prompt, the same
  messages, refresh + render) and the same RPC `clear_vehicle_stoppage_422`
  with the same arguments. **Return to QC** (QC-rework vehicle ready for
  re-inspection) is handled by pdc-qc-rework.js's own document listener. The
  panel file still has no fetch / RPC of its own. No new SQL.
* Shown only to **operator** and **administrator**, the roles the server
  accepts (`r.role IN('operator','administrator')` in
  `20260826193000_422_targeted_stoppage_paths.sql`). Other roles see the
  reasons and a note, no button. (The drop-down list showed the button to all
  roles and the server refused the others.) The same gate applies to Return to
  QC.
* Rows in the STOPPAGES tile open the panel like any other row.
* Version 2026.10.22.r485; cache-bust `vehicle-slideout=2026.10.22.r485`
  (canonical-entry.js), which also reloads the CSS. Tests:
  `test_vehicle_locations_table_only_485.js` 9-13.

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

## r473 (F86): panel top, Open Vehicle (Craig, 22 Oct 2026)

* The open panel no longer shows the card's summary row: no station-icon strip
  and no PMB status / PMB stream / Book all stations box. The table row still
  shows the stations, status and its buttons, and the Drop-down view is
  unchanged. The parity copy (`parityStrip`) still draws the full card, so
  `PDC_VEHICLE_LOCATIONS_TABLE.parity()` keeps comparing every strip.
* An **Open Vehicle** button under the stock / key / JC line opens the vehicle
  card (the same `openVehicleCardFromVisibleBoard` call the stock number made).
  Stock numbers in the panel are plain text.
* When the vehicle card closes, the table and the open panel are drawn again
  from the data, and a control another script adds to an operation line gets
  its own row instead of sitting over the description (Craig saw "Unassigned"
  drop-downs over Hoist line 21 and Electrical line 5 after closing the card).
* Display only: no data, RPC or storage changes. Undo: revert the r473 commit.

## r494 (F107): Manage sublets

A **Manage sublets** button sits beside Open Vehicle (added by `pdc-vehicle-sublets.js`; the panel itself is unchanged). It opens one screen for that vehicle: whole line sublets (the line is Sublet work; its tick completes it) and sublet items on operation lines (the line keeps its category; the PO has its own tick), with GP PO, provider, out / due back / back, status (Away / OVERDUE / Back N days) and Draft email. Operators and administrators can make a line a whole line sublet or move it back (`set_vehicle_work_category`); ticks are the r439 tick.

r494 update (Craig 22 Oct 18:41): whole line sublets with no GP PO show **PO to raise** (board Sublet box orange, and on the line); a new GP PO on a line in another category shows **PO raised for this line** until ticked or **Got it** (per user, this browser); the screen says **Supplier**.

r494b (Craig 22 Oct 18:55): the vehicle's Sublet box is uniform: each line ends in one same-size chip (GP PO number or **PO to raise**), no 'Hours not stated', no 'Op line PO' caption, no 'PO raised for this line' / 'Got it' (here or in Manage sublets), one text size. In Manage sublets 'PO to raise' sits in the GP PO column.
r494c (F107b, site slow after the stack went live): the board's **PO to raise** makes no request and no board redraw while it renders. It uses the board's own Sublet lines and GP PO counts (exact once a vehicle's GP PO lines are loaded by opening it here, in the drop-down or in Manage sublets; until then a safe lower bound). Opening a vehicle may give one debounced board redraw if its count changes.

## r496 (F109): edit hours and jobs in the panel (Craig, 22 Oct 2026, 7:16 pm)

* The operations heading's **Edit jobs & hours** button (which opened the Vehicle
  detail window) becomes **Edit** plus a small **Open full editor** link. The link
  opens the old window, unchanged; it is still where Add line, Edit line and Best
  slot live.
* **Edit** reads this one vehicle (`loadVehicleWorkshopDetail`, the same read the
  window makes when it opens) and shows app.js's own Work & bookings rows in place
  of the read-only list, with every button removed: an hours box per line and the
  Work category (or Station) selector to move a line to another job. Changed fields
  are outlined amber. Nothing is sent until **Save**.
* **Save** runs the window's own save paths in order: `saveVehicleWorkshopLineHoursBatch`
  (Save all hours, changed rows only), then `saveVehicleWorkCategory`
  (set_vehicle_work_category) or `moveVehicleWorkshopLineStage` for each moved
  line, each with the versions app.js has just reloaded. Then only the panel is
  drawn again. **Cancel** drops the drafts. Closing the panel or opening another
  vehicle with unsaved changes asks first.
* Same roles as the window (`vehicleWorkshopCanEditLines`: operator,
  administrator); no SQL. Speed: nothing runs per vehicle when the board or the
  panel is drawn; the table and board are never redrawn by a save.
* Undo: revert the r496 commit (the button and the window come back as before).

## r565 (F179): edit in the same chip list (Craig, 27 Oct 2026, 8:08 am)

* **Edit** stays on this same chip list. It does not open the Work & bookings layout.
  Hour boxes are added to the chips. **Save** writes those hours through
  `saveVehicleWorkshopLineHoursBatch`. **Open full editor** still opens the old window
  for Add line, Edit line and Best slot. Open Vehicle, Manage sublets and the stoppage
  box stay.
* In edit mode a line or job chip can be dragged onto another station or bay. The hours
  travel with it. A station drop calls `saveVehicleWorkCategory` (`set_vehicle_work_category`,
  which extends or shortens the job). A bay drop then calls `moveWorkshopDroppedPlan` or
  `scheduleWorkshopVehicle`, so overlaps, technician clashes and close-gaps stay in those
  functions. A completed chip does not move.
* A line or job that is already completed shows **Completed**, who completed it and when,
  in blue or grey. There is no orange.
* A workshop controller (User Management role `operator`, and an administrator) can tick
  a line completed in the panel, and untick it. The tick is `set_panel_line_completion_565`,
  which records the user and the time and refuses every other role. Other roles see the
  tick read-only. The tick does not change the vehicle, a booking, a category or QC sign-off.
* Opening the panel reads that completion list once (`get_panel_line_completions_565`).
  The workshop detail read still happens only when Edit is pressed, for that one vehicle.
* Craig approved go-live 27 Oct 2026 08:48 AWST. Cache bust `vehicle-slideout=2026.10.27.r565` on the slide-out module, and `r565=2026.10.27.r565` on `canonical-entry.js` and `app.js`. The stock-panel `r560` token stays.
* Undo: revert this commit. If the migration was applied, run
  `supabase/rollbacks/20261027150000_r565_panel_line_completion.down.sql` on staging
  between :02 and :45.

## r694 (F304, 29 Oct 2026): the panel is the vehicle card

- Open full editor is removed (heading button and the editor link).
- A red **Override location** button sits in the top row (operator, administrator). It opens the same dialog as the
  vehicle card (pdc-location-override.js, `PDC_OPEN_LOCATION_OVERRIDE`).
- Station lists show the jobs only: no booking chips and no bay chips. Edit still drags a line onto another station.
- **Move to a bay** at the bottom (administrators): one row per station with bays and open lines. Pick bay, date and
  start time, then Book / Move. It reads this vehicle's bookings once, then sends `administrator_move_workshop_booking`
  (existing booking) or `administrator_schedule_workshop_vehicle` (none) through app.js `vehiclePanelBookingCommand`,
  cascade on. The server keeps every planner rule. Started jobs are moved in Workshop Planner.
- Saved ticks now show as soon as the panel opens.
