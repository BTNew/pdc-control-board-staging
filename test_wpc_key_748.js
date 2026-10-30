'use strict';
// r748 (F354, F355). F354: a one-minute sweep clears planned / queued bookings on stations whose lines are all ticked.
// F355 (Craig 30 Oct): WPC frees the key number; a car into QC becomes WPC; the WPC age runs until Autocare collects
// it and the PMB days before it are kept.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sql = fs.readFileSync('supabase/migrations/20261030110000_r748_wpc_key_and_done_station_sweep.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030110000_r748_wpc_key_and_done_station_sweep.down.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const sales = fs.readFileSync('sales/sales.js', 'utf8');

test('staging only, outside import windows, guarded on the exact old bodies', () => {
  assert.match(sql, /r748: staging only/);
  assert.match(sql, /r748: import window/);
  for (const md5 of ['bdf35576db35ecec8a16b40d05d8896d', 'd104288a99dde96994084b7fc291efb7', '4c2334ec15cdce2044925ffd08ddc61e']) {
    assert.ok(sql.includes(md5), md5);
    assert.ok(down.includes(md5), md5);
  }
});

test('F354 sweep: renamed from the live r776 job, system actor, only queued / planned via the r746 clear', () => {
  assert.match(sql, /cron\.unschedule\('staging-done-station-planner-sweep-776'\)/);
  assert.match(sql, /'staging-done-station-planner-sweep-748', '\* \* \* \* \*'/);
  assert.match(sql, /clear_done_station_bookings_746\(v_ids, 'r748_sweep'\)/);
  assert.match(sql, /request\.jwt\.claims/);
  assert.match(sql, /status IN \('queued','planned'\)/);
  assert.match(sql, /REVOKE ALL ON FUNCTION pdc_work_categories_private\.sweep_done_station_bookings_748\(\) FROM PUBLIC, anon, authenticated/);
});

test('F355: WPC is never a key token, so it never clashes and the number is free', () => {
  assert.match(sql, /OR t = 'WPC' THEN NULL/);
  assert.match(sql, /DELETE FROM pdc_key_number_private\.active_key_575 WHERE token = 'WPC'/);
});

test('F355: into QC with a real key becomes WPC, before the r575 guard runs', () => {
  assert.match(sql, /CREATE TRIGGER zzy_pdc_qc_key_wpc_748 BEFORE INSERT OR UPDATE OF current_location, location_override/);
  assert.ok('zzy_pdc_qc_key_wpc_748' < 'zzz_pdc_active_key_575');
  assert.match(sql, /v_new_eff = 'QC' AND v_old_eff <> 'QC'/);
  assert.match(sql, /NEW\.key_number := 'WPC'/);
});

test('F355: WPC start recorded without a column list; PMB key date kept; typed WPC never resets the PMB age', () => {
  assert.match(sql, /AFTER UPDATE ON public\.vehicles\s+FOR EACH ROW WHEN \(OLD\.key_number IS DISTINCT FROM NEW\.key_number\)/);
  assert.match(sql, /pmb_key_at/);
  assert.match(sql, /upper\(btrim\(e\.metadata->'changed_fields'->>'key_number'\)\) <> 'WPC'/);
  assert.match(sql, /upper\(btrim\(v\.key_number\)\) <> 'WPC'\)/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.list_wpc_timers_748\(\) TO authenticated/);
  assert.match(sql, /'wpc_key_748', 'F355'/);
  assert.match(sql, /'done_station_sweep_748', 'F354'/);
});

test('board: WPC is not a PMB key, not New to PMB, not a duplicate, and shows its WPC age', () => {
  const ctx = { Date };
  vm.createContext(ctx);
  for (const name of ['parseIsoTimestamp', 'vehicleKeyIsWpc', 'wpcTimerRow', 'ensureWpcTimers', 'wholeDaysBetween', 'wpcAgeInfo',
    'pmbKeyAssignedRow', 'pmbVehicleHasKey']) {
    const start = app.indexOf(`function ${name}(`);
    assert.ok(start >= 0, name);
    vm.runInContext(app.slice(start, app.indexOf('\nfunction ', start + 1)), ctx);
  }
  vm.runInContext(`var app = { wpcTimers: new Map([['v1', { vehicle_id: 'v1', wpc_at: '2026-10-28T02:00:00Z', freed_key: '269',
    pmb_key_at: '2026-10-19T01:00:00Z', collected_at: '2026-10-30T02:00:00Z' }]]) };`, ctx);
  assert.equal(ctx.pmbVehicleHasKey({ keyNumber: 'wpc' }), false);
  assert.equal(ctx.pmbVehicleHasKey({ keyNumber: '269' }), true);
  const info = ctx.wpcAgeInfo({ id: 'v1', key_number: 'WPC' });
  assert.equal(info.label, 'WPC 2 days');
  assert.equal(info.pmbDays, 9);
  assert.match(info.title, /until Autocare collected it/);
  assert.match(info.title, /key 269 freed/);
  assert.equal(ctx.wpcAgeInfo({ id: 'v1', key_number: '269' }), null);
  assert.match(app, /if \(vehicleKeyIsWpc\(vehicle\)\) return false;\n  const raw = pmbKeyAssignedTimestamp\(vehicle\);/);
  assert.match(app, /token === 'WPC'\) return null;/);
  assert.match(app, /const wpc = atPmb \? wpcAgeInfo\(vehicle\) : null;/);
  assert.match(app, /client\.rpc\('list_wpc_timers_748'\)/);
});

test('sales: WPC stays At PMB and shows the WPC age', () => {
  assert.match(sales, /rpc\('list_wpc_timers_748'\)/);
  assert.match(sales, /toUpperCase\(\)==='WPC'\)return wpcAgeHtml\(row\)/);
  assert.match(fs.readFileSync('sales/index.html', 'utf8'), /sales\.js\?v=[^"]*&amp;r748=2026\.10\.30\.r748/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /app\.js\?[^"]*r748=2026\.10\.30\.r748/);
});
