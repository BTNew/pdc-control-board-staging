'use strict';
// r754 (F359): an overdue planned job follows the clock within 5 minutes; a live overrun keeps the r552 15 minute step.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030111500_r754_overdue_job_follows_clock.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030111500_r754_overdue_job_follows_clock.down.sql', 'utf8');
test('r754: one anchored line in the tick, pins and literals move, resaves check counts cosmetic under 5 minutes, check 464', () => {
  assert.match(up, /IF v_md5 <> '593971a38ed792793513985f49156ac6' THEN RAISE EXCEPTION 'r754: tick is not the r737 body'/);
  assert.match(up, /OR \(status=''planned'' AND actual_start_at IS NULL AND original_start<p_now AND abs\(extract\(epoch FROM \(\(movement->>''to''\)::timestamptz-original_start\)\)\)>=300\)\);/);
  assert.match(up, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = md5\(v_new\) WHERE prosrc_md5 = v_md5;/);
  assert.match(up, /IF v_n < 6 THEN RAISE EXCEPTION 'r754: md5 literals not moved/);
  assert.match(up, /WHERE check_name = 'clock_tick_resaves_per_tick'/);
  assert.match(up, /'overdue_job_follows_clock_754', 'F359',/);
  assert.match(up, /b\.scheduled_start_at < now\(\) - interval '7 minutes'/);
  assert.match(down, /<> '593971a38ed792793513985f49156ac6' THEN RAISE EXCEPTION 'r754 down: body is not the r737 body'/);
});
