# PDC Control Board — Backup and Disaster Recovery

Status: staging-verified. Not yet exercised against production.

## Two layers (independent-review remediation, finding #8)

The independent review correctly identified that the custom backup
script (`scripts/pdc_backup.py`) is an **operational-data export**, not
a full Supabase project disaster-recovery mechanism. It intentionally
does not capture `auth.*` users/sessions, the database schema as a
restorable dump, functions/RPCs, RLS policies/grants, Auth
URL/email-template settings, project configuration, or storage
objects. Treating it as a complete disaster-recovery solution would be
a real gap. This project now uses two deliberately separate layers:

### Layer 1 — Native Supabase/PostgreSQL backup (full project recovery)

Supabase's own project-level backup/point-in-time-recovery (PITR)
feature is the authoritative full-project recovery path. It covers
everything the custom script does not:

- Complete schema (every table, including `auth.*`, `storage.*`)
- All functions/RPCs, exactly as deployed, with their `SECURITY
  DEFINER`/`INVOKER` mode and search_path settings intact
- RLS policies and every grant, exactly as they exist at backup time
- Realtime publication membership
- Auth configuration (site URL, redirect allow-list, password policy)
- `auth.users` and every session
- Storage buckets, objects, and storage policies

**Action required before this layer is truly "enabled" for this
project**: confirm the Supabase project's backup/PITR retention window
via the Supabase dashboard (Project Settings → Database → Backups) for
both the staging and (later, separately-approved) production projects,
and document the retention window and the exact recovery procedure
(restore from dashboard, or via the Supabase Management API) once
confirmed. This has NOT yet been confirmed or exercised in this
remediation phase — it is a real, outstanding item, not something this
document can complete unilaterally, because it requires access to the
Supabase organisation's billing/plan tier (backup retention length
varies by plan) and a decision about acceptable RPO/RTO, which are
business decisions outside the scope of a code remediation.

### Layer 2 — Encrypted operational-data export (secondary, human-auditable)

`scripts/pdc_backup.py` remains a real, working, staging-verified
secondary backup:

- Runs on a schedule (`scripts/pdc_backup_scheduled_tick.py`, driven by
  a Hermes cron job) and on demand (`scripts/pdc_backup_run.py`).
- Exports every table in `TABLES` (the explicit list in
  `pdc_backup.py`) as Fernet-encrypted JSON, with row counts, a backup
  run ID, the environment, and the current migration version recorded
  in the manifest.
- Independently useful for: human-auditable row-level history,
  fast targeted recovery of operational data without touching schema
  or Auth, and a second, independently-encrypted copy in case the
  native Supabase backup layer is ever unavailable.
- Verified via `scripts/pdc_restore.py`, which loads a backup into a
  brand-new, isolated Postgres schema (never touches `public`) and
  runs a verification pass -- see "Restore verification" below for
  what changed in this remediation phase.

Both layers should be tested and documented; neither replaces the
other.

## Restore verification (independent-review remediation, finding #9)

**Before this remediation**: `pdc_restore.py` used a short, 27-entry
hand-written list of foreign keys (`FOREIGN_KEYS`), added each
constraint `NOT VALID`, and never ran `VALIDATE CONSTRAINT` on any of
them. A constraint that could not be added (`skipped`) was recorded in
the report but did **not** fail `all_checks_passed` -- meaning "full
restore passed" could be printed even when a real relationship failed
to restore.

**After this remediation**:

- `discover_foreign_keys()` queries the live `public` schema's real
  catalog (`information_schema.table_constraints` /
  `key_column_usage` / `constraint_column_usage`) instead of using a
  hand-written list. Verified live against staging: this finds **68
  real foreign keys**, more than double the old list's 27 entries --
  proving the old list was stale and incomplete, not merely
  differently organised.
- Every discovered constraint is filtered to only those where both the
  referencing and referenced table are part of the backup payload
  (`TABLES`); backup-tooling metadata tables (e.g.
  `restore_test_runs`, which records restore-test results themselves
  and is intentionally never part of the operational-data backup) are
  correctly excluded rather than counted as a failure.
- `add_foreign_keys()` now runs `ALTER TABLE ... VALIDATE CONSTRAINT`
  immediately after `ADD CONSTRAINT ... NOT VALID`, so every added
  constraint is actually checked against the restored data before the
  restore reports success.
- `restore_backup()`'s `all_checks_passed` now explicitly requires
  `foreign_keys_skipped` to be empty -- a single skipped/invalid
  constraint fails the whole restore, exactly as the review required.

**Verified live this remediation phase**: a real backup of the current
staging database, followed by a real restore into a fresh isolated
schema, reported:

```
"foreign_keys_discovered": 68,
"foreign_keys_added": 68,
"foreign_keys_skipped": [],
"all_checks_passed": true
```

## Recovery procedure (staging)

1. Locate the desired backup file (Fernet-encrypted `.bin`) and its
   manifest.
2. Set `PDC_BACKUP_ENCRYPTION_KEY` in the environment (never commit
   this value; it lives only in the environment where the backup/
   restore scripts run).
3. Run `python scripts/pdc_restore.py --backup-file <path> [--schema-name <name>] [--drop-after]`.
4. Inspect the JSON report: confirm `all_checks_passed: true`, zero
   `row_count_mismatches`, zero `foreign_keys_skipped`, and every named
   check (`vehicle_notes_attached_correctly`,
   `bookings_bay_and_time_match_source`,
   `technician_assignments_restored`, `audit_history_preserved`,
   `notifications_restored_disabled`) is `true`.
5. The restore always lands in a brand-new, isolated schema -- it never
   writes to `public`. Promoting a verified restore into `public` (a
   real recovery, not just a verification) is a separate, explicitly
   approved procedure not automated by this script, and must never be
   attempted against production without separate approval.

## Known limitations (honest, not glossed over)

- Layer 1 (native Supabase backup/PITR) has not yet been confirmed
  enabled or exercised for either the staging or production project in
  this remediation phase -- this requires Supabase dashboard/plan-tier
  access this working environment does not have.
- The encrypted operational export (Layer 2) does not capture
  `auth.users`, RLS policies, grants, or Auth configuration -- by
  design; that is Layer 1's job. A restore of Layer 2 alone recreates
  operational tables and their foreign-key relationships, not a
  complete project.
- Cron scheduling for the operational export currently relies on a
  Hermes-managed cron job (see the scheduler documentation for the
  exact schedule); it does not use Postgres `pg_cron` (confirmed not
  installed on the staging project during the database schema
  snapshot in this remediation's review package).
