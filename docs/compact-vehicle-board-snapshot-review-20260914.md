# Compact vehicle board snapshot review

The additive `get_pdc_email_vehicle_board_snapshot()` wrapper is approved for the reviewed scope. It calls the original endpoint as `SECURITY INVOKER`, preserves successful response envelopes and row order, returns unsuccessful/non-array envelopes unchanged, and removes only each vehicle's `pilbara_service_operations` and object-valued `parts_flags.operations` members. Missing, null and non-object parts values survive unchanged. The original endpoint definition and grants are not changed by the migration, recorded by staging as `20260914053929_compact_vehicle_board_snapshot.sql`.

Consumer review found that `pdc-email-vehicle-location-service.js` derives `pilbaraServiceOperations` from retained canonical `operation_lines`. Parts consumers in `app.js` and `pdc-parts-confirmation.js` read summary, confirmation, job and import timestamp fields. None reads the removed operation map. The separate `pdc-email-ai-v2-actions.js` caller can continue using the original endpoint for compatibility.

An independent read-only staging transaction on 14 September 2026 measured 102 vehicles: 6,686,546 bytes originally and 4,017,512 bytes after compaction, saving 2,669,034 bytes (39.92%). Every retained row value, vehicle order and response envelope matched. Original snapshot generation took 1,678.564 ms and transforming that already-generated JSON took 80.593 ms. These are single database-side samples; the change reduces transfer and parsing work while retaining the original generation cost.

Existing numeric parts flags, separate parts feed (eight cases), parts email confirmation and Pilbara operation projection tests passed. The local runtime source and exact proposed migration were reviewed; no remote schema changes were made by this review.

After the deployment owner installed the compact wrapper and the authorization repair below, both complete read-only SQL suites passed. The then-current 103-vehicle snapshot measured 6,751,759 bytes originally and 4,060,567 bytes compacted, saving 2,691,192 bytes (39.86%). There were zero retained-field differences; all envelope, order, permission and 11 exact-body shape cases passed. Sequential original/compact database samples were 1,669.492/1,566.814 ms; these are verification samples rather than an isolated performance benchmark.

## Reusable verification

Run `tests/sql/compact_vehicle_board_snapshot_rollback_20260914.sql` as one complete SQL request after the compact wrapper and NULL-role repair are installed. It runs in a read-only, repeatable-read transaction and ends in rollback. It requires the staging sentinel, the existing approved Craig account and both endpoints. It creates no helper functions, tables or business fixtures.

The test checks the invoker/stable/JSONB declaration and explicit execution grants; anonymous denial; missing-claims behavior against the original endpoint; the actual `data.vehicles`/`data.revision` envelope; complete retained-field, count and positional parity; payload reduction; and 11 explicit edge-case envelopes. The edge cases execute the exact deployed function body in an anonymous block, replacing only the upstream read and return statements with transaction-local fixture input/output. The seams deliberately fail if that reviewed source structure changes. Results contain counts and timings rather than vehicle data or claims.

A separate read-only original/original comparison confirmed that the current live envelope is exactly `ok`, `code`, `data`, with `revision` and `vehicles` inside `data`, and is stable across repeated calls in one repeatable-read transaction.

## Authorization defect found and repaired

The original base function `get_pdc_email_vehicle_location_snapshot_pre168()` checked `IF v_role NOT IN (...)` without handling a null role. `current_pdc_user_role()` returns null for empty claims, and SQL's null comparison caused that guard to fall through. Read-only verification reproduced successful snapshots under the `authenticated` role with `auth.uid()` and `auth.role()` null before repair. This behavior predated the compact wrapper.

The deployment owner applied the narrowly scoped `20260914054444_vehicle_snapshot_null_role_guard.sql` repair. It changes the one guard to `IF v_role IS NULL OR v_role NOT IN (...)`. Its exact predecessor definition hash is checked before replacement, and the function definition and execution grants are checked afterward. The role helper, four allowed roles, data query and grants are retained.

`tests/sql/vehicle_snapshot_null_role_guard_rollback_20260914.sql` passed all nine read-only checks: missing claims and an identity without a registered application role receive identical `unauthorized` responses from the original and compact endpoints; a null or unapproved role value is denied; viewer, operator, importer and administrator guard branches remain allowed; and the existing approved account retains access to the current snapshot. The compact integration suite independently verifies missing-claims denial and the anonymous execution restriction. Neither suite creates accounts or writes operational records.
