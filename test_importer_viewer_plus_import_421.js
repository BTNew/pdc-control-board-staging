'use strict';
// r421 (F36): importer = viewer + Navision import. Importers no longer pass controller-level gates on the server
// (is_pdc_role('operator') and six direct role lists), except inside the existing email-monitor canonical action
// contracts; the frontend no longer offers "show on Vehicle Locations" to importers.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20261021003815_r421_importer_viewer_plus_import.sql');
const rollback = read('supabase/rollbacks/20261021003815_r421_importer_viewer_plus_import.down.sql');

function fnBody(sql, header) {
  const start = sql.indexOf(header);
  assert.notEqual(start, -1, header);
  const open = sql.indexOf('$function$', start);
  const close = sql.indexOf('$function$', open + 10);
  return sql.slice(open + 10, close);
}

test('is_pdc_role: importer passes the controller gate only inside a monitor canonical action', () => {
  const body = fnBody(migration, 'CREATE OR REPLACE FUNCTION public.is_pdc_role(');
  assert.match(body, /required_role='operator' and public\.current_pdc_user_role\(\) in \('operator','administrator'\) then true/);
  assert.match(body, /required_role='operator' and public\.current_pdc_user_role\(\)='importer' and public\.pdc_importer_monitor_action_421\(\) then true/);
  assert.doesNotMatch(body, /[(\[]\s*'operator'\s*,\s*'importer'/);
  assert.match(body, /required_role='importer' and public\.current_pdc_user_role\(\) in \('importer','administrator'\)/);
});

test('the six direct role lists no longer put importer next to controller', () => {
  for (const name of ['pdc_sublet_actor_allowed', 'save_pdc_online_state', 'save_pdc_online_state_batch',
    'activate_navision_backend_record', 'append_vehicle_timeline_event', 'get_vehicle_intelligence_snapshot']) {
    const body = fnBody(migration, `CREATE OR REPLACE FUNCTION public.${name}(`);
    assert.doesNotMatch(body, /[(\[]\s*'operator'\s*,\s*'importer'/, name);
    assert.match(body, /pdc_importer_monitor_action_421\(\)/, name);
  }
});

test('the monitor exception helper is private and the migration is guarded, pinned and checked', () => {
  assert.match(migration, /CREATE FUNCTION public\.pdc_importer_monitor_action_421\(\)/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.pdc_importer_monitor_action_421\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(migration, /NOT BETWEEN 2 AND 45/);
  assert.match(migration, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.match(migration, /'importer_viewer_plus_import','F36'/);
  assert.match(migration, /WHERE release='r421'\)<>8/);
  assert.doesNotMatch(migration, /workshop_clock_tick\(boolean,timestamptz\) *(RETURNS|AS)/i);
});

test('the rollback restores the original importer ladder and drops the helper', () => {
  const body = fnBody(rollback, 'CREATE OR REPLACE FUNCTION public.is_pdc_role(');
  assert.match(body, /required_role='operator' and public\.current_pdc_user_role\(\) in \('operator','importer','administrator'\) then true/);
  assert.match(rollback, /DROP FUNCTION public\.pdc_importer_monitor_action_421\(\);/);
  assert.match(rollback, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r421';/);
});

test('Navision import stays importer/administrator; show on Vehicle Locations is controller/administrator in the UI', () => {
  const app = read('app.js');
  const fn = app.slice(app.indexOf('function navisionBoardActivationRoleAllowed('), app.indexOf('function navisionBoardActivationIdempotencyKey('));
  assert.match(fn, /\['operator', 'administrator'\]\.includes/);
  assert.doesNotMatch(fn, /'importer'/);
  assert.match(app, /return \['importer', 'administrator'\]\.includes\(resolvedRole\);/);
  assert.match(read('index.html'), /&amp;r421=2026\.10\.21\.01/);
});

test('no personal emails in the r421 SQL', () => {
  for (const sql of [migration, rollback]) assert.doesNotMatch(sql, /@(pmgwa|broometoyota|toyotawa)\./i);
});
