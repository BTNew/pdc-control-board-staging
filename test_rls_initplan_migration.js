const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const forwardPath = 'supabase/migrations/20261019140000_rls_auth_initplan_and_overlapping_policies.sql';
const downPath = 'supabase/rollbacks/20261019140000_rls_auth_initplan_and_overlapping_policies.down.sql';

test('RLS migration wraps auth.uid and combines overlapping policies without widening access', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.match(forward, /reviewed_policy_changed/);
  assert.equal((forward.match(/\(SELECT auth\.uid\(\)\)/g) || []).length, 3);
  assert.match(forward, /public\.workshop_is_planner_operator\(\)\s+OR /);
  assert.match(forward, /karratha135_pdc\.workshop_is_planner_operator\(\)\s+OR /);
  assert.doesNotMatch(forward, /DROP POLICY k135_verified_department_scope/);
  assert.doesNotMatch(forward, /vjdtsswhroyguxyfjdkt/);
  assert.match(forward, /'viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text/);
  assert.doesNotMatch(forward, /CREATE POLICY[^;]*TO public/i);

  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_production_environment_sentinel/);
  assert.match(down, /CREATE POLICY navision_backend_revision_planner_operator_select ON public\.navision_backend_revision/);
  assert.match(down, /CREATE POLICY navision_backend_revision_planner_operator_select ON karratha135_pdc\.navision_backend_revision/);
  assert.match(down, /auth\.uid\(\) IS NOT NULL/);
  assert.doesNotMatch(down, /\(SELECT auth\.uid\(\)\)/);
  assert.equal(
    fs.existsSync(path.join('supabase/migrations', path.basename(downPath))),
    false
  );
});
