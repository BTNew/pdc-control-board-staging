'use strict';
// r892 (F442): owner page counts vehicles (not operation lines) and shows days of work per station (Craig 31 Oct 2026).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const MIGRATION = 'supabase/migrations/20261031140000_r892_owner_vehicles_days.sql';
const ROLLBACK = 'supabase/rollbacks/20261031140000_r892_owner_vehicles_days.down.sql';

test('database: vehicles, not bookings; days = hours not started / (bays x workshop day)', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  assert.match(sql, /'vehicles_booked', \(SELECT count\(\*\) FROM act\)/);
  assert.match(sql, /'vehicles_not_booked'/);
  assert.doesNotMatch(sql, /'booked_jobs'/);
  assert.match(sql, /count\(DISTINCT wb\.vehicle_id\)/);
  assert.match(sql, /key = 'day_end_time'[\s\S]*key = 'day_start_time'/);
  assert.match(sql, /sum\(mins_not_started\) \/ 60\.0 \/ \(count\(\*\) \* \(SELECT day_hours FROM cfg\)\)/);
  assert.match(sql, /IF NOT public\.is_pdc_owner_viewer_891\(\) THEN/);
  const down = fs.readFileSync(ROLLBACK, 'utf8');
  assert.match(down, /'booked_jobs'/);
});

test('page: no operation-line tile; station shows days of work and vehicles', () => {
  const html = fs.readFileSync('owner.html', 'utf8');
  assert.doesNotMatch(html, /Jobs in bays|data-h="booked_jobs"/);
  assert.match(html, /data-h="vehicles_booked"/);
  assert.match(html, /data-h="vehicles_not_booked"/);
  assert.match(html, /owner\.js\?r891=[^"]*r892=/);
  const js = fs.readFileSync('owner.js', 'utf8');
  assert.match(js, /days of work/);
  assert.match(js, /b\.vehicles/);
  assert.doesNotMatch(js, /\bs\.booked\b|\bb\.booked\b/);
});
