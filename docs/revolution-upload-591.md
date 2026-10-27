# Revolution upload r591 — comparison with Kajel's 18:11 run

Preview only. The parser was checked against the five reports from Kajel's 27 Oct 2026 18:11 AWST run. The raw files and Kajel's outputs are not in git. This note records counts and field-diff counts only.

The files are Office Open XML workbooks with an `.xls` name. The parser also accepts an HTML table and SpreadsheetML, and it refuses an old BIFF workbook.

## Row match

| Report | Kajel rows | Parser rows | Field diffs |
|---|---:|---:|---:|
| Service as a Whole, rows Kajel sent | 6533 | 6533 of 6866 collapsed lines | 0 |
| CW parts | 519 | 519 | 0 |
| BT deal items 05:35Z | 1433 | 1433 | 0 |
| BT deal items 08:08Z | 1433 | 1433 | 0 |
| KTA deal items | 2501 | 2501 | 0 |

CW, both BT files, and KTA match Kajel's `rows.json` exactly, including department numbers, flags, nulls and source row numbers. Karratha's `broome_sales` flag is false. Broome's is true.

Service matched on the 13 sheet columns, `source_row_numbers` and `sublet_pos`. None of the 6533 sent rows were missing. There were 0 field diffs.

## Service lines Kajel did not send

The file collapses to 6866 department 138/139 lines. Kajel sent 6533. The other 333 stay in this preview on purpose: every 138/139 line is passed to the dry run, and the existing apply still decides archive and the new-vehicle step.

192 of the 333 are Kajel's not-sent holds, and all 192 are present here:

| Hold reason | Lines |
|---|---:|
| staff_lock_1208 | 149 |
| duplicate_line_on_board_1208 | 17 |
| conflict_1208:historical_identity_requires_restore | 12 |
| conflict_1208:closed_vehicle_requires_review | 14 |

The other 141 lines are whole repair orders Kajel neither sent nor listed. All are Type D with a Create Advisor. None of those repair orders appear in the sent parts.

| Sub status | Has stock | Lines |
|---|---|---:|
| blank | yes | 44 |
| blank | no | 35 |
| 80 | yes | 59 |
| 80 | no | 1 |
| 99 | no | 2 |

One of the 44 blank-status lines with a stock is a collapse of 7 source rows. The dry run then skips every status 99 line, including one status 99 line that was inside the 6533 Kajel sent. Kajel did not drop every status 99 before send. This preview does.

## What this dry run does not claim

Kajel's 18:11 apply result was 130 service lines inserted, 0 updated, 1 archived and 8 new vehicles; CW 402 matched, 36 updated and 117 unmatched; KTA 11 inserted, 5 superseded, 153 matched and 80 unmatched. Those numbers are Kajel's apply against the board that afternoon. This preview did not call preview or apply, so it does not repeat them. The dry run compares the parsed rows with a board snapshot in memory and leaves the database alone.

## Gates that stay on

Function md5 pins, including Kajel's two functions and department 135 `fd05b9eef69498002ac06dd68e01cdff`. Pin count 241, with no new pin. More than 15 new vehicles or archives stops the run until an administrator confirms. The key-unique guard refuses a shared non-zero key. Status 99 is skipped. Service is departments 138 and 139 only. Sales boards Broome `37047` and Karratha `14450` are not changed by the PMB archive rule. A vehicle with an open job card is not archived or hidden. A sha256 already in the ledger is a duplicate. Apply is refused around 07:00, 12:30 and 18:00 AWST, and it is refused in this preview at every other time as well.

## Later

Status 80 vehicles on an upload moving to QC, with every item ticked green, is not in this build.

A later pull from `pdc@pmgwa.com.au` would use the same identification, the same sha256 ledger, and the same existing SQL functions. It would still require a Graph message id, mail authentication results showing `spf=pass` and `dmarc=pass` from `mx.microsoft.com`, the sender `noreply@revolutionsoftware.com.au`, and To `pdc@` with Craig copied. It would still refuse quiet hours, still keep Kajel's import beside it until switch-over, and still call no model. Manual upload is the first path.
