'use strict';
// r729 (F339, F340): regression check literals follow the live bodies, the QC gate pin follows the applied
// qc_override_closes_jobs_20261029 body, the board snapshot is pre-warmed by cron, and the QC cache refill runs every 5 s.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261029210000_r729_check_hygiene_and_board_prewarm.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261029210000_r729_check_hygiene_and_board_prewarm.down.sql', 'utf8');

test('every literal the file moves is asserted present first, and the live bodies are asserted by md5', () => {
  assert.match(up, /a check literal is not where this file expects it; nothing changed/);
  assert.match(up, /a live function body is not the one this file pins; nothing changed/);
  for (const md5 of ['20fac9508d40f9bb79438208bba7fa45', 'fad0a85d5dfcdfb0526b2062463d3188', 'b2de35bd65bd1021b4dfc14410244dc4', 'be14ea3e9d330a21a5547deb9145a4d7']) {
    assert.ok(up.includes(md5), md5);
  }
});

test('the QC gate pin moves from the r590 value to the applied override-aware body, and back on rollback', () => {
  assert.match(up, /SET prosrc_md5 = '22d863876a4cfa8f127756cc4a8a6da4'/);
  assert.match(up, /WHERE signature = 'public\.pdc_qc_gate_issues\(uuid\)' AND prosrc_md5 = '4973560977892d1a6b3a52c9ec0c7855'/);
  assert.match(down, /SET prosrc_md5 = '4973560977892d1a6b3a52c9ec0c7855'/);
});

test('Key 460 checks follow the vehicle instead of 5.00 h', () => {
  assert.match(up, /IS NOT DISTINCT FROM \(SELECT nullif\(sum\(\(l->>''estimated_hours''\)::numeric\),0\)/);
  assert.match(up, /IS NOT DISTINCT FROM nullif\(open_hours\.total,0\)/);
  assert.doesNotMatch(up, /SET check_sql = replace\(check_sql,'= 5\.00','IS NULL'\)/);
});

test('pre-warm job: every 3 s, working hours only, rebuilds only when the cache is 15 s old, as the display account', () => {
  assert.match(up, /cron\.schedule\('staging-vehicle-board-prewarm-729', '3 seconds'/);
  assert.match(up, /BETWEEN time '05:30' AND time '18:30' AND extract\(isodow FROM clock_timestamp\(\) AT TIME ZONE 'Australia\/Perth'\) < 6/);
  assert.match(up, /computed_at FROM pdc_ops\.vehicle_board_snapshot_cache_545 c WHERE c\.singleton\), '-infinity'\) < clock_timestamp\(\) - interval '15 seconds'/);
  assert.match(up, /"email":"workshopdisplay@pmgwa\.com\.au"/);
  assert.match(up, /cron\.schedule\('staging-cron-history-cleanup-729', '17 2 \* \* \*'/);
  assert.match(down, /cron\.unschedule\(jobid\) FROM cron\.job WHERE jobname = 'staging-vehicle-board-prewarm-729'/);
  assert.match(down, /cron\.unschedule\(jobid\) FROM cron\.job WHERE jobname = 'staging-cron-history-cleanup-729'/);
});

test('refill cadence moves to 5 s with its check, and back', () => {
  assert.match(up, /cron\.alter_job\(jobid, schedule => '5 seconds'\) FROM cron\.job WHERE jobname = 'staging-qc-operation-lines-cache-refill'/);
  assert.match(up, /replace\(check_sql,'''20 seconds''','''5 seconds'''\)/);
  assert.match(down, /schedule => '20 seconds'/);
});

test('post check: the touched rows must be green or the file rolls back; the pin count stays 241', () => {
  assert.match(up, /r729: red after apply, rolled back/);
  assert.match(up, /expected_function_md5\) <> 241 THEN RAISE EXCEPTION 'r729: pin count moved'/);
  assert.match(up, /'board_prewarm_729', 452, 'F340', 'r729'/);
});
