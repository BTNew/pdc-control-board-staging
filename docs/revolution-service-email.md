# Automated service email imports

Craig authorised automatic service reports for Departments 138 and 139 on 6 October 2026.

Accept the exact subject PMG PD Service Complete and filename PMG PD Service Complete.xls or .xlsx, or the exact producer variant PMG PD Service Complete - Job 1.xls or .xlsx, verified as an OOXML workbook. Record the actual noreply@revolutionsoftware.com.au source. Receiving Gmail evidence must show aligned SPF and DMARC passes, delivery to the monitor (directly or the established owner-To/monitor-CC route), the exact message ID, and no changed Reply-To.

The management manifest contains the genuine source, attachment hash, immutable payload hash, explicit owner authority, source snapshot, Company 01 and Division 1. Both preview and apply check the automated sender and each row's department/R/O/source envelope. Existing preview/apply request binding, receipt replay, importer transaction and disabled-account restoration remain mandatory. No new grants or accounts are introduced. Bhavesh's delegated scope stays Department 138.

Prepare service before parts. Preserve whole-stock holds, source/staff hours, mandatory current catalogue review for newly prepared missing estimates, normal review queues, rolling omissions, deleted/completed history, conversion checks and guarded QC. An authenticated report is not inspection completion.

A later report with identical source values may be recorded as a verified no-change scan: retain the original file/hash and map every row to its previous verified import or unresolved hold. Do not duplicate intake or review records. Keep its real source snapshot as a freshness watermark for future file comparisons; never describe held rows as applied.

Validation: synthetic authentication/department/hash/grant rejection checks and isolated two-department preview/apply/replay succeeded on staging. The latter ran inside a rolled-back subtransaction; it was not a committed service-file import. The importer returned to its original disabled state. The first automated report's 4,533 source rows matched the earlier owner-provided report exactly, so no service records were replayed.


## CW PMB CSV — owner-authorised 19 October 2026

Craig confirmed Company 01 / Division 1 and instructed the existing monitor to import each genuine **CW PMB Service Complete** CSV on receipt. No repeat authority or extraction-time question is required. The exact original filename is **.csv**. This is an additional supported contract; the original OOXML contract remains supported.

Use the exact fifteen headers: Type, Dept, Stock #, Rego #, Owner Name, Parts Location, Key Tag Number, R/O #, Status, Sub Status, Line #, Operation Desc, Estimated labour hours, Modified Date, Range #. Retain the full original bytes and original header/row values. Type D is a service line; the T1 total footer is retained and excluded. Only exact138/139 rows may enter PMG. Never search for or process dedicated135 reports while parked.

The CSV has no Company/Division or extraction timestamp. Record Craig's fixed scope as owner provenance, not as supplied CSV columns. Use the genuine authenticated producer Email Date as **emission time**, with snapshot_basis authenticated_revolution_email_date and source_scope_basis craig_20261019_fixed_company01_division1. Preserve the Date header and Gmail receiving time and require them within five minutes. Modified Date is per-line evidence, not the snapshot.

The private manifest and row validators bind this exact source envelope, header contract, original filename, receiving authentication, prepared/source hashes and J138/J139 jobcard identities. Other prefixes remain explicit exceptions; never rewrite a B jobcard into J. Supplied Stock takes priority, then exact Rego fallback; absence of Navision alone is not a hold. Initial New Vehicles acceptance and all staff/source-hour, lifecycle, conversion/QC and booking protections remain.

Before every service import, follow tools/import-routing/README.md and save confident semantic AI routing. Accepted-vehicle additions process automatically; protected or ambiguous changes stay visible with their reason, without ordinary Operation Updates approval. A classification-only learned decision may lack fallback hours: management-only complete_reviewed_ai_hours_20261019 can fill a reviewed NULL internal-work fallback with an exact prior-rationale check and an immutable previous-decision audit. It cannot change the category, replace a non-null estimate, supply external/QA/note labour, or edit source/staff hours. Then use remember_ai_routing_20261019 for verification and process_pending with exact affected vehicle IDs, bounded limit and named department filter.

Verification: tests/revolution_cw_csv_contract.sql checks validators, retained OOXML support, rejection paths, private execution permissions and guarded missing-fallback completion, entirely rolled back without operational fixtures. Real file import receipts and canonical readback remain in the private email-monitor ledger; they are separate evidence from contract tests.


The Job 1 workbook filename variant was observed in an authenticated Revolution report on19October2026. It retains the original OOXML worksheet/header/company/division/extraction contract; it is not the CW CSV contract. Other job suffixes and file formats remain rejected. The management-only filename validator changed; source-row, identity, hours, intake, booking/QC and parked135 protections are unchanged. Pure filename/authentication/scope/permission checks were rehearsed with rollback before staging installation and read back afterward.

## Sublet purchase orders — r439 (F50), 21 October 2026

Sublet contractors come on site, so a PO never changes a line's category, bay or booking.

Envelope change for PMB Email:
- The service report may carry seven optional columns after the normal headers: `PO #`, `Job #`, `Document Line`, `Sublet Line`, `Description of sublet`, `Company`, `Division`. CW CSV: the exact 15 headers, optionally followed by exactly these 7 (`revolution_service_headers_439`). Excel workbook: the 14 headers, optionally followed by the same 7 (the workbook branch of the manifest has no header restriction, so it is unchanged).
- Put per-line sublet values in `raw_row.sublet_columns`. Report-level `Company` `01` and `Division` `1` stay as they are (the row validator still requires them).
- `source_headers` in the provenance stays optional.

PO-only import (separate from the service import, never creates or changes lines):
- `public.import_sublet_pos_439(p_rows jsonb, p_source_file_sha256 text, p_dry_run boolean DEFAULT true) RETURNS jsonb`, granted to `authenticated` (importer, controller, administrator) and `service_role`.
- Rows: `[{"stock": "...", "ro": "J139...", "line": 5, "po": "GP13900001"}, ...]` (also `stock_number`, `repair_order_number`, `original_line_number`). Blank stock: send the Rego #. 1 to 30,000 rows; the hash is the 64-hex SHA-256 of the source file.
- Call with `p_dry_run` true to preview (writes nothing), then false to apply. An apply is idempotent per (file hash, request hash): repeating it returns `replay: true`.
- Returns `contract: "pdc-sublet-po-import-439"`, `totals` by status, `lines_with_po`, `vehicles_with_po`, `distinct_pos`, `by_category`, `created_vehicles/jobs/lines`, `category_changes`, `booking_changes` (always 0) and `row_statuses` `[{row, status, stock, ro, line, po, category}]`.
- Statuses: `attached`, `already_attached`, `ignored_blank_po`, `ignored_all_placeholder`, `held_non_gp_po`, `invalid_row/stock/ro/line`, `duplicate_in_file`, `unmatched_stock_not_on_board`, `held_stock_ambiguous`, `skipped_owner_hold`, `skipped_vehicle_rft`, `skipped_vehicle_completed`, `skipped_vehicle_not_active`, `skipped_job_closed`, `unmatched_line_not_on_job_card`, `held_line_ambiguous`, `skipped_line_inactive`, `skipped_line_completed`, `skipped_notes_line`, `held_line_without_identity`.
- Rolling: a PO missing from a later file is never removed, and imports never clear a 'sublet done' tick.

## PMG PD Service Complete w/Sublet — r442 (F54), 21 October 2026

Craig, 21 Oct 15:08 AWST: the Revolution report **PMG PD Service Complete w/Sublet** replaces **PMG PD Service Complete** going forward. The parts, CW and sales feeds are unchanged. The old title and the CW CSV stay accepted, byte for byte, during the transition; retire them in a later release once the w/Sublet report has arrived for a while.

Envelope (same authentication and scope as before):
- From `noreply@revolutionsoftware.com.au` with aligned SPF and DMARC passes, delivered to `pmbcontroller@gmail.com`, exact Gmail message id, no changed Reply-To. Worksheet parameters must show Company `01` and Division `1`.
- Subject and report title (worksheet cell A1) exactly `PMG PD Service Complete w/Sublet`.
- Attachment filename `PMG PD Service Complete w/Sublet.xls` or `.xlsx`, or with ` - Job 1`. Because `/` cannot appear in most filenames, `w_Sublet`, `w-Sublet`, `w Sublet` and `wSublet` are also accepted. Nothing else.
- Manifest provenance: `source_kind` `revolution_automated_service_workbook`, `source_format` `ooxml_workbook`, `subject` and `report_title` = the title, `source_headers` = the worksheet headers (required), `type_column` `absent_r442`, `line_collapse` `r442_one_row_per_dept_ro_line`, plus the usual authority, instruction, company, division and authentication fields.

Headers: the 13 usual columns `Dept, Stock #, Rego #, Owner Name, Parts Location, Key Tag Number, R/O #, Sub Status, Line #, Operation Desc, Estimated labour hours, Modified Date, Range #`, followed only by r439's sublet columns, with `PO #` required (this report sends `Description of sublet` and `PO #`). There is no Type column (r468: Revolution may now send an optional leading Type column, which the preparer drops; see below). r509: an optional trailing Create Advisor column is also dropped by the preparer before this list is checked; see below.

Type: in the PMG 138/139 import, Type was only used by the preparer: `D` marked a service line and the `T1` totals footer was skipped. No database function reads it for 138/139 (only parked Karratha 135 does, and that import is not touched). Without Type:
- a data row has an R/O # and a Line #;
- the single totals footer has neither, and it is kept as evidence but never imported;
- a row with another department is excluded as before;
- any other row shape (an R/O # that is not J138/J139 for its Dept, a Line # that is not a positive whole number, negative or non-numeric hours) stops the whole file. Nothing is guessed and no Type is invented; w/Sublet rows must not carry a `Type` key.

Collapse: the report repeats a service line once per sublet PO. The preparer sends ONE row per Dept + R/O # + Line #:
- hours, description and every other service value come from the first row in source order and are never summed;
- `raw_row.sublet_pos` = every distinct PO of the line (trimmed, spaces removed, upper case, source order; `[]` when none);
- `raw_row.sublet_columns` = the sublet columns of every source row with its `source_row_number`;
- `raw_row.source_row_numbers` = the collapsed rows;
- `raw_row.collapse` = `{rule, source_rows, hours_summed: false, conflict}`. When repeated rows differ outside the sublet columns, the first row is kept, `conflict` is true, and `differing_values` lists every value. The apply receipt reports these.

Reference implementation: `tools/import-rules/revolution_service_wsublet.py` (tests beside it). The row validator refuses a w/Sublet file with a repeated line, a Type key, `hours_summed` other than false, a `source_rows` count that does not match, or a mix of titles.

Sublet POs in the same apply: `pdc_pilbara_service_apply_v1(preview_batch_id, source_hash, idempotency_key)` is called exactly as before. After the service writes and the job sync, it feeds every PO of the file through `import_sublet_pos_439`, keyed by the source workbook SHA-256 and with the same rules: GP POs only, ticks never cleared, POs never removed, no category, bay or booking change, owner-held, RFT, completed and inactive vehicles, closed jobs and completed or notes lines skipped. The result and its single apply receipt carry `sublet_pos`:

`{contract: "pdc-service-sublet-po-feed-442", ok, dry_run, source_file_sha256, po_rows, replay, totals, lines_with_po, vehicles_with_po, distinct_pos, by_category, created_vehicles/jobs/lines, category_changes, booking_changes, ticks_cleared, pos_removed (all 0), import (the full r439 result without row_statuses), exceptions (row statuses other than attached / already_attached / duplicate_in_file / ignored_blank_po), collapse {rule, hours_summed, lines, lines_with_repeats, source_rows, conflicts [{stock, ro, line, fields, kept}]}}`

A file without POs gives `po_rows: 0`. If the PO step fails, `sublet_pos.ok` is false with `code: "sublet_po_feed_failed"`, `sqlstate` and `message`. The service apply still stands, and the POs can be re-run with `import_sublet_pos_439(rows, workbook sha256, false)`. A PO-only preview after the service preview is available to the management connection: `pdc_codex_intake_private.service_sublet_po_feed_442(preview_batch_id, true)` (private, writes nothing). New lines added by the same apply are matched only once they are on the job card (new operations still go through review).

The apply function's md5 changed (pinned): callers that guard it must use `fc3717a5215de94c93ebb2c7facfe744` (was `84e1ed9f1a722719c8c4b5b113e1884f`). The preview function is unchanged (`375bffc2dced95a7a5c74c3273dbccb3`). The only other change in the apply is `WHERE true` on its existing new-vehicle-review `ON CONFLICT ... DO UPDATE` (same behaviour), so the recreated function passes the safeupdate DML lint.

Verification: `tests/revolution_service_wsublet_442.sql` (rolled back, no fixtures), regression check `service_wsublet_contract_and_po_feed`. Undo: `supabase/rollbacks/20261021073319_r442_service_wsublet.down.sql`, run before any r439 undo.

## Bay code on a re-sent line — r471 (F84), 22 October 2026

Kajel reported a stock held as `ambiguous_existing_operation`: Revolution had re-sent an existing line with the vehicle's bay / parts-location code appended (`DE MINE SPEC` then `DE MINE SPEC 05K4F`; on fuel lines `... -- 04K2B`). The description is part of the service identity, so the import kept a second immutable version of the same Dept + R/O + Line # and the stock was held.

- **Preparer** (`tools/import-rules/revolution_service_wsublet.py`): before the preview, `existing_lines_from_operations(operations, superseded_ids)` lists each line's live descriptions and `canonicalise_bay_code_descriptions(rows, existing)` sends the live description when the only difference is a trailing code matching `[0-9]{2}[A-Z][0-9][A-Z]` (optionally after `-` or `--`), whether the code was added, removed or changed. Stems compare case-insensitively. The incoming text stays in `raw_row` `Operation Desc`; `raw_row.description_bay_code_r471` records `{rule, incoming, kept, incoming_bay_code, kept_bay_code}`. Not matched (still a new version / review, as before): any wording change (`HAEVY` → `HEAVY`), extra annotations (`**SUSP 17C6B**`), lower-case or short codes, or more than one live description that could match.
- **Retiring a duplicate** (staging, service role, in the release window): `pdc_service_supersede_private.supersede_operation_471(retired, kept, rule, approved_by, reason, live_booking_ok)` records the retirement in `public.pdc_service_operation_supersessions_471` and deactivates the retired board line with a manual-operator overlay; the operation row and its history are untouched. It refuses unless both versions are the same line, the kept one is live and nothing (completion, rejection, PIT tick, auditor evidence, pending review, live booking on the stage) hangs off the retired one. Rules: `owner_decision` or `trailing_bay_code_471`.
- **Change candidate**: `pdc_tune_operation_change_candidate_20260912` ignores retired versions (md5 `3781d764a2aedf1bbfddab707a1ccfd9`, pinned). Preview `375bffc2dced95a7a5c74c3273dbccb3`, apply `fc3717a5215de94c93ebb2c7facfe744` and the row validator `0534336e01558066cf7ec3dcb3995cd4` are unchanged.
- **Hold step**: a stock is held for several versions only when more than one *non-retired* version exists; the pipeline must pass the retired ids (from the supersession table) to `existing_lines_from_operations` and to its version-count hold.

Undo: the data change first (one per retirement, restores the overlay exactly), then `supabase/rollbacks/20261022021500_r471_service_operation_supersede.down.sql`. Tests: `tools/import-rules/test_revolution_service_wsublet_471.py` (synthetic R/Os only), `tests/service_operation_supersede_471.sql`, `test_service_operation_supersede_471.js`; daily check `service_operation_supersede_471`.

## Optional leading Type column — r468 (F81), 22 October 2026

Kajel reported the 22 Oct 08:33 AWST w/Sublet report held: Revolution now sends a leading **Type** column (`D` on data rows, `T1` on the totals footer). r442 refused any Type column. From r468 the preparer (`tools/import-rules/revolution_service_wsublet.py`) accepts it as OPTIONAL and drops it, the same way the sales feed drops its Type column:

- `Type` is accepted only as the first header (exactly `Type`; surrounding spaces trimmed). Anywhere else, twice, or in another case, the file stops.
- `D` = a data row: it must have an R/O # and a Line # (a row of another department is excluded as before). `T1` = the totals footer: it must have neither, it is kept as evidence and never imported, and there is still at most one. Any other value (blank, `d`, `T2`, `D1`, a number, ...) stops the whole file with the worksheet row number: `row N: Type 'X' is not D (data) or T1 (footer); only D and T1 are accepted`.
- The Type cell is removed before anything else is built: `source_headers` are the headers after it, no `raw_row` carries a `Type` key, and source row numbers are still worksheet rows. The manifest marker stays `type_column` `absent_r442` (no Type column reaches the database); `source_type_column()` gives `leading_type_dropped_r468` (or `absent`) for the provenance evidence.
- A file without Type parses exactly as before (a test pins the r442/r444 output digest).

No database function changed: the manifest (md5 `e4ba03437490bd155d4d8553285107f8`), the row validator (`0534336e01558066cf7ec3dcb3995cd4`) and the service apply (`fc3717a5215de94c93ebb2c7facfe744`) are as r442/r444 left them, and `service_wsublet_contract_and_po_feed` still checks that a Type header or Type key is refused there. Tests: `tools/import-rules/test_revolution_service_wsublet_468.py` with synthetic fixtures `tools/import-rules/fixtures_service_wsublet_468.py` (2,572 lines across 154 stocks with 243 sublet POs, with and without Type, plus bad Type values; `python3 fixtures_service_wsublet_468.py DIR` writes the three workbooks).

## Sublet descriptions — r444 (F57), 21 October 2026

Craig approved 21 Oct 16:24 AWST: the vehicle drop-down's Sublet box lists every sublet with its 'Description of sublet' from the upload.

- Store: `public.pdc_service_line_po_refs_439` gains `description` (as typed, ends trimmed, at most 1,000 characters) and `description_source_file_sha256`.
- `import_sublet_pos_439(rows, sha256, dry_run)`: each row may carry an optional `description` (string). It is stored when the PO is attached and replaced only when a later file has a non-blank one; a blank or missing description never clears it. Row statuses carry `description` = `none` / `unchanged` / `set`, and the result has `descriptions` counts. Everything else is unchanged (GP POs only, ticks never cleared, POs never removed, no category, bay or booking change).
- w/Sublet preparer (`tools/import-rules/revolution_service_wsublet.py`): each collapsed line carries `raw_row.sublet_po_descriptions` = `{PO: description}` for the POs in `sublet_pos` (a PO repeated with different descriptions keeps each distinct one in source order, joined with `^`, Revolution's own line break). The key is optional: the row validator accepts a line without it, and refuses an object keyed by a PO that is not in `sublet_pos` or with a non-string value (strings up to 4,000 characters).
- The service apply is called exactly as before (`pdc_pilbara_service_apply_v1` is unchanged, md5 `fc3717a5215de94c93ebb2c7facfe744`); its PO feed `service_sublet_po_feed_442` now passes each PO's description (from `sublet_po_descriptions`, or `sublet_columns."Description of sublet"` for r439 CSV / workbook rows).
- `get_pdc_sublet_lines_439` lines add `po_details: [{po_number, description}]`.
- Function md5s (pinned, release r444): `import_sublet_pos_439` `6083fb5bcf03d341d9101831c2217cb8`, `sublet_po_vehicle_439` `756b7a4164a6e9ce37bb33c7c861b346`, `service_sublet_po_feed_442` `66379d312c3fddfd2eaab5b37c0ba497`, `revolution_service_rows_20261006` `0534336e01558066cf7ec3dcb3995cd4`.

Verification: `tests/sublet_po_descriptions_444.sql` (rolled back, no fixtures), regression check `sublet_po_descriptions_444`. Undo: `supabase/rollbacks/20261021083212_r444_sublet_po_descriptions.down.sql`, run before any r442 or r439 undo (it drops the stored descriptions).

## Full open-R/O snapshot: "PMG PD Service as a Whole w/Sublet" — r479 (F92), 22 October 2026

Revolution sends a second report, **PMG PD Service as a Whole w/Sublet**: every open R/O of Depts 138 and 139 (parameters `Company = "01" Division = "1" (Dept = "138" or Dept = "139") and Status >= "20" and Status < "90"`), with the same 15 columns as w/Sublet. The header cells arrive as Excel formula text (`="Dept"`).

- **Preparer** (`tools/import-rules/revolution_service_whole.py`, which calls the w/Sublet library): checks the title and that the parameters cover the full snapshot, unwraps the `="..."` headers, then hands the sheet to `revolution_service_wsublet.read_values` / `collapse`, so the Type column (r468), one-row-per-line collapse (r442), PO feed and descriptions (r439 / r444) and bay-code rule (r471) are the w/Sublet ones. r509 (below): an optional trailing Create Advisor column is accepted on that same reader and dropped before the manifest.
- **Identity** (`raw_row.identity_r479 {rule: r479_exact_board_stock_or_job_card, basis}`): a non-blank Stock # must equal a board stock (no fuzzy or prefix match, no fallback). A blank Stock # links only on, in order, Rego # = a board stock, R/O = the vehicle's job card number, or an existing service job for the R/O. Exactly one live (active / rft) vehicle links; several is `ambiguous`; only completed / deleted matches is `vehicle_not_live`; none is `no_board_vehicle`. Only linked R/Os are sent to the preview, which is unchanged: lines are added or updated on linked vehicles only, a vehicle or job is never created, and owner / standing holds, r471 supersede and the 80 / 99 checkout guard apply as before.
- **Key Tag**: from an as-a-Whole preview, `pdc_apply_tune_key_number_v1` only fills a blank board key (a set key is kept, reason `board_key_not_blank_r479`), so hourly snapshots never overwrite a controller's edit. Parts Location is already a Revolution-only value (`service_location_fields`) and is stored as before.
- **Snapshot** (private schema `pdc_service_snapshot_private`, postgres only): the preparer writes `snapshot-record-NN.sql` (2,000 lines per call) calling `record_snapshot_479(header, lines)`; lines are `[dept, R/O, line, board stock, file stock, file rego, sub status, identity]`. Idempotent (a re-sent part records nothing, a changed value is refused), append-only, newest 48 snapshots kept. Nothing on the board is written.
- **Review list** (`reconcile_479(sha DEFAULT NULL)`, `review_list_479()`, read-only): `open_ro_no_board_vehicle`, `ro_all_lines_80_99_still_open`, `board_vehicle_missing` and `board_ro_missing` (a live vehicle / open service R/O absent from the last two consecutive complete snapshots; with one snapshot they show as `..._pending`). Nothing is closed, hidden or deleted.
- **Sub Status 99 checks a vehicle out once.** The 'as a Whole' report re-sends every open R/O, 99s included, every hour. `capture_service_status` (called by the unchanged apply) keeps every earlier rule: a vehicle with any checkout receipt, in QC / RFT, inspected or transferred is skipped. On top of that, a 99 R/O that is already on one of the vehicle's checkout receipts, or that was already at 99 in a service import before an owner reopen (audit action `owner_reopen_workshop_status`), never completes the vehicle again (`service_99_used_479(vehicle, stock, company, division, R/O)`: `checkout_receipt` / `used_before_owner_reopen` / NULL, read-only). Only a 99 not used that way can check a vehicle out, once. A used 99 is skipped silently: no review row every hour. The review list's 80/99 items carry `checkout_99_used`.
- Function md5s (pinned, release r479): manifest `63ff5dabf94abcdf7c278fb3afa9bd96`, row validator `b5e3ab4517bd59a1931509a2b9a1299f`, key import `7db7b5482de592222cfc5828ff9e6a45`, `append_only_479` `1ab209a3fff8dbc2efe3051f17c42703`, `record_snapshot_479` `fe1aa81a9ff00b6071eb4c0b7ea1a4ab`, `reconcile_479` `f4470aaa28afeb5a89fa206edb8a6076`, `review_list_479` `a84de72c728027dcea5a2d9adb4c04ad`, `capture_service_status` `7870d544117de6a5465b8212f0d228b7` (was `3cc871d85d84195d9f8f65113a03e1ef`, unpinned), `service_99_used_479` `574255e4c99e77830069f74ad849d9b4`.

Undo: `supabase/rollbacks/20261022043000_r479_service_whole_snapshot.down.sql` (refuses while snapshots exist unless `SET LOCAL pdc.r479_undo = 'discard_snapshots'`). Tests: `tools/import-rules/test_revolution_service_whole_479.py` (synthetic), `tests/service_whole_snapshot_479.sql`, `tests/service_99_once_479.sql`, `tests/r479_local_harness/run.sh`, `test_service_whole_snapshot_479.js`; daily check `service_whole_snapshot_479`.


## r505 (F118): Outlook / pdc@ mailbox

From 23 Oct 2026 the shared sign-in helper also accepts the as-a-Whole / w/Sublet report when it arrives in Outlook on `pdc@pmgwa.com.au` (see `docs/revolution-parts-email.md` r505). The service rows validator accepts `mailbox` `pdc@pmgwa.com.au` as well as `pmbcontroller@gmail.com`. The service manifest body is unchanged; bind `p_message_id` to the Outlook internet / Graph message id for the Outlook path.

## Optional trailing Create Advisor — r509 (F122), 23 October 2026

Kajel (Email Bot) is blocked on the filtered as-a-Whole workbook `CreateAdvisor-Service-as-a-Whole.xlsx`: `check_headers` in `tools/import-rules/revolution_service_wsublet.py` allowed only the 13 service columns plus the optional sublet columns, so a trailing **Create Advisor** column (values such as `OB` / `BP` / `GR`) held the file. Craig's feed is as-a-Whole with the report filter `Create Advisor <> ""` (only rows that have a Create Advisor). Compared with the latest unfiltered feed, 59 R/Os drop out (all Dept 139); 54 of those are already open on the board and must stay open.

Preparer only. No SQL. `revolution_service_headers_439` (md5 `bfda8a3acd8a08bb36f5851ead2cd5e4`), the manifest, the row validator and the checks `service_wsublet_contract_and_po_feed` and `service_whole_snapshot_479` stay as they are, because Create Advisor is dropped before `source_headers` is built (the same pattern as the leading Type column). Sending the raw worksheet header row, with Create Advisor still on it, is still refused by the database. That is intentional.

- The column is accepted only as the last header, exactly `Create Advisor` (surrounding spaces trimmed; Excel formula text `="Create Advisor"` unwrapped). Anywhere else, twice, or in another case (`create advisor`), the file stops.
- It may follow the optional leading Type column. Both are removed before anything else is built: `source_headers` are the headers after the drop, and no `raw_row` carries a `Create Advisor` or `Type` key. `source_create_advisor_column()` gives `trailing_create_advisor_dropped_r509` or `absent` for provenance. The manifest marker stays `type_column` `absent_r442`.
- When the column is present, a **data** row with a blank Create Advisor is not imported. It is counted on `read_values().create_advisor` (`blank_data_rows`, `blank_data_row_numbers`) and left out of the data rows that `collapse` sees. The totals footer and other-department rows are classified as before, even when their advisor cell is blank. A file with no Create Advisor column is unchanged (`column` `absent`), including the r468 golden digest.
- `create_advisor.closes_board_cards` is false. This preparer does not close, hide or delete a board card. An R/O that is missing from the filtered file is simply not in the preview. r479 `reconcile_479` is unchanged and read-only: after two of these filtered snapshots it may list an open no-advisor R/O as `board_ro_missing`. That list does not close the card. Do not add a close step for it.
- Worksheet title stays `PMG PD Service as a Whole w/Sublet`. The parameter cell must still contain Company `01`, Division `1`, Dept `138` or `139`, and Status `>= "20"` and `< "90"`. `Create Advisor <> ""` may be additional text in that cell; it does not replace those clauses. Filename: the Revolution name, or `CreateAdvisor-Service-as-a-Whole.xlsx` / `.xls`.

Kajel: point the as-a-Whole preparer at `CreateAdvisor-Service-as-a-Whole.xlsx`. Use `revolution_service_whole.source_headers` (or `check_headers`) as `source_headers`, not the raw header row. `read_values().create_advisor.blank_data_rows` should be 0 on that filtered file (the report filter already dropped empty advisors; the footer is not a data row). Preview only. Do not apply a close for the 54 open Dept 139 cards that are absent from this file.

Undo: revert the r509 commit. Nothing to undo in the database. Tests: `tools/import-rules/test_revolution_service_create_advisor_509.py`, `test_create_advisor_509.js`. The r442 / r468 / r471 / r479 preparer tests stay as they are.
