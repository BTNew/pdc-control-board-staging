# Fault log

Every fault gets: root cause, a fix that stops it coming back, an undo, and a
check in `pdc_ops.fault_regression_check()` that runs daily.
Times are AWST (UTC+8). Staging Supabase `cdsmnqxtyyoeoznmbidd` only.
No customer names; key and stock numbers only.

Daily check: `select * from pdc_ops.fault_regression_check();` (service role or
PDC administrator). Any row with `ok = false` needs attention.

To add a check: insert a row into `pdc_ops.regression_checks` (as postgres, in
a migration) whose `check_sql` returns one row `(ok boolean, detail text)`. The
runner is STABLE, so a check cannot write. A release that changes a pinned
function must update `pdc_ops.expected_function_md5` in the same migration.

| Id | Date | Reporter | Symptom | Root cause | Fix (release / PR) | Undo | Guarding check |
|---|---|---|---|---|---|---|---|
| F01 | 20 Oct 12:13 | Bhavesh (email) | Keys 246 and 227 (Mechanical) refused for Bays 9 and 10 | Category rule used `preferred_bay` only (Mechanical 1–4), so Bays 9/10 refused whole-job Mechanical work | `allowed_bay()` adds Bays 9/10 for Mechanical, Electrical, Accessories; migration 20261020042257, PR #386 (163f3e9d) | `supabase/rollbacks/20261020042257_bus_bays_9_10_whole_job.down.sql` | `bays_9_10_accept_mech_elec_acc`, `bus_bay_category_grid`, `bay3_hiace_only` |
| F02 | 20 Oct ~12:35 | Bhavesh / Craig | Only one item or Bus section could be started at a time | `conversion_save` refused a second running section; item timing was per job, not per item | Per-item Start/Done timing, several running at once; migration 20261020044621, PR #387 (467f15ff) | `supabase/rollbacks/20261020160000_bay_item_start_done.down.sql` | `multiple_started_items_allowed` |
| F03 | 20 Oct ~14:30 | Bhavesh (via PMB Email) | Close gaps: Apply always "preview is stale"; Bus 4x4 plans refused (`bus_shift_outside_hours`) | Preview fingerprint hashed fields the one-minute clock rewrites; Bus 4x4 was planned on general hours, not the Bus shift | `workshop_capacity_plan` excludes clock fields and passes the bay calendar; migration 20261020063929, PR #391 (2df642ad) | `supabase/rollbacks/20261020063929_close_gaps_clock_stable_preview.down.sql` | `close_gaps_fingerprint_excludes_clock_fields`, `bus_plans_use_bay_shift` |
| F04 | 20 Oct ~13:50 | Bhavesh (via PMB Email) | Key 243 / Bay 9: "Bookings could not be checked" | A Navision relink set 31 Dept 138 vehicles to `microsoft_navision`; the Dept 138 read gate accepted only `tune_pmg` | Read gate also accepts Navision-linked Tune/PMG vehicles; migration 20261020060044, PR #389 (9a71db9d) | `supabase/rollbacks/20261020060044_key243_navision_linked_138_read.down.sql` | `dept138_read_complete` |
| F05 | 20 Oct ~14:05 | Bhavesh (via PMB Email) | Keys 504/510/512 could not be read | Read gate required every open job to be Dept 138; these also have a Dept 139 job | Mixed 138/139 accepted in `workshop_read_vehicle_allowed_20261013`; migration 20261020061025, PR #390 (a1e4323) | `supabase/rollbacks/20261020061025_mixed_138_139_read.down.sql` | `dept138_read_complete` |
| F06 | 20 Oct 16:42 | Craig | Sales table showed no vehicles | Client view/filter state in the browser, not data: the board snapshot returned all vehicles | None needed (no change made); refresh clears it | n/a | `sales_board_has_vehicles` |
| F07 | 20 Oct ~16:20 | Craig | Build/Tint/Tray ticks could be set by hand and drifted from the PO lines | Ticks were stored, with an in-house exemption, instead of derived from PO lines | Ticks derived from PO lines only; ordering write RPCs refuse; migration 20261020083610, PR #395 (f022cc8e) | `supabase/rollbacks/20261020083610_r394_ticks_derived_only.down.sql` | `sales_ticks_derived_only` |
| F08 | 20 Oct 18:16 | Bhavesh (email) | Keys 504 and 509 refused for Bay 8 (`category_bay_mismatch · 22023 · HTTP 400`) | In the all-bays view the card was the Mechanical item and the bay list offered every bay; Mechanical is not allowed in Bay 8. The Mechanical work was done before the board, and there was no way to record that, so the Mechanical item stayed first. The error code was shown raw because the client did not know the bare token. Electrical into Bay 8 was always allowed | Bay lists filtered by category; friendly message; operators can mark Mechanical/Electrical/Accessories "done before the board" with a reason (lines, hours, overrides and history kept; undo available); migration 20261020105452 (r399) | `supabase/rollbacks/20261020105452_r399_bay8_offboard_done.down.sql` + revert the PR | `bay8_electrical_and_offboard_confirm`, `no_booking_breaks_bay_category_rule`, `test_bus_bay8_category_bays.js` |
| F08b | 20 Oct 18:16 | Bhavesh (email) | Search for 509: "Bookings could not be checked" | Same cause as F05 in a second gate: `workshop_nonnav138_read_allowed_20261012` still required Dept 138-only jobs (Keys 509 and 338) | Same mixed 138/139 rule in that gate; migration 20261020105452 (r399) | as F08 | `dept138_read_complete` |

General checks (not tied to one fault): `clock_ticks_recent`,
`qc_cache_zero_mismatches`, `no_orphan_bookings`, `no_double_booked_bays`,
`no_booking_breaks_bay_category_rule`, `karratha_135_hidden_data_kept`,
`protected_function_md5s`. The runner is migration 20261020105501.
