# PMG Stock-only intake — STAGING

Target: `BTNew/pdc-control-board-staging`, Supabase `cdsmnqxtyyoeoznmbidd` only.

The existing `pdc_pilbara_service_preview_v1` and `pdc_pilbara_service_apply_v1` now accept Tune/PMG rows with Department 138/139 and an immutable workbook digest. Non-Tune requests retain the dynamic Revolution contract. No extra importer or task graph was introduced.

## Request and continuation

Use the retained operational task `t_9562e4d6` under `t_7194c433`. Hermes still owns operational intake using its existing restricted viewer identity; this release does not activate any runtime or grant administrator privileges.

Send the original resolved partition to the same three-argument preview RPC with a new idempotency key for this correction. Keep `p_source_hash = 056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814`. Do not resubmit the old preview ID to apply: it remains immutable evidence of the former blocked outcome. A new `pmg_stock_v3` preview revision can evaluate the same source digest. It must report 121 Stocks / 1,395 accepted operations before apply.

Each row retains the existing fields: `stock_number`, `repair_order_number`, `original_line_number`, `operation_description`, `source_estimated_hours`, `parts_on_backorder_raw`, and `raw_row`. Department is read from `department` or `raw_row.Dept`; the workbook digest is read from `workbook_sha256` or `raw_row.parent_attachment_sha256`. Proposed stations and nullable operation codes can be supplied at either level. The retained resolved evidence already has the required raw fields.

Workbook: `PMG Test Run.xlsx`, email `10/09/2026 Import`, message `1a0899faa2b63679`, SHA-256 `d19014d07e363c16e808b609a353d5968237b1ad19813446606c334e55d49984`. The workbook digest and partition digest are stored separately in immutable batch `source_link`; raw source rows and classification provenance remain immutable.

For the 105 unidentified operations, submit the separately retained full R/O partition through the same preview/apply route, with its own actual partition digest and new idempotency key. Keep Stock blank and the original workbook digest. Supply the retained proposed stations; the tests' fallback REVIEW values are not a replacement for Hermes' prepared classifications. No Stock is inferred from registration, owner, or R/O. A Stock can propagate only from an unambiguous supplied Stock in the same complete R/O payload. Rows with VIN require the identity review route rather than discarding VIN evidence.

The ten unbound R/O groups are `J138000829`, `J139125531`, `J139125533`, `J139125539`, `J139125569`, `J139125594`, `J139125596`, `J139125597`, `J139125603`, `J139125634`.

## Result and safeguards

- One exact canonical vehicle per valid Stock; check existing current, historical, alias, tombstone, and Navision identities. Conflicts fail closed. Tombstones are not recreated. Existing operational/approved vehicles are not reset.
- New external records: `source_system=tune_pmg`, null VIN, Yard Hold, active, hidden from the board, New Vehicles pending. Existing unambiguous Navision-linked hidden pending records are reused without replacing location authority.
- Tune identity: Department + R/O + exact Stock + Line + normalized description. Same-line different descriptions survive; operation codes remain nullable. Later real codes are retained through append-only operation history and authoritative projection without duplicating the operation.
- Dept 138 always projects to BUS_4X4 and cannot be overridden by classifier v2 or the New Vehicles controls. Dept 139 uses the retained per-operation proposals, with existing current classifications/manual corrections taking precedence.
- Unknown groups persist in `pdc_unidentified_tune_review`, with no vehicle column or foreign key. Their source evidence is immutable and independently replayable.
- No booking, completion, technician assignment, PMB transfer, or automatic approval is performed.

`pdc_pmg_intake_readback_v3(apply_batch_id)` is the restricted authoritative result, including vehicle state, operations, Department/stations, hours, codes, source linkage, and unidentified rows. The existing `list_pdc_new_vehicle_reviews` remains the actual New Vehicles page source. `list_pdc_unidentified_tune_reviews(offset,limit)` powers its separate read-only Unidentified Tune Review list.

## Verification and limits

Rollback acceptance used all 1,395 retained resolved rows: 121 canonical vehicles, 1,120.68 hours, every source operation's station and hours verified in New Vehicles projection, and exact preview/apply replay. Original workbook parsing independently verified 1,500 operations and 1,233.24 hours. The unbound test used all 105 actual workbook rows / 10 R/O groups / 112.56 hours with zero vehicles, exact replay, and rejection of changed source evidence. Edge cases cover same-line different descriptions, duplicate rows, zero hours, code enrichment, conflicting Departments, changed source hash with reused idempotency key, and unauthorized callers. Booking/completion counts did not change.

All 340 JavaScript regression tests passed. Headless browser checks used the actual New Vehicles module with rollback database readbacks: Department 138 locked to Bus 4x4, all 10 unbound groups / 105 operations displayed, no unbound approval control, and queue cleared on signout. This is browser integration acceptance, not a claim that a live operational import was committed.

All acceptance data was rolled back. The operational import and live populated-page acceptance remain for Hermes on the retained task after deployment. No connector to resume that local Hermes task is exposed in this workspace.

Security advisors flag the intended authenticated SECURITY DEFINER read APIs and the deny-direct-access queue with RLS and no direct policies. These follow the existing scoped-RPC architecture: anonymous EXECUTE is revoked, caller role/identity is checked inside the APIs, and authenticated direct table reads/writes remain denied. Production was not accessed or changed.
