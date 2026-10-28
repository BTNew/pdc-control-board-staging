# Reported faults

## Parts ETA in the table no longer sets a date

Craig, 28 Oct 2026 06:05 AWST. On Vehicle Locations the Parts ETA cell (`Set`) does nothing when you click it. The date should be read in that column. It is set or changed only in the vehicle side panel, in the PARTS ETA section that opens when you click the vehicle. That section must also offer Place as STOPPAGE, the same choice from #561 (r581), so the vehicle can go into the planner's Stoppage section. The side panel is slow to open and slow when a date is set.

### Cause

The cell and the panel both asked a function named `refreshAllViews` to repaint. That function is not defined anywhere, so the click stored "editing" and then drew nothing. Opening the panel built the vehicle card, then built it again when the completion list came back, and every Vehicle Locations refresh built it again. Each of those builds also asked for the email notes and the line handoffs. A burst of operation chips queued a layout read for every chip.

### Fix

r595 / F209 / sort 365. Craig approved go-live of #571 at 06:59 AWST on 28 Oct 2026. Re-checked at 08:35 AWST. Staging `cdsmnqxtyyoeoznmbidd`. Production `vjdtsswhroyguxyfjdkt` was not touched. The ledger tip before this apply is `outstanding_station_hours_594` (r594 / F208 / sort 364). r592 / F206 / sort 360, r590 / F204 / sort 361 and r593 / F207 / sort 363 are live. Sort 362 stays with the Revolution preview (#575, r591 / F205). r588 / F202 is the live tick grid and inserted no check. Pin count stays 241. No pin is inserted. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel's rows validator stays `9be0883b1a555f48f3c1ba9fa111c891` and the apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The manual save stays `fa275b45be296e9021f9f4dc570f5751`. The stoppage board stays `c22076cba374291befa2ea23fc59f276`. No function body is replaced, so those functions still return the same bytes. Up md5 `0607df33cbbfd15d27ab5cfca3c78b40`. Down md5 `fe31fe1960c370a336853e5653044c1e`.

The Parts ETA column shows the date and nothing you can click to set one. Set date, Change, and the blue Place as STOPPAGE checkbox are in the side panel. Saving a date calls the existing save. Ticking Place as STOPPAGE calls the existing r581 place. It does not download the stoppage list again. The planner Stoppage section updates from that reply. A tick with no date opens the date form and does not write.

The panel is drawn once per open. When the completion list arrives it puts the ticks back on the chips instead of building the card again. A Vehicle Locations refresh that still shows the same vehicle does not build the card again. Chip inserts share one layout pass.

The five-column operation grid from r588 stays. Its cache-bust stays `vehicle-slideout=2026.10.28.r588` on the script and the stylesheet (`VERSION` is still `2026.10.28.r588`). The script URL also carries `r595=2026.10.28.r595`, and `index.html` keeps `r588=2026.10.28.r588`. The Parts ETA block is a direct child of the detail grid (`grid-column: 1 / -1` only there). It is not on an operation line, so it does not share the PO-chip or tick tracks.

### Timings

The SQL is not applied, and no function body changes, so the server times stay the times of the live functions. On staging, stock 13018398 (`be6b9a21-99cd-4779-85a0-8b770d43b832`), `get_panel_line_completions_565` was 1.891 ms (368 buffer hits). The same read earlier in this pass: email notes 4.6 ms, one vehicle's station icon 7.8 ms, the cached QC lines 1 ms, and the station-icon list for 200 vehicles 131 ms and about 150 KB.

Before, a click on Set stored "editing" and painted nothing, because `refreshAllViews` is not a function. Opening the panel built the card, then built it again when the completion list came back, and every table refresh built it again. Each extra build asked for the email notes and the line handoffs a second time. In the slide-out fixture, 40 opens that each receive a completion row now draw 40 cards (80 including the 40 board rows drawn first) and a refresh of that same vehicle draws none. The old path would have drawn the card again for each of those 40 completion replies and again on the refresh. Setting a date and ticking Place as STOPPAGE is two calls, `set_pdc_parts_stoppage_564` then `place_parts_eta_stoppage_573`. The stoppage list is not downloaded again. A local run of that script, with the network stubbed, showed those two calls and then the planner Stoppage section for 13018398. The live board was not signed in, and nothing was written to staging.

### Check

`parts_eta_panel_only_595` (F209, sort 365). It goes red if the manual save, the stoppage board, the email ETA, Kajel's two import functions or department 135 change, if Place as STOPPAGE is missing, if the pin count leaves 241, or if r595 inserts a pin.
## Revolution report upload

Craig approved the build on 28 Oct 2026 at 07:10 AWST and go-live on 28 Oct 2026 at 08:05 AWST. Staff upload a Revolution report on Admin > Revolution uploads. The server reads the file and shows what would change. No model is in the loop. Apply does not write the import tables. Kajel's imports keep running. Switching over needs a separate go-live. Production `vjdtsswhroyguxyfjdkt` was not touched. Staging `cdsmnqxtyyoeoznmbidd` only.

Kajel's rows function stays `9be0883b1a555f48f3c1ba9fa111c891` and the apply function stays `b62fb7c29ffd2a1629f214f696e5cb14`.

### Fix

r591 / F205 / sort 362. The ledger already has r592 / F206 / sort 360, r590 / F204 / sort 361, r593 / F207 / sort 363 and r594 / F208 / sort 364. Sort 362 was the free hole. r589 / F203 stays with #571. r584 / F198 / sort 356 stays with #498. Pin count stays 241. No new pin. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. The upload page uses blue (`#1d4ed8`, `#dbeafe`, `#2563eb`).

The edge function names the report from its title and headers, refuses the wrong report, and parses the rows. A dry run counts new, updated, archived and skipped, plus one hold list. Each held line has one reason: closed-vehicle conflict, identity changed, identity restore, staff-lock, status 99, duplicate line, or carried-over not-sent. The SQL apply raises until the switch-over. More than 15 new vehicles or archives needs an administrator confirm. Service keeps departments 138 and 139 only. A status 99 line with no live board vehicle is held. Broome Sales `37047` and Karratha Sales `14450` are not changed by the PMB archive rule. A vehicle with an open job card is not archived.

Up `supabase/migrations/20261028080000_r591_revolution_upload.sql` file md5 `ce3c83acf2c296c9594661dc828f14e6`. Down `supabase/rollbacks/20261028080000_r591_revolution_upload.down.sql` file md5 `5d7ae37ce1165e4bf2a6dfc43986e896`. Applied on staging as ledger `20261028004802` `r591_revolution_upload`. The new check is green. Pins stay 241. The seen table is empty. Kajel's two functions and department 135 are unchanged. The two clock checks were already red before this apply (lock timeouts at 07:24, 07:35 and 08:37). Ticks from 08:43 through 08:48 succeeded. No new red, so nothing was rolled back. The comparison is in `docs/revolution-upload-591.md`. 6,533 sent lines match with 0 field diffs. The 333 holds match Kajel's three hold files with 0 diffs.

Later: a status 80 vehicle moving to QC with every item ticked green, and pulling the same reports from the pdc@ inbox.

### Check

`revolution_upload_591` (F205, sort 362). It goes red if apply is enabled, if the Kajel pins move, if department 135 moves, if a new pin is added for this upload, or if the sanity confirm stops being raised above 15.

## New to PMB is a view, not an acknowledgement

Craig, 28 Oct 2026, 06:01 AWST, clarified 06:03 AWST. Craig approved go-live at 08:05 AWST. This is for vehicles at Yard Hold and for non-division vehicles. When one arrives off a truck, staff tick To PMB and enter a key number, and it goes straight onto the board in the PMB bucket. Nobody approves or acknowledges it. New to PMB is a view only: it lists vehicles whose key number is under 4 days old, so people who log in can see what has arrived recently and make arrangements. Those vehicles appear in both places, the PMB bucket and the New to PMB list. The counter is display only.

### What the key time is

The time is `public.pdc_vehicle_key_assigned_562.assigned_at`, which r562 already stores. It is the earliest of the key audit, a vehicle audit event, the service key snapshot, or the clock when a blank key was first filled. This release does not invent a time. A vehicle with a key but no row in that table is not tagged. On the 20 open rows read at about 06:10 AWST, the stored sources were `service_snapshot`, `audit_events` and `assigned`. `service_snapshot` is a time already stored on that row, not a time made up for this view.

### What happens to vehicles waiting for acknowledgement

The apply closes the acknowledgement and leaves the location, the key and the bookings as they are. A read of the 20 open rows (no body-builder hold was open):

Both the PMB bucket and the New to PMB view (key under 4 days, already at PMB), 15: IS51036977 key 637, 13073086 key 146, 13094165 key 139, 13073095 key 150, 13102818 key 205, 13047384 key 214, 13092999 key 10, 12728609 key 514, 1IJM275 key 16, 13032863 key 310, 13000608 key 329, 13073065 key 410, 13073072 key 280, 13073071 key 259, 13073070 key 333.

PMB bucket only, key older than 4 days, 2: 13008249 key 238, 13070395 key 415.

PMB bucket, no key and no assignment time, so not tagged, 2: 12660039 and 12662903. The one-time release flag lets those two close. A normal close still requires a key.

Not shown in PMB, 1: 13017931 key 205 is already at RFT. Closing its acknowledgement does not change its location, and the key is older than 4 days so it is not tagged.

A location of OD - Delivered To Bodybuilder still does not enter PMB by itself. It waits until someone presses To PMB. The acknowledgement after that press is gone.

### Department booking

The earlier department tick no longer gates booking and no longer removes the vehicle from one department's list. There is one shared New to PMB view and one PMB bucket. The booking functions are not replaced. A PMB card still has Ready for QC, To PIT, Open, book-all and the station controls. The bay dialog can still be called, but it is not offered as an acknowledgement step. A body-builder vehicle is not in the PMB bucket until To PMB. After that, if the key is under 4 days, it is in both places.

### Fix

r593 / F207 / sort 363. Craig approved go-live 28 Oct 2026 08:05 AWST. Applied on staging `cdsmnqxtyyoeoznmbidd` as ledger `20261028002119` `r593_new_to_pmb_view`. Production `vjdtsswhroyguxyfjdkt` was not touched. The required tip was r592 / F206 / sort 360. r589 / F203 / sort 361 stays with #571. r590 / F204 also names sort 361. r591 / F205 / sort 362 stays with #575. r584 / F198 / sort 356 stays with #498. The apply closed 20 open acknowledgements. None of them was a body-builder hold, so none stay open. Locations, keys and bookings were not moved. The new check is green: pins 241, window 4, stray open arrivals 0. Baseline was 130 checks and 2 reds (`clock_ticks_recent`, `clock_tick_latency_trend`), both already red from the 07:24 and 07:35 lock timeouts. Post-check was 131 checks and the same 2 reds. No new red, so nothing was rolled back. Ticks at 08:20, 08:21, 08:22 and 08:23 succeeded in under a second. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Public `fitter_job_command` stays `626ca8b23a2e5f02e2ca8f96a4533d6f`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. Up md5 `e1cccdb804201b859fe4d23e1694add8`. Down md5 `17117e1b891371252125ac94d68e3048`. The tag and the counter use blue (`#1d4ed8` / `#dbeafe`).

### Check

`new_to_pmb_view_593` (F207, sort 363). It goes red if a non-bodybuilder move opens an acknowledgement, if To PMB still waits for a department, if the day window is not 4, if a booking function is rewritten, if the pin count leaves 241, or if department 135 or the Kajel imports change.
## QC sign-off refused on stock 13047122

Craig, 28 Oct 2026 07:00 AWST. He opened QC stock 13047122, ticked every item, and the screen would not sign off QC / RFT. His rule: once the vehicle has been through the workshop, every item is ticked, and every station icon is green, QC must be able to sign off. That includes a line or a station a workshop controller or an admin overrode to complete (#564). Craig, 28 Oct 2026 08:05 AWST: ignore the cut-off "and once" in his QC message. Sign-off is the end. No extra step follows it. The vehicle moves to RFT and stays there. Craig approved go-live 28 Oct 2026 08:08 AWST ("Go live #577").

Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched. This release does not sign 13047122 off. Craig does that.

Stock 13047122 (VIN MR0PEBHV300404116, key 322) is in QC, version 40, with no QC completion time. All 10 checkable QC lines are ticked and have hours. The completion photo is stored. There is no open booking, no running clock on an open booking, no parts stoppage, and no sublet booking. The Sublet station icon is green, 4 of 4, because the QC ticks and Craig's side-panel ticks (including Pit and weigh) count. There is no station-override row. The Sublet work-item box is still required and not completed. `pdc_qc_gate_issues` returns only `outstanding_required_work:SUBLET`. The before-update trigger raises `QC gate failed: outstanding_required_work:SUBLET` (SQLSTATE 22023). The screen keeps that code, or on the phone says sign-off was not confirmed, and does not say Sublet.

The #564 icon turns green from a QC tick, a side-panel tick, the latest fitter Done, or a controller override. It does not mark the work-item box complete. The QC gate was still reading only that box.

### Fix

r590 / F204 / sort 361. r588 / F202 is the live side-panel tick grid (frontend only). r589 / F203 stays with the open PRs #570 and #571. r592 / F206 / sort 360 is the hoist place-after check already on the ledger. A station the icon calls complete is not outstanding work. A line counts as ticked for sign-off when the QC flag, a panel tick, the latest fitter Done, or a completed station override says so. The sign-off button stays on the screen. While something is still open it is grey and the note names it, for example "Sublet is still required. The station icon is not green." The sign-off function returns that sentence instead of raising 22023. The r405 gate pin moves in place. No pin is inserted. Pin count stays 241. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The clock tick stays `3b2398e33a2ea35fc137deeedeca4af5`.

Up `supabase/migrations/20261028080000_r590_qc_signoff_override.sql` file md5 `6cfc288ff55922d9f4d1e803080b802b`. Down `supabase/rollbacks/20261028080000_r590_qc_signoff_override.down.sql` file md5 `9b61c048454366ee9d40fd6377a4fd6e`.

Applied on staging. Ledger row `20261028002147` `r590_qc_signoff_override`. The vehicle was not signed off. After the apply it is still QC, unsigned, version 41. `qc_signoff_outstanding_590` as Craig returns ready, with nothing outstanding. The gate lists no issues. The F204 check is green: pins 241, icon gaps 0, panel gaps 0, override gaps 0, stock 13047122 clear. `protected_function_md5s` is green, 241 pinned, 0 changed. The earlier dry-run had already shown finalize would return `qc_signed_off_moved_to_rft` and then rolled that back.

### Check

`qc_signoff_override_590` (F204, sort 361). It goes red if a green station icon is still listed as outstanding work, if a panel tick or a station override does not count as a ticked line, if stock 13047122 is still in QC unsigned and the gate still names Sublet, if the sign-off wording is missing, or if the pin count, department 135, Kajel, the clock, or the QC line reader moves.
## Key 460's Hoist card still says 12.00 hours

Craig, 28 Oct 2026 08:02 AWST. The search card for Key 460 (stock 13071838) said "Unallocated · 12.00 hours retained", and he was still seeing the running-job conflict toast. On the Hoist / GVM panel everything is ticked except one GVM upgrade. That open line is 5.00 hours. The long-range tank (2.00 h) and the other GVM line (5.00 h) are ticked.

The 12.00 h is the unallocated booking's saved duration. The station estimate added every Hoist line and did not look at the panel ticks. A drag of that card then sent 12.00 h, which is the whole station, not the work still to do.

r594 / F208 / sort 364. The station estimate now skips a line whose panel tick is complete. An unallocated drag uses that estimate, so Hoist books 5.00 h. The same rule applies to every station on this planner. The card says how many hours are still to do. Key 460 is not booked by this release. Department 135's own hours function is not changed.

## Key 460 would not go into Jason Ranoco's Hoist bay

Craig, 28 Oct 2026 06:28 AWST, then "fix it" at 06:31 AWST. Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched. Key 460 (stock 13071838, job card J139125587, 12.00 h, unallocated) was dropped onto Hoist bay Jason Ranoco as the next job after Key 328. The toast said: "This change conflicts with a job already running or on stoppage. No changes were saved."

Two `administrator_move_workshop_booking` calls at 06:27 AWST returned HTTP 200. That is a drag with cascade on, not Schedule and not Best slot. Key 328 is started. Its chip ends at 10:12, but the booking's real end is 12:05. The 12 hour window overlaps that running job, so `cascade_workshop_booking_move_pre_116` returns `live_booking_conflict` and never pushes the later jobs. There is no "too many vehicles" limit on this path. A plan at 10:12 already wants to move the 10 later jobs in the bay, and the mover's step cap is 800.

### Fix

r592 / F206 / sort 360. r588 / F202 is the side-panel tick grid and has no check. The Parts ETA release is r595 / F209 / sort 365 (#571). r590 / F204 is the QC sign-off label named by the Revolution preview, and r591 / F205 / sort 362 is that preview (#575). A drop that overlaps a running job or a stoppage in the bay asks, in plain English, to place this job at the next working minute at or after that job's real end. Later planned jobs in the bay move back. Cancel leaves the bay as it is. The running job is not moved. Key 460 is not booked by this release; Craig drops it.

The question is `place_after_running`. The confirm sends `place_after_confirm.plan_hash` once. `administrator_move_workshop_booking` stays the r571 pin `6a02115d30578e8eb3807a283b1d60ea`. The pin catalogue stores that signature with `timestamp with time zone`, and the release looks the pin up in that spelling. Pin count stays 241. No pin is inserted. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The clock tick stays `3b2398e33a2ea35fc137deeedeca4af5`.

Up `supabase/migrations/20261028081000_r592_hoist_place_after.sql` file md5 `9ddf6478b361c9736f543b32b695195f`. Down `supabase/rollbacks/20261028081000_r592_hoist_place_after.down.sql` file md5 `610e7526ca91cb6a1e716292bf61a0ef`.

#542 (r560 / F174) is already on main and in the published planner: a stock number opens the Vehicle Locations side panel. This release does not change that SQL. `test_stock_opens_side_panel_560.js` is part of the website regression run.

### Check

`hoist_place_after_592` (F206, sort 360). It goes red if the cascade mover still returns `live_booking_conflict`, the code the planner shows as "This change conflicts with a job already running or on stoppage. No changes were saved." A valid place-after drop asks to place the job after the running one and does not show that toast. The check also goes red if the place-after helper is missing, if the move pin changes, or if department 135 or Kajel's functions change. The apply itself still requires the pin count to be 241. The ongoing check does not lock that total, because the regression self-test rejects a check that does. `test_hoist_place_after_592.js` runs in `node --test test_*.js` and fails if that toast is the message for `place_after_running`.

## Side panel: PO chips overlapped the completion tick

Craig, 28 Oct 2026 07:19 AWST. Go live on staging. Stock **13092999** (Hilux DCC), Vehicle Locations side panel.

On operation lines the hours, GP/PO chip (`GP1 63458`, `PO to raise`, `GP1 63459`) and the controller **Tick** checkbox sat on top of each other, especially in the **Sublet** section. Long descriptions left no room for the trailing columns at the real panel width (~420px).

### Fix

r588 (F202). Frontend only. Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched. No SQL. Pin count stays **241**. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel import md5s stay `9be0883b1a555f48f3c1ba9fa111c891` and `b62fb7c29ffd2a1629f214f696e5cb14`.

`pdc-vehicle-slideout.css` uses a five-column grid inside `#vso-shell`: PD line, description (ellipsis + hover full text), hours, PO chip, completion tick. Panel rules override `pdc-sublet-po.js` chip placement (`grid-column: 2 / -1`) so chips no longer span the tick column. Green completed lines, blue override buttons and accent colours are unchanged.

Cache bust `vehicle-slideout=2026.10.28.r588` on `pdc-vehicle-slideout.js` / `.css` and `r588=2026.10.28.r588` on `canonical-entry.js`.

### Check

`test_vehicle_slideout_tick_grid_588.js` (no new `fault_regression_check` row). Before publish, `pdc_ops.fault_regression_check()` was 129 checks with one existing red (`clock_tick_latency_trend`, not introduced by this release).

## Control board QC lines and nested work items

Craig, 28 Oct 2026 05:18 AWST, release 2 of go live and optimise the board. Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched. The vehicle-board lock convoy is r586. This release is the eligibility snapshot the control board reads.

A cold `pdc_ops.eligibility_snapshot_compute_554()` was about 2.2 seconds. QC lines were already cached, and calling the wrapper once per vehicle was about 60 ms of that. Candidate work items were looked up once per eligibility row. A grouped read in `ctid` order matched all 1220 live rows.

### Fix

r587 / F201 / sort 359. PR #498 keeps r584 / F198 / sort 356. r586 / F200 / sort 358 stays the board waiter release. The eligibility function joins `qc_operation_lines_cache` and still calls `pdc_qc_operation_lines_379` when a vehicle has no cached lines. It does not fill that cache. Work items are aggregated once per vehicle and stage, in `ctid` order, and the candidate row reads that list. The public wrapper stays `9207f7c1664552122775bb4a2e6d9f25`. The apply compared the whole snapshot, including `generated_at`, before and after in one transaction and would have rolled back if it differed.

Pin count stays 241. No new pin. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The clock tick stays `3b2398e33a2ea35fc137deeedeca4af5`. The board body stays `1b8106327e68624c8f235c2e84641842`. QC lines stay `b7f90bff12643229ff80f8ca552663a2`, `97fc4caaf7b462163d35b4a3511bc487` and `a93005010cf96ab6eb804ef879039861`. The compute body moves from `f744636778e0f10128d6457605430c2f` to `a328867510e60f5b5f03c42368600c82`. Station eligibility moves from `633a0124502c70d88a552985af2c6e2e` to `cc9af22998b96b07d51eec43dda6e5d9`. `read_once_snapshots_554` names the new compute body. The detail line that records the r554-era checksum is unchanged.

Up `supabase/migrations/20261028064500_r587_board_qc_nesting.sql` file md5 `ef5d9480b7319e275886441f3be706c3`. Down `supabase/rollbacks/20261028064500_r587_board_qc_nesting.down.sql` file md5 `e398b30fcb254c2151f80330f1dc75b2`.

The clock before the apply was green: 781 runs since r552, p95 76 ms, last 30 minutes p95 619 ms, max 690 ms, 0 whole-tick failures in 24 hours. Baseline was 128 checks and 0 red. One attempt started on the clock second and rolled back with no ledger row. Live ledger `20261027224137` `r587_board_qc_nesting`. No data rollback.

Before, five computes, median 2202.2 ms: 2273.1, 2231.0, 2187.5, 2201.5, 2202.2. Payload without `generated_at` was md5 `4436ae90c3c77cf4b732c3628465a4d4`. After, five computes, median 1840.1 ms: 1937.5, 1902.3, 1839.4, 1840.1, 1823.1, 1588053 bytes, md5 `941758803a8beb55714a9d23acc00c4a`. Those two samples are minutes apart, so the checksums are not the identity proof. The identity proof is the in-transaction compare. The post-check was 129 checks and 0 red. The new check's cached wrapper calls were 0.5 ms and 0.3 ms, 1588055 bytes.

### Check

`board_qc_nesting_587` (F201, sort 359). It goes red if the per-vehicle QC call or the per-row work-item lookup comes back, if the wrapper or the public eligibility function changes, if the first call takes 8 seconds or more, if the second call takes 2 seconds or more, or if the two payloads differ.

## Vehicle board waiters blocked on the rebuild lock

Burt, 28 Oct 2026 06:19 AWST. `get_pdc_email_vehicle_board_snapshot_conditional` convoyed on an advisory lock. One PostgREST call was active for 12 seconds holding the lock while it rebuilt, and four more were waiting on Lock/advisory and climbing toward the 8 second authenticator timeout. The control board mean was about 4.4 seconds. Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched.

The conditional read calls `get_pdc_email_vehicle_board_snapshot()`. That function tries the r545 lock and, on a miss, blocks until the holder finishes. Postgres logged 696 calls of the conditional RPC, mean 5454.6 ms, max 29812.3 ms. At 06:23 AWST the stored snapshot was revision 250559, 42.5 seconds old, 16149117 bytes, md5 `344b4a5ed091569ab196d26f3f1e3caa`, so the next caller would rebuild and everyone else would wait.

### Fix

r586 / F200 / sort 358. PR #498 keeps r584 / F198 / sort 356. A fresh snapshot, same revision and under 15 seconds, is still returned with no lock. One caller builds the next copy. Anyone who does not get the lock returns the last stored snapshot at once, even when it is a few seconds stale. A cold cache, with no row yet, polls for 1.5 seconds and then returns `board_busy`. It does not take the blocking lock. The rebuild strip is unchanged, so the holder's JSON stays byte-identical to the previous rebuild.

The board function is not pinned. Pin count stays 241. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The clock tick stays `3b2398e33a2ea35fc137deeedeca4af5`. The conditional read stays `5b50acbf467ad4f38d3a8f9a062cc12e`. QC lines stay `b7f90bff12643229ff80f8ca552663a2`, `97fc4caaf7b462163d35b4a3511bc487` and `a93005010cf96ab6eb804ef879039861`. The new board body is `1b8106327e68624c8f235c2e84641842`. `read_once_snapshots_554` now names that body instead of `ae706516b88574c1162e2c5889e4b4a9`.

Up `supabase/migrations/20261028063000_r586_board_waiter_cache.sql` file md5 `3eee2d7a0096acabe78390d037acf419`. Down `supabase/rollbacks/20261028063000_r586_board_waiter_cache.down.sql` file md5 `3ce8e597edee4a773316fcac7b90ae00`.

The clock before the apply was green: 767 runs since r552, p95 75 ms, 0 whole-tick failures in 24 hours. Baseline was 127 checks and 0 red. A fresh five-call sample was not taken before the apply: the stored snapshot was already stale, and calling the old function would have taken the blocking lock. Ledger `20261027222945` `r586_board_waiter_cache`. No rollback.

After, five direct calls, median 220.0 ms: 928.9 ms (the rebuild), then 203.4, 220.0, 220.4 and 219.3 ms. All five returned the same JSON, md5 `ac2219fd1e57212b8a5ce02c8881e224`, 16275814 bytes, and that JSON matched a strip of the location snapshot in the same transaction. Five conditional calls, median 297.4 ms: 423.8, 297.4, 291.2, 298.7, 292.1 ms, 16275860 bytes. Dropping `snapshot_token` leaves the same md5. No session was waiting on an advisory lock. The post-check was 128 checks and 0 red.

### Check

`board_snapshot_waiter_586` (F200, sort 358). It goes red if the blocking lock comes back, if a second call takes 2 seconds or more, or if the two payloads differ.
## Station snapshot and the sublet board were past 8 seconds

Craig, 28 Oct 2026 05:18 AWST. Go live and optimise the board. Staging `cdsmnqxtyyoeoznmbidd` only. Production `vjdtsswhroyguxyfjdkt` was not touched.

Since 27 Oct 12:33 AWST the station snapshot and the sublet PO board were rebuilt by every open planner at once. Postgres logged 57 station RPCs in that window, average 20.3 s, p50 20.3 s. An uncontended call was already under a second. r545 caches the vehicle board and r554 caches location and eligibility. Neither covers these two reads. The calculation bodies had not changed.

### Fix

r585 / F199 / sort 357. PR #498 keeps r584 / F198 / sort 356. The public functions authorise first, then keep that exact JSON for 15 seconds. One caller builds it. The others wait for that copy. A station revision, an email revision, or a QC-line generation drops the station copy. An email revision, a QC-line generation, a PO sighting, or a sublet tick drops the board copy.

The calculation checksums stay `98cc6aafa9cc7627c77eda8b46b389fa` (station) and `7dde7e19d31b269136a93ebecd12217a` (sublet). Pin count stays 241. The sublet pin stays release r439 and now names wrapper `17b223a6d98bd9c3d1326f6393b9213e`. The station wrapper is `d395400d2a34e8b39ed6d382efa48b35`. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. Kajel rows stay `9be0883b1a555f48f3c1ba9fa111c891` and apply stays `b62fb7c29ffd2a1629f214f696e5cb14`. The clock tick stays `3b2398e33a2ea35fc137deeedeca4af5`.

Up `supabase/migrations/20261028054500_r585_station_sublet_cache.sql` file md5 `26c2acf14134025c9ee553a760b14989`. Down `supabase/rollbacks/20261028054500_r585_station_sublet_cache.down.sql` file md5 `39d5342046ebfcdfee7394e0ed61a021`.

Before, five uncontended runs, about 05:40 AWST, median: Fitting 692.0 ms (`ad842b6408f957de6324e0fadd720d35`, 562372 bytes), Hoist 399.3 ms (`73c76f7db21842aea28acc8cba9a67d0`, 267246 bytes), Tint 471.7 ms (`5c76b9c010147c7bffc814cb6d6fb92f`, 373773 bytes), sublet 442.4 ms (`9571c569873296ac482ecfd530e5a0c5`, 28815 bytes).

After, five runs, median: Fitting 8.4 ms, Hoist 0.4 ms, Tint 0.4 ms, sublet 0.8 ms. The first call of each five is the rebuild (Fitting 746.3 ms, Hoist 410.2 ms, Tint 489.3 ms, sublet 460.8 ms). Each returned JSON matched a fresh calculation in the same transaction. The sublet md5 stayed `9571c569873296ac482ecfd530e5a0c5`. Fitting, Hoist and Tint bytes moved with the workshop between the two samples (Fitting 562889 bytes, stable md5 `ec8eb94c492ee81f1555ab50d9a32dc3`).

The first apply, ledger `20261027214343`, was rolled back by `20261027214828`. Its check read the cache with the regression statement's snapshot, so a row committed while that statement was running looked like a mismatch (`stored f/f`). The other 126 checks stayed green. The check now reads the cache in its own command. Ledger `20261027215121` is an empty probe and changed nothing. Live is `20261027220606` `r585_station_sublet_cache_apply`. The post-check was 127 checks and 0 red. The baseline before the apply was 126 checks and 0 red. The clock before the apply was green: 721 runs since r552, p95 74 ms.

### Check

`station_sublet_cache_585` (F199, sort 357). It goes red if either read takes 8 seconds or more, if two calls disagree, if the stored JSON is not the JSON that was returned, or if the calculation checksum moves.

## Send a fitter line to another department

Craig, 27 Oct 2026. On the Fitters iPad, stock 13073300 (key 307) has a poly water tank line (`source:354acf7c-04bc-4c0d-8a6c-e825af5fde4e`, "POLY WATER TANK WITH 12V PUMP - SIZE TBC") filed as Fitting. The work belongs to Electrical. The fitter needs to send that one line to Electrical, and optionally a bay, then finish the rest of the fitting job. The line stays outstanding for Electrical. The workshop controller sees it on Vehicle Locations (including New to PMB) and books it into an Electrical bay. Either person can undo it. The station icon counts it for Electrical and does not turn that station green until the line itself is done.

### Fix

r583 / F197 / sort 355. Preview only. The SQL was not left applied. Staging `cdsmnqxtyyoeoznmbidd`. Production `vjdtsswhroyguxyfjdkt` was not touched. The ledger tip before this preview is sort 354 `station_icon_completion_578` (r578 / F196) and sort 353 `bodybuilder_new_to_pmb_574` (r582 / F195). Pin count stays 241. No pin is inserted. Department 135 stays `fd05b9eef69498002ac06dd68e01cdff`. `fitter_job_command` stays `626ca8b23a2e5f02e2ca8f96a4533d6f`. Up md5 `9befa8a68fc4fcb470085314f30147fe`. Down md5 `295843b41146173cabc7fe85f343273b`. A rolled-back staging apply plus `fault_regression_check()` returned pins=241, reds=0, checks=126. The up-then-down round trip restored the live function bodies and left no handoff table.

Blue (`#1d4ed8` / `#2563eb`) marks a sent line. Green stays complete.

### Check

`line_handoff_583` (F197, sort 355). It goes red if the send, undo or list is missing, if a handed-off line is treated as finished work, if the station icon no longer remaps the line, if the pin count leaves 241, or if department 135 changes.

## 13077205 hours won't change

Craig, 27 Oct 2026 12:02 AWST. Stock 13077205 would not let him change the hours.

### Cause

Saving hours does not write the hours on their own. It copies the whole job-line wording into an hours record that refused any description longer than 180 characters. Stock 13077205 has two such lines (297 and 329 characters). Craig's Save at 12:01 AWST hit that check. Postgres rejected the new row (`vehicle_workshop_line_adjustments_description_check`, code 23514). The screen said only that the hours batch was rejected. A short line on the same vehicle saves. The vehicle is one row, department 139, not deleted and not hidden. There is no booking and no existing hours record. The job card is not sub status 80 or 99. Today's other go-lives are not the cause. The side panel from #549 is only the editor that calls this save.

The wording is the real job text. No source row is wrong, so this preview does not change vehicle data.

The same state on non-deleted vehicles: 47 lines, longest 329, on 34 stocks: 12710966, 12710968, 13003383, 13004183, 13017855, 13025962, 13025963, 13047337, 13047338, 13047339, 13052490, 13071999, 13075144, 13077191, 13077196, 13077197, 13077198, 13077199, 13077200, 13077201, 13077203, 13077205, 13077206, 13077210, 13077211, 13092247, 13102906, 13102907, 13102908, 13102909, 13102910, 13102911, 13102912, 13106992.

### Fix

r573 / F187 / sort 344. Staging only. #552 is live as r572 / F186 / sort 342. r571 / F185 / sort 343 is left unused for #559.

The public hours description may be 1 to 2000 characters, still trimmed, still with no control character. Department 135 stays at 180. Pin count stays 241. The hours-batch pin moves in place from `e21c5c8901714498c71b75ea9caaf812` to `8255bcf5461babcc01714481fcd8cbe0`. A line whose wording still cannot be stored returns `hours_description_rejected` and names the line. The screen says the hours were not saved and why. Outstanding Parts paint stays as it is.

### Check

`hours_description_fits_573` (F187, sort 344). It goes red if any non-deleted vehicle has job wording that is empty, untrimmed, has a control character, or is longer than 2000 characters, or if the public limit is no longer 2000, or if department 135's limit is no longer 180. It does not require stock 13077205 to keep these two long lines.

### How to re-test after the preview is applied

1. On staging, open stock 13077205 and change the hours on the long Sublet line (the FMG BEV fleet signage wording) from 1.50 to another value, then Save.
2. The hours stay at the new value. The screen says the hour row was saved. Cancel is not required.
3. A line whose wording is longer than 2000 characters is refused in words, and no other line is changed.
4. `pdc_ops.fault_regression_check()` includes `hours_description_fits_573` and it is green. Pin count is still 241.
