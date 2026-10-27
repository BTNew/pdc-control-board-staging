# Reported faults

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
