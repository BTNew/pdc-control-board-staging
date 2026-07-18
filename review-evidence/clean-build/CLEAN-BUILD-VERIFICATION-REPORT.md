# Stage 2A Clean-Build Verification Evidence

Temporary Supabase project: `psnnswebuhnvjgghdpvt`
Temporary project name: `pdc-stage2a-clean-build-20260718`
Region: `ap-southeast-2`
Source branch: `fix/stage2a-independent-review-findings`
Production project `vjdtsswhroyguxyfjdkt` was never linked, queried, or changed.
Staging project `cdsmnqxtyyoeoznmbidd` remained manually paused throughout.

## Migration application

Command:

```text
npx supabase link --project-ref psnnswebuhnvjgghdpvt --password [REDACTED]
npx supabase migration list --linked
npx supabase db push --linked --password [REDACTED] --yes
npx supabase migration list --linked
npx supabase db push --dry-run --linked --password [REDACTED]
```

Result:
- Before push: local migrations 001-025, remote empty.
- All migrations 001 through 025 applied in exact filename order.
- No migration failed.
- After push: local and remote align exactly for 001-025.
- Dry run: `Remote database is up to date.`
- The CLI emitted a non-fatal post-push migration-catalog cache warning because Docker is not installed. It occurred after all migrations completed and the command exited 0; the subsequent migration list and dry-run independently confirm the ledger is complete.

Primary evidence:
- `migration-list-before-push.txt`
- `db-push-001-025.txt`
- `migration-list-after-push.txt`
- `db-push-dry-run-after.txt`
- `migration-checksums-001-025.txt`

## Clean schema and staging comparison

Generated a full clean-project schema catalog (`temp-clean-build-schema.json`) and compared it with the pre-pause staging catalog (`C:\tmp\prepause-backup\schema-only-snapshot.json`).

Exact matches:
- schemas
- all tables and columns (including nullability/defaults)
- named primary keys, foreign keys, unique constraints, and check constraints
- functional indexes
- triggers
- views
- 280 functions/RPCs, signatures, owners, return types, and Security Definer flags
- routine grants
- table grants
- 39 RLS policies and RLS-enabled flags
- 22-table Realtime publication membership
- replica identity settings
- migration ledger 001-025
- cron state (no pg_cron schema/jobs on either project)

The raw `information_schema.table_constraints` output includes PostgreSQL-generated internal NOT-NULL constraint names containing deployment-specific object OIDs. Those names differ by design between databases. The semantic comparison normalized only those internal OID-based names and compared their per-table counts; all named constraints and all column nullability metadata matched exactly.

Result: `UNEXPECTED_DIFFERENCE_COUNT=0`, `RESULT=PASS`.

Evidence: `schema-comparison-report.txt`.

## Behavioral/security verification

1. Existing Stage 2A reference-data staging suite against the temporary project:
   - **33 passed, 0 failed**
2. Dedicated clean-build migration-025 verification:
   - **25 passed, 0 failed**
   - anonymous Stage 2A RPC access denied
   - zero anon EXECUTE grants on Stage 2A RPCs
   - case-insensitive functional unique indexes present
   - case/space duplicate rejected
   - concurrent duplicate creation: exactly one winner
   - active technician assigned as bay default
   - deactivating default technician atomically clears bay default
   - inactive technician cannot be reassigned
   - viewer cannot expose inactive technician via include-inactive request
   - malformed time, non-positive increment/duration, malformed work week, and invalid start/end relation rejected
   - ledger exactly 001-025
   - Realtime publication has 22 expected tables
   - 5 Stage 2A Realtime tables use replica identity FULL
3. Database privilege hardening suite:
   - **4 passed, 0 failed**
4. pdc_user_roles direct-write lockdown suite:
   - **6 passed, 0 failed**
5. Role access matrix suite (with one synthetic temporary vehicle):
   - controller/viewer/disabled/administrator matrix all passed
   - **6 matrix cells passed, 0 failed**

Evidence files:
- `test_stage2a_workshop_reference_data_staging.txt`
- `_tmp_verify_stage2a_clean_build.txt`
- `clean-build-behavior-console.txt`
- `test_privilege_hardening_staging.txt`
- `test_pdc_user_roles_lockdown_staging.txt`
- `role-access-matrix-console.txt`

All test users, test rows, credentials, and the synthetic vehicle existed only in the temporary project.

## Temporary-project deletion

Command:

```text
npx supabase projects delete psnnswebuhnvjgghdpvt --yes
```

Result: `Deleted project: pdc-stage2a-clean-build-20260718`.

A subsequent `supabase projects list -o json` contains only:
- staging `cdsmnqxtyyoeoznmbidd` — status `INACTIVE` (still manually paused)
- production `vjdtsswhroyguxyfjdkt` — status `ACTIVE_HEALTHY`

The temporary ref `psnnswebuhnvjgghdpvt` is absent. The CLI automatically removed the deleted linked-project reference; `supabase/.temp/project-ref` no longer exists. No attempt was made to resume staging. Production was not linked, queried at the database level, or changed.

All temporary API keys, database passwords, and temporary-user ID files were deleted from the evidence directory after project deletion. They are not present in this evidence package.
