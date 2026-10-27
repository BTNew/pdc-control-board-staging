# Reported faults

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
