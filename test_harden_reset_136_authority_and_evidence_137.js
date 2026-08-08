const fs = require('fs');
const assert = require('assert');

const sql = fs.readFileSync('supabase/staging_only/137_harden_reset_136_authority_and_evidence.sql', 'utf8');
const installer137 = fs.readFileSync('scripts/apply_migration_137_staging.py', 'utf8');
const installer136 = fs.readFileSync('scripts/apply_migration_136_staging.py', 'utf8');
const dataIntegrity = fs.readFileSync('scripts/verify_pdc_staging_backup_data_integrity.py', 'utf8');
const correction138 = fs.readFileSync('supabase/staging_only/138_correct_reset_backup_evidence_scope.sql', 'utf8');
const qa = fs.readFileSync('scripts/qa_reset_136_staging.py', 'utf8');

assert.match(sql, /pdc_staging_environment_sentinel[\s\S]*cdsmnqxtyyoeoznmbidd/);
assert.match(sql, /pdc_production_environment_sentinel/);
assert.match(sql, /pdc_vehicle_has_current_navision_dealer_delivery/);
assert.match(sql, /navision_backend_records[\s\S]*source_system='microsoft_navision'[\s\S]*is_current[\s\S]*record_status='current'/);
assert.match(sql, /count\(\*\)=1[\s\S]*bool_and\(public\.navision_operational_location/);
const qcBody = sql.match(/create or replace function public\.pdc_enforce_qc_then_rft\(\)[\s\S]*?\$function\$;/)?.[0] || '';
assert.ok(qcBody.includes('pdc_vehicle_has_current_navision_dealer_delivery'));
assert.ok(!qcBody.includes('reset_location_authority'));
assert.match(sql, /source_payload=coalesce\(source_payload,'\{\}'::jsonb\)-'reset_location_authority'/);
assert.match(sql, /c6450f3b6a43aa05f3ef80441d8f2ece265b05a9c424eb4a834fb60a8e423c88/);
assert.match(sql, /actual_backup_manifest_sha256/);
assert.match(sql, /b624e1942c621ffed0fa8bbb610a8fa704f0d691a69a0917c666c8930b6d930a/);
assert.match(sql, /7f7d027f1a0da08982241b9d6f7a553b09908fed93c56f1e934e60a4cee1b439/);
assert.match(sql, /database_owner_migration_runner/);
assert.match(sql, /corrects_actor_attribution',true/);
assert.match(sql, /immutable_reset_history_rewritten',false/);
assert.match(sql, /enable row level security/);
assert.match(sql, /revoke all on table public\.pdc_staging_reset_attestations from public,anon,authenticated,service_role/);

for (const source of [installer137, installer136]) {
  assert.match(source, /validate_backup/);
  assert.match(source, /isolated_restore_receipt/);
  assert.match(source, /foreign_key_violations/);
  assert.match(source, /cleanup_verified/);
}
assert.match(dataIntegrity, /sha256_file\(manifest_path\)/);
assert.match(dataIntegrity, /restored_row_count/);
assert.match(dataIntegrity, /foreign_keys_checked/);
assert.match(dataIntegrity, /foreign_key_violations/);
assert.match(dataIntegrity, /drop schema/);
assert.match(dataIntegrity, /conn\.rollback\(\)/);
assert.match(dataIntegrity, /if header != expected_csv_columns/);
assert.ok(!dataIntegrity.includes('set(header).issubset'));
assert.match(dataIntegrity, /"full_schema_restore_verified": False/);
assert.match(dataIntegrity, /"disaster_recovery_receipt": False/);
assert.match(correction138, /pdc_staging_reset_evidence_corrections/);
assert.match(correction138, /full_schema_restore_verified boolean not null check\(not full_schema_restore_verified\)/);

const preAuthCheck = qa.indexOf('configured_ref = page.evaluate');
const credentialEntry = qa.indexOf('page.fill("#pdc-login-email"');
assert.ok(preAuthCheck >= 0 && credentialEntry > preAuthCheck, 'staging project must be verified before credentials');
assert.match(qa, /parsed_url\.hostname != "btnew\.github\.io"/);
assert.match(qa, /if configured_ref != STAGING_REF or production/);
assert.match(qa, /vehicleLocationBoardRows\(\)\.length === 325/);
assert.match(qa, /openVehicleModal\(key\) === true/);
assert.match(fs.readFileSync('app.js', 'utf8'), /description: existing\.authenticatedEmailOperation === true \? existing\.description : line\.description/);
assert.match(fs.readFileSync('app.js', 'utf8'), /job_card_number: existing\.job_card_number \|\| line\.job_card_number/);

console.log('Migration 137 reset hardening contract passed.');
