'use strict';
// r779 (F431): a queued booking left on a station the car has no work for (lines moved away) is cleared,
// because re-validating it refuses every move of the car's real stations (key 276 Fab, 31 Oct 2026).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261031010000_r779_no_work_station_bookings.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261031010000_r779_no_work_station_bookings.down.sql', 'utf8');

const fnBody = (src, name) => {
  const start = src.indexOf(`FUNCTION pdc_work_categories_private.${name}(`);
  assert.ok(start >= 0, name);
  const end = src.indexOf('$function$;', start);
  return src.slice(start, end);
};

test('staging only, outside import windows and imports, guarded on the live r830 sweep body', () => {
  assert.match(sql, /r779: staging only/);
  assert.match(sql, /r779: import window/);
  assert.match(sql, /r779: an import job is running/);
  assert.match(sql, /<> '8f937836105c82f6de70477701c69409'/);
  assert.match(sql, /sort_order = 565 OR fault_id = 'F431' OR added_in = 'r779'/);
});

test('only queued, bayless, never-started bookings on a station with no open requirement and no lines', () => {
  const pick = fnBody(sql, 'no_work_station_bookings_779');
  assert.match(pick, /wb\.status = 'queued' AND wb\.bay_id IS NULL/);
  assert.match(pick, /wb\.actual_start_at IS NULL AND wb\.actual_end_at IS NULL/);
  assert.doesNotMatch(pick, /'planned'|'started'|'stoppage'/);
  assert.match(pick, /wi\.required AND NOT wi\.completed/);
  assert.match(pick, /station_icon_completion_578\(/);
  assert.match(pick, /coalesce\(l\.total, 0\) > 0/);
  assert.match(pick, /pdc_qc_rework_scope_20260909/);
});

test('clearing is a soft delete with history and a restorable record, under the board change lock', () => {
  const clear = fnBody(sql, 'clear_no_work_station_bookings_779');
  assert.match(clear, /pdc:workshop:top-level-mutation/);
  assert.match(clear, /status = 'deleted'/);
  assert.match(clear, /deleted_at = pg_catalog\.clock_timestamp\(\)/);
  assert.match(clear, /r746_cleared_bookings/);
  assert.match(clear, /workshop_write_history\(b\.id, 'deleted'/);
  assert.doesNotMatch(clear, /DELETE FROM/);
});

test('the r830 sweep keeps the done-station step and adds the no-work step', () => {
  const sweep = fnBody(sql, 'sweep_done_station_bookings_830');
  assert.match(sweep, /clear_done_station_bookings_746\(v_ids, 'r830_sweep'\)/);
  assert.match(sweep, /clear_no_work_station_bookings_779\(v_none_ids, 'r779_sweep'\)/);
  assert.match(sweep, /request\.jwt\.claims/);
  assert.match(sweep, /workshop_bump_station_revision\(v_stage\)/);
});

test('helpers are closed to clients; check added and the release sweeps once', () => {
  for (const fn of ['no_work_station_bookings_779(uuid[])', 'clear_no_work_station_bookings_779(uuid[], text)', 'sweep_done_station_bookings_830()']) {
    assert.ok(sql.includes(`REVOKE ALL ON FUNCTION pdc_work_categories_private.${fn} FROM PUBLIC, anon, authenticated`), fn);
  }
  assert.match(sql, /'no_work_station_bookings_779', 'F431'/);
  assert.match(sql, /r779: check red after the sweep/);
});

test('rollback restores the r830 sweep exactly and drops the helpers', () => {
  assert.match(down, /<> '8f937836105c82f6de70477701c69409'/);
  assert.match(down, /DROP FUNCTION pdc_work_categories_private\.clear_no_work_station_bookings_779\(uuid\[\], text\)/);
  assert.match(down, /DROP FUNCTION pdc_work_categories_private\.no_work_station_bookings_779\(uuid\[\]\)/);
  assert.match(down, /check_name = 'no_work_station_bookings_779'/);
  assert.doesNotMatch(down, /no_work_station_bookings_779\(v_all\)/);
});
