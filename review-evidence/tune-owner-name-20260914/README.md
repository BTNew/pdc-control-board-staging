# Tune Owner Name correction — staging deployed

Stock **13073094**, job card **J139125725**, has 18 imported operations totalling 18.75 effective hours. Its report rows contain `Owner Name = HERTZ AUSTRALIA PTY LTD **`, but the live `pdc_tune_source_fields_v5` customer alias list omits `Owner Name`. Consequently both retained normalized fields and Tune detail evidence have a null customer. No matching Navision record supplies the missing details. This report contains no model/vehicle description or VIN; the proposed correction does not infer either field or a salesperson.

## Prepared changes

`supabase/migrations/20260914054015_tune_owner_name_alias.sql` appends `owner name` after existing customer aliases. The existing text helper already handles spaces, underscores and case. This fixes normalization for new report previews while retaining established customer precedence, parts/VIN/model mappings, function permissions and security mode. Previously stored previews/evidence remain immutable.

`restore_stock13073094_customer.sql` derives the customer from all 18 retained rows. It resolves generated identifiers through exact active Stock/Job Card, the current evidence pointer, original apply receipt and corresponding preview. It checks the original source and workbook hashes, Stock/R/O columns, owner consistency and absence of current Navision authority. It appends one receipt to the original import batch with `receipt_kind = replay` and explicit `repair_scope = canonical_customer_only` / `operations_replayed = false`. The canonical update changes only customer, one receipt pointer in source payload, version and update attribution/time. Management execution is attributed to its actual database role and `auth.uid()`; it does not impersonate the original importer.

The existing `pdc_tune_vehicle_details_v5` projection falls back from null immutable evidence customer to the canonical vehicle customer, so no projection change or replacement evidence is required. Repeating the targeted repair makes no further changes. If a later import, nonblank customer or Navision authority changes the verified source state, the repair stops for re-evaluation.

## Verification

`test_rollback.sql` ran against staging `cdsmnqxtyyoeoznmbidd` inside one transaction ending in ROLLBACK. It passed nine alias cases, all 18 real retained rows and checks that unrelated normalized fields, function permissions, all other vehicle fields, ten operational tables, raw import rows, immutable Tune evidence and the current evidence pointer remain unchanged. It also checked repair replay and all deferred constraints. Projected customer became `HERTZ AUSTRALIA PTY LTD **`; operations remained 18 / 18.75h, bookings zero, location Yard Hold, VIN and vehicle description null.

`rollback-verification.json` records the pre-deployment test result and independent readback: customer remained null and vehicle version remained 23 after rollback. The reviewed alias migration was subsequently applied on staging, followed by the targeted repair in its own atomic transaction. Final committed readback showed the recovered customer, version 24, 18 operations, 18.75 hours, zero bookings and Yard Hold. Repeating the final guarded repair returned the existing receipt without another version change. Model and VIN remain null because neither source supplies them.

The migration was generated with the workspace CLI at `C:/Users/craig/Documents/Codex/2026-09-11/craig-requested-this-task-as-part-2/work/supabase.exe`, version 2.81.0, after checking `migration new --help`, using the isolated `work/tune-owner-repair` directory. No new RPC/table/privilege exposure is introduced. Supabase function/migration documentation and relevant locking guidance were reviewed. The changelog Markdown endpoint could not be retrieved in this environment.

The CLI generated local version 20260914053312; the migration file was renamed to the actual Supabase migration-ledger version 20260914054015 after successful apply. The repair file deliberately leaves transaction control to its caller.
