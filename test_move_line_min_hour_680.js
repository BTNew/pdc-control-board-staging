'use strict';
// r680 (F290): moving a line (e.g. Electrical into Fitting) never resizes an unstarted booking under 60 minutes
// or one whose start has passed; both made "The category was not saved. The unstarted booking could not be lengthened."
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261029010000_r680_move_line_min_hour.sql', 'utf8');
test('both resize paths get the 60 minute floor and the passed-start skip; pin moves', () => {
  assert.match(sql, /resize anchor not found twice/);
  assert.match(sql, /resize condition not found twice/);
  assert.match(sql, /IF mins<60 THEN mins:=60; END IF;/);
  assert.match(sql, /IF rec\.scheduled_start_at >= clock_timestamp\(\) AND \(mins IS DISTINCT FROM/);
  assert.match(sql, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r680' WHERE prosrc_md5 = '240e25e96467490d71744490c7a4d75c'/);
});
