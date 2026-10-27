# Reported faults

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
