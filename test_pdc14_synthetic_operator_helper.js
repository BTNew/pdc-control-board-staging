'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationName = '20260903200000_pdc14_synthetic_operator_verification_helper.sql';
const migrationPath = path.join('supabase', 'staging_only', migrationName);

assert.ok(fs.existsSync(migrationPath), 'the append-only synthetic Operator verification helper migration exists');
const sql = fs.readFileSync(migrationPath, 'utf8');

assert.match(sql, /cdsmnqxtyyoeoznmbidd/, 'migration is pinned to the approved STAGING project');
assert.match(sql, /pdc_staging_environment_sentinel/, 'migration requires the STAGING sentinel');
assert.match(sql, /pdc_production_environment_sentinel/, 'migration rejects a Production sentinel');
assert.match(sql, /functional\.pdc\.staging@example\.com/g, 'helper is pinned to the one approved synthetic identity');
assert.doesNotMatch(sql, /CREATE(?: OR REPLACE)? FUNCTION public\.apply_pdc14_staging_test_operator_role\s*\([^)]*[a-z_]+\s+(?:text|varchar)/i, 'assignment helper accepts no arbitrary email parameter');
assert.match(sql, /CREATE FUNCTION public\.apply_pdc14_staging_test_operator_role\(\)/, 'dedicated no-argument assignment helper exists');
assert.match(sql, /CREATE FUNCTION public\.rollback_pdc14_staging_test_operator_role\(text\)/, 'dedicated bounded rollback helper exists');
assert.match(sql, /SECURITY DEFINER SET search_path=''/g, 'helpers use hardened SECURITY DEFINER search paths');
assert.match(sql, /role='operator'/, 'assignment grants only Operator');
assert.doesNotMatch(sql, /role='administrator'/, 'assignment never grants Administrator');
assert.match(sql, /JOIN auth\.users auth_user ON auth_user\.id=role_row\.auth_user_id/g, 'helpers bind the role row to the matching Auth user');
assert.match(sql, /lower\(auth_user\.email\)='functional\.pdc\.staging@example\.com'/g, 'helpers verify the Auth email independently');
assert.match(sql, /PDC_14_SYNTHETIC_IDENTITY_AMBIGUOUS/g, 'helpers fail closed on duplicate target identities');
assert.match(sql, /PDC_14_SYNTHETIC_WRONG_ENVIRONMENT/g, 'privileged helpers revalidate STAGING at invocation time');
assert.match(sql, /pdc14_staging_test_operator_already_assigned/, 'assignment is replay-idempotent');
assert.match(sql, /reverted_assignment_event_id/, 'rollback is bound to one immutable assignment receipt');
for (const field of ['approved_at', 'rejected_at', 'rejection_reason', 'disabled_at', 'disabled_reason', 'restored_at']) {
  assert.match(sql, new RegExp(`v_before\\.${field} IS DISTINCT FROM v_receipt\\.after_${field}`), `rollback rejects drift in ${field}`);
}
for (const signature of [
  'public.apply_pdc14_staging_test_operator_role()',
  'public.rollback_pdc14_staging_test_operator_role(text)',
]) {
  assert.match(
    sql,
    new RegExp(`REVOKE ALL ON FUNCTION ${signature.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} FROM public,anon,authenticated,service_role`),
    `${signature} remains owner-only`,
  );
}
assert.match(sql, /20260903190000/, 'migration is strictly chained to the merged PDC-14 head');
assert.match(sql, /INSERT INTO supabase_migrations\.schema_migrations/, 'migration records its applied identity');

console.log('PDC-14 synthetic Operator helper contract: PASS');
