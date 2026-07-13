# Master Sheet Import

## Import completed 13 July 2026

Source: `Master2021 (1).xlsx`, visible `EOS` worksheet.

- 321 real vehicle rows imported.
- 276 numbered-key vehicles mapped to PMB.
- 17 `WPC` vehicles mapped to RFT because they sit in the completed WPC/RFT section and carry an RFT/WPC date.
- 28 `IT` vehicles retained as Production / In Transit with no invented key number.
- The `Test` row with stock `444555` was excluded.
- 85 numbered placeholder rows without a stock number were excluded.
- Hidden copy and test worksheets were not imported.
- No duplicate stock numbers were found.

## Status mapping

| Master sheet field | Website field |
| --- | --- |
| HAT numeric key | PMB location and Key Number |
| HAT `WPC` | RFT location |
| HAT `IT` | Production / In Transit |
| Date In | Kewdale/on-site baseline and PMB entry date |
| Fabrication Status | Fabrication required/complete |
| Parts Status | Parts ordered/issued state |
| PD Status and Build Status | Fitting required/complete |
| MotorOne Tint and PMG Tint | Tint required/complete |
| MMT and PSC | Electrical required/complete |
| Tyre Upgrade | Tyre required/complete |
| SSM/GVM, GVM record, tank, roll bar and seating | Hoist required/complete where explicit |
| Pit Status | Pit required/complete |
| Sublet `@` | Sublet work stream |
| Build `HeldUp` or helper-column job stoppage | Blocked vehicle and blocker reason |

The source sheet can hold several simultaneous `Working` values. The website keeps all of those as outstanding work markers, but only assigns a single PMB work stream when the master gives a strong current-position signal: Sublet `@`, Fabrication `Working`, PD `Working`, or Build `HeldUp`. Other vehicles remain in PMB Unallocated so the migration does not invent a current bay or department.

All original operational status values are retained on each imported vehicle as `master...` fields and in the source status summary. Job card numbers and JITA status were left blank/unknown because the master sheet does not provide reliable values for them; unknown JITA is displayed as `?`, not as a false red cross.
