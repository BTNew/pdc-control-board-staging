# Automatic external-operation routing

Status: released to working staging `cdsmnqxtyyoeoznmbidd` at **23:18 Perth, 26 October 2026**, as migration `20261026151839` (`new_addition_external_routing_20261026`). Fresh readback at 23:19 Perth matched all three expected source hashes below, preserved function metadata, and confirmed the station-resolver pin within the 241-pin registry. No backlog retry or operational data migration was run. Production is prohibited.

## Verified fault

An uploaded new **Pit & Weigh** line could be rejected with `operation_schedule_conflict` / `operation_readback_mismatch`. The automatic proposal still read an older `BUS_PIT` dictionary entry and proposed `PIT_INSPECTION`, while the current owner-approved canonical rule projected the same line as `SUBLET`. The acceptance readback guard correctly rolled the change back.

The Department 138 station validator had another independent path: its resolver selected an AI category before the current external-operation rule. Changing only the proposal could therefore still fail for a learned classification that disagreed with the canonical rule. The resolver also serves vehicle and email read projections, so changing its global precedence would have affected existing work.

## Repair and preserved rules

The proposal uses the **existing** `note_fee_sublet_521` and `perth_delivery_sublet_523` predicates for an unapproved new addition. It does not introduce a new keyword mapping or rewrite the AI/dictionary tables.

The server-selected estimate already belongs to the automatic approval receipt. Acceptance makes that same decision available inside its transaction before the adjustment validator runs; the final normal receipt retains it. Any subsequent refusal rolls the source insertion, linkage, provisional receipt and adjustment back together. Clients cannot supply this marker through the public approval RPCs or write the protected review table directly.

The Department 138 resolver honours only the exact `canonical_external_sublet_20261026` decision on the matching approved added-operation review, with a currently matching external description. Existing reviewer and routing-history decisions remain first. No old receipt is reinterpreted and no existing row is rewritten at installation. Later uploads for an operation created by this rule use its current projected category, including subsequent staff choices, instead of returning to a stale learned mapping.

Original imported hours remain evidence. Department 139 retains its established effective-hour standards: the current Pit and Weigh/full-fuel standard projects `0.17` hours; it does not rewrite the original source hours. Department 138 keeps its existing explicit-source-hour behavior. Zero-hour Sublet lines remain supported. The existing precision, missing-hours, saved-estimate, inactive/rejected/completed-work and scheduling guards remain in force.

## Files and application order

1. `supabase/proposals/new_addition_sublet_routing_20261026.up.sql`
2. `supabase/proposals/new_addition_sublet_receipts_20261026.up.sql`

The only supported complete deployment is `supabase/proposals/new_addition_sublet_combined_20261026.up.sql`. It wraps both up bodies atomically in that order, taking the same nonblocking clock-then-mutation locks before either function changes. Keep its complete transaction intact so an acceptance cannot observe a mixed deployment.

Each proposal checks the environment and exact installed function/dependency hashes. It preserves function identity, owner, grants, security mode and other `pg_proc` metadata. The existing station-resolver integrity pin changes only to the verified new source hash. No row repair or backlog retry is included.

| Function | Before source MD5 | After source MD5 |
|---|---|---|
| `pdc_operation_updates_private.proposal(uuid)` | `48d590c26ddc7e1c92449450a841c931` | `1c1eb17a1594f36489cf33572117d642` |
| `pdc_operation_updates_private.accept_change(uuid)` | `b51e1d2211722fe2c04c246d5e0a0d83` | `91683e76e8418e2d3f305ae152451965` |
| `pdc_bus_private.operation_station(uuid)` | `03e96225dc36891ec0d122aecd87b967` | `e9ee86ee7214bcfeb920343eb01bca83` |

## Verification

The combined disposable-copy runs (phases 8 and 11) passed the updated accepted-import and category fixtures. They covered new external additions in both departments, unchanged source hours, effective-hour standards, stale learned rules, later uploads, subsequent manual category choices, completed-work refusal, and a forced failure after source linkage proving atomic rollback.

All **8,817** pre-existing operation-station results and **557** uncached vehicle-operation projections were identical before and after application. The unused-release inverse restored all three exact function definitions, their metadata, and every integrity pin. The disposable database was stopped and removed. These are database rollback tests, not proof of a live authenticated browser import or drag.

The existing approved-source index supports receipt lookup; `EXPLAIN` selected `pdc_tune_approved_operation_source_idx` with estimated cost `0.27–2.52`. That is a query plan, not a measured end-to-end speed claim.

The category fixture separately distinguishes a legacy whole-stage booking from a current `BUS_WHOLE_JOB` reservation. Leaving a legacy Bus stage for Tint requires release confirmation and leaves the booking/line unchanged. A current explicit whole-job scope remains protected even if release confirmation is supplied.

## Reversal

Before any receipt-backed operation has been accepted, the **only supported complete inverse** is `supabase/proposals/new_addition_sublet_combined_20261026.down.sql`. Keep its entire `BEGIN` / `COMMIT` transaction intact. It runs the receipt component first, then the proposal component. Never run those component files separately. The proposal inverse also verifies that the original acceptance and station-resolver definitions have already been restored.

Both components first try to acquire the existing workshop-clock lock and then the existing top-level mutation lock, in automatic acceptance's normal order. They refuse immediately if either is busy. The locks remain held through the complete combined transaction. An in-flight acceptance therefore prevents the inverse; a newly arriving acceptance returns its normal busy result at its first lock gate. There is no unlocked interval between restoring the receipt resolver and restoring the proposal, and no blanket table lock is introduced.

Both inverses refuse once an approved added-operation review contains this exact automatic-policy decision. Removing the resolver or later-upload behavior after use could remap accepted work through the old AI rule. A used release therefore needs a separately reviewed forward-compatible reversal that preserves those saved decisions; do not bypass this refusal or delete receipts to force a rollback.

Post-use reversal refusal with unchanged function/pin/work state passed in the disposable copy. Phase 11 confirmed the final combined apply/inverse and existing-projection parity. Phase 12 used four actual two-connection checks, separately holding the clock and mutation locks during deployment and reversal: each attempt refused with its expected busy result in under two seconds, leaving exact function metadata, pins and work unchanged. All lock-holder sessions exited cleanly; the final database server was stopped and its temporary data, scratch and password files removed. Private run receipts and detailed logs remain outside Git.

The live release was verified by installed source, metadata and integrity-pin readback. An actual authenticated browser upload/save was not used as a live test fixture and remains outside this verification.
