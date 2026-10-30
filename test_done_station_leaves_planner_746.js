'use strict';
// r746 (F352): a station whose lines are all ticked (or overridden) leaves Unallocated and its queued / planned bookings.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261030020000_r746_done_station_leaves_planner.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030020000_r746_done_station_leaves_planner.down.sql', 'utf8');

test('staging only, outside import windows, guarded on the exact eligibility body', () => {
  assert.match(sql, /r746: staging only/);
  assert.match(sql, /import window/);
  assert.match(sql, /<> '952da1c6a242d3014d1deae7a0585bac'/);
  assert.match(sql, /sort_order = 466 OR fault_id = 'F352'/);
});

test('done means the r578 station icon says complete; QC rework keeps the station open', () => {
  assert.match(sql, /station_icon_completion_578\(/);
  assert.match(sql, /WHERE r\.complete/);
  assert.match(sql, /pdc_qc_rework_scope_20260909/);
});

test('eligibility leaves out done stations and only asks the icon about rows with no open hours or an override', () => {
  assert.match(sql, /WHERE NOT EXISTS\(SELECT 1 FROM done d WHERE d\.vehicle_id=e\.id\)/);
  assert.match(sql, /e\.approved_hours IS NULL/);
  assert.match(sql, /eligibility tail not found exactly once/);
  assert.match(sql, /eligibility readback differs/);
});

test('only queued / planned bookings are removed; started and stopped jobs stay', () => {
  const clear = sql.slice(sql.indexOf('clear_done_station_bookings_746(p_vehicle_ids'), sql.indexOf('after_station_tick_746()'));
  assert.match(clear, /status IN \('queued', 'planned'\)/);
  assert.doesNotMatch(clear, /'started'|'stoppage'/);
  assert.match(clear, /status = 'deleted'/);
  assert.match(clear, /workshop_write_history\(b\.id, 'deleted'/);
  assert.match(clear, /r746_cleared_bookings/);
  assert.match(clear, /pdc:workshop:top-level-mutation/);
});

test('ticks and overrides trigger the cleanup, which can never fail the tick, and refresh the planners', () => {
  for (const table of ['pdc_panel_line_completion_565', 'pdc_station_completion_override_578']) {
    assert.match(sql, new RegExp(`AFTER INSERT ON public\\.${table}\\s+REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT`));
    assert.match(sql, new RegExp(`AFTER UPDATE ON public\\.${table}\\s+REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT`));
  }
  assert.match(sql, /EXCEPTION WHEN OTHERS THEN\s+RAISE WARNING 'r746: planner cleanup skipped/);
  assert.match(sql, /workshop_bump_station_revision\(v_stage\)/);
});

test('one sweep, recorded with an actor, then the check must be green', () => {
  assert.match(sql, /'r746_sweep'/);
  assert.match(sql, /request\.jwt\.claims/);
  assert.match(sql, /done_station_leaves_planner_746/);
  assert.match(sql, /r746: check red/);
});

test('helpers are closed to clients', () => {
  for (const fn of ['done_planner_stations_746(uuid[])', 'clear_done_station_bookings_746(uuid[], text)', 'after_station_tick_746()']) {
    assert.ok(sql.includes(`REVOKE ALL ON FUNCTION pdc_work_categories_private.${fn} FROM PUBLIC, anon, authenticated`), fn);
  }
});

test('rollback restores the saved eligibility body by md5 and drops triggers, helpers and the check', () => {
  assert.match(down, /r746_function_backup/);
  assert.match(down, /952da1c6a242d3014d1deae7a0585bac/);
  assert.equal((down.match(/DROP TRIGGER IF EXISTS zz_station_done_746_/g) || []).length, 4);
  assert.match(down, /DROP FUNCTION IF EXISTS pdc_work_categories_private\.done_planner_stations_746/);
  assert.match(down, /done_station_leaves_planner_746/);
  assert.ok(down.indexOf('EXECUTE v_def') < down.indexOf('DROP FUNCTION'), 'eligibility is restored before its helper is dropped');
});

test('r746b: an override alone is not done; removed override bookings are put back', () => {
  const fix = fs.readFileSync('supabase/migrations/20261030023000_r746b_override_alone_keeps_booking.sql', 'utf8');
  assert.match(fix, /WHERE coalesce\(r\.total, 0\) > 0 AND r\.done = r\.total/);
  assert.doesNotMatch(fix, /WHERE r\.complete/);
  assert.match(fix, /WHERE override_only AND restored_at IS NULL/);
  assert.match(fix, /'same bay and time'/);
  assert.match(fix, /'restore', v_craig/);
});
