# Reported faults

## F185 — Tint drop between jobs, 27 Oct 2026 11:46 AWST

Craig, Shared Bays, Tint. He dragged Key 112 (stock 13109746, JC J139125966, Kimberley Aboriginal Medical) into Tint Bay 01 between the jobs already there (Key 338 around 12:00, Key 214 around 3:00 pm). The planner showed the raw database error:

> The server rejected this change. No update was saved. conflicting key value violates exclusion constraint "workshop_bookings_active_vehicle_no_overlap" 23P01 · HTTP 400

He asked that slotting a job between other jobs push the later ones back.

### What actually collided

The chip is Tint booking `acd1a2d7-5836-473a-87fd-a0a87d79fff2`, queued, no bay, so it is exempt from the exclusion until it is given a bay. Giving it Tint Bay 01 makes it overlap Key 112's own Fitting stoppage `6d92ccca-a568-46e0-9e3d-b93ad49a008f` (no bay, scheduled Tue 27 Oct 08:28 – Wed 28 Oct 07:08 Perth, 550 minutes). A stoppage with no bay still occupies the vehicle. The live move has no handler for that exclusion, so PostgREST returns HTTP 400 and the page prints the constraint name. Key 338 and Key 214 are the later Tint Bay 01 jobs. They are not the row that fired the constraint. Key 264 is started in Tint Bay 01 at 11:42–12:42 and is not moved.

#557 (r567) is not applied. Its pre-check loads a queued booking with no bay, and it does not load a stoppage with no bay, so this Fitting row would still reach the constraint. It also names a started or stoppage booking and stops, without offering a start after it.

### Preview

r571 / F185 / sort 343. Not applied. Staging only. Stacked on #557. #557's head is not changed. Live tip on main is r569 / F183 / sort 340. Open previews hold r570 / F184 (#544 and #556 at sort 341; the Bay Manager preview at sort 342) and #557 holds r567 / F181 / sort 341. #552 still names sort 342. This is the next free triple.

A timed drop pushes later planned jobs in that bay, on a station bay and on a shared bay, through the administrator move, the plain move, the cascade move, a new booking and the schedule cascade. When the same vehicle is already booked somewhere that can move, #557's blue confirm still asks before pushing it. When that other booking is started or on stoppage, the planner is told it cannot move and is offered the first start after it (for Key 112, Wed 28 Oct 08:08 Perth, an hour after the Fitting stoppage). Later jobs in the destination bay move back only when they start at or after that time. Today's Tint Bay 01 jobs are earlier than that, so this drop does not push them. Cancel saves nothing. A leftover exclusion is a plain sentence. When the server can name the booking, the sentence names the vehicle, the bay and the time. The confirm button is blue (`#1d4ed8`).

Pins stay 241. The move pin moves in place from r567 to r571. Department 135 stays `4eb5baf999b849d174880a1e261fcbf2`. `move_workshop_booking` and `schedule_vehicle_work` keep `search_path` `pg_catalog, public, extensions`. Up file md5 `726a69694d4f9ac465e084f23c436521`. Down file md5 `feaebca749647fdbee92c4afab26affc`.

#557's migration guard treats fault id F181 as free. Staging already has `parts_stoppage_manual_567` at F181, sort 338. This preview does not change that file. Apply #557 only where its own guard can pass, then apply this one.

### Regression check

`slot_between_571` (F185, sort 343). It checks the move body still has the r567 marker and the r571 marker, that the place-after text lives in the helper, that the move, the cascade move, the schedule and the schedule cascade call the helper, that the pin matches the move body at release r571, and that the department 135 move checksum is unchanged. `cross_station_drop_567` is retargeted to the r571 pin and must stay green. The check does not require Key 112's rows to stay in this conflict.

### How to re-test after the preview is applied

1. On staging, Shared Bays, Tint, drop Key 112 onto Tint Bay 01 between Key 338 and Key 214.
2. The blue question should say Key 112 is on stoppage in Fitting, Unallocated, until Wed 28 Oct 07:08, and that this job would start Wed 28 Oct 08:08. It should not print `23P01` or the constraint name. Cancel leaves every booking where it is.
3. Place after. The Tint booking starts Wed 28 Oct 08:08. The Fitting stoppage is not moved. Key 264, which is started, is not moved. Jobs in Tint Bay 01 that start at or after 08:08 move back. Jobs earlier that day stay.
4. Drop a planned job between two later planned jobs in the same bay, with no other booking of that vehicle in the way. The later jobs move back and the drop is saved.
5. `pdc_ops.fault_regression_check()` includes `slot_between_571` and `cross_station_drop_567`, and both are green. Pin count is still 241.

## F181 — Fitting drop onto Thanh's bay, 27 Oct 2026 09:44 AWST

Craig, Workshop Planner PMB (department 139), Fitting. He dropped Key 214 (stock 13047384, MAIN ROADS) into Thanh Truong's bay and expected the later jobs in that bay to move back. The planner showed:

> This change would overlap a vehicle's booking in another bay or station, including any booking pushed back by the change. No conflicting bookings were saved. Use Best slot to find a time with the 1-hour buffer, or move the affected later booking.

Thanh's lane was holding Key 338 (JC J139125823, stock IS60353006, Tams Group, Start job, about 75%) from 12:00 pm to 3:15 pm.

### What actually collided

The drop is an administrator cascade move of the unallocated Fitting booking `676d6c62-89ee-45cd-a9c7-cd22c60253ef` (841 working minutes, queued, no bay). Cascade is willing to push Key 338. The save never lands, because the validation trigger rejects the new Fitting window for overlapping Key 214's own other bookings. Key 338 has no booking in another station.

Staging rows read 27 Oct 2026 (times in Perth):

| Vehicle | Booking | Where | When | Why it matters |
| --- | --- | --- | --- | --- |
| Key 214, stock 13047384, MAIN ROADS | `b6a0c4c7-d3e5-4d73-9491-82a756736c85` | Tint, Tint Bay 01 | Tue 27 Oct 11:30 am – 12:30 pm | The 09:44 am attempts returned this id. A drop at 9:44 am runs through this hour. |
| Key 214, same vehicle | `5012775c-0070-4c00-a9ef-8c943c273c63` | Hoist, queued, no bay | Tue 27 Oct 1:00 pm – Wed 28 Oct 9:30 am | The 09:43 am attempt returned this id. The push planner only loads bookings that already have a bay, so this queued window was invisible to it and the trigger still rejected the save. |
| Key 214, the job being dropped | `676d6c62-89ee-45cd-a9c7-cd22c60253ef` | Fitting, unallocated | placeholder Wed 28 Oct 10:30 am – Thu 29 Oct 2:01 pm | This is the chip Craig dropped. |
| Key 338, stock IS60353006, Tams Group | `0c469ed0-8f5c-46c5-8c23-c6ed358812bc` | Fitting, Thanh (bay 3) | Tue 27 Oct 12:00 pm – 3:15 pm | Same bay. Cascade pushes this. It is not the overlap that aborted the save. |

A plan of the 9:44 am drop, read only, pushes Tint Bay 01 to Wed 28 Oct 2:15 pm and pushes Key 338 back inside Thanh's bay. It does not mention the queued Hoist, which is the hole.

### Preview

r567 / F181 / sort 341. Not applied. Staging only. The next free triple after the live ledger: main is r565 / F179 / sort 337 (side panel, #549). Open previews still hold r566 / F180 / sort 340 (#554), r565 / F179 / sort 339 (#553) and r564 / F178 / sort 338 (#550).

Dropping into a bay still pushes that bay's later jobs and succeeds when the vehicle is free elsewhere. When the same vehicle is already booked in another bay, or queued with a time and no bay, nothing is saved until the planner confirms. The question names the key, the stock, the customer, the station, the bay and the Perth times, and the confirm button is blue. Confirming pushes those bookings (and what they would land on) back, with an hour clear, then the bay drop runs. A started or stoppage booking is named and is not pushed. The same vehicle is not left in two places at once.

Pins stay 241. The move pin is updated in place. Department 135 is not edited. Up file md5 `df1f6da063989cd2e48fbd8f1483fc53`. Down file md5 `60fccd64d7be546b15491964bf4e02cb`.

### Regression check

`cross_station_drop_567` (F181, sort 341). It checks the move body still contains the r567 marker, the confirm refusal, and the older non-cascade push path, that the pin matches that body at release r567, and that the department 135 move checksum is unchanged. It does not require Key 214's rows to stay in this conflict.

### How to re-test after the preview is applied

1. On staging, Workshop Planner PMB, Fitting, drop Key 214's unallocated Fitting chip onto Thanh's bay at about 9:44 am.
2. The blue question should name Tint Bay 01 (Tue 27 Oct 11:30 am) and the unallocated Hoist (Tue 27 Oct 1:00 pm). Cancel leaves every booking where it is.
3. Push back. Key 214's Fitting lands in Thanh's bay, Key 338 moves later in that bay, and Tint and the Hoist move so they start at least an hour after the job in front of them. Key 214 is not in two stations at once.
4. `pdc_ops.fault_regression_check()` includes `cross_station_drop_567` and it is green. Pin count is still 241.
