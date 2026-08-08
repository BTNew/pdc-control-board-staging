const fs = require('fs');
const assert = require('assert');

const verifier = fs.readFileSync('scripts/verify_pdc_staging_backup_data_integrity.py', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/138_correct_reset_backup_evidence_scope.sql', 'utf8');
const installer = fs.readFileSync('scripts/apply_migration_138_staging.py', 'utf8');

assert(verifier.includes('if header != expected_csv_columns:'), 'CSV headers must exactly match all non-generated manifest columns');
assert(!verifier.includes('set(header).issubset'), 'subset CSV headers must not be accepted');
assert(verifier.includes('"full_schema_restore_verified": False'));
assert(verifier.includes('"schema_ddl_applied": False'));
assert(verifier.includes('"disaster_recovery_receipt": False'));
assert(verifier.includes('pdc-staging-backup-data-integrity-v2'));
assert(verifier.includes('data_integrity_receipt.json'));
assert(!verifier.includes('pdc-staging-backup-isolated-restore-v1'));

assert(migration.includes("project_ref='cdsmnqxtyyoeoznmbidd'"));
assert(migration.includes("version='137'"));
assert(migration.includes('pdc_staging_reset_evidence_corrections'));
assert(migration.includes('exact_csv_headers_verified'));
assert(migration.includes('full_schema_restore_verified boolean not null check(not full_schema_restore_verified)'));
assert(migration.includes('disaster_recovery_receipt boolean not null check(not disaster_recovery_receipt)'));
assert(migration.includes('enable row level security'));
assert(migration.includes('pdc_staging_reset_evidence_corrections_immutable'));
assert(migration.includes('immutable_reset_history_rewritten'));
assert(installer.includes('refusing Migration 138 apply from unreviewed or dirty worktree'));
assert(installer.includes('data-integrity receipt contract mismatch'));

console.log('Migration 138 backup-evidence scope static checks passed');
