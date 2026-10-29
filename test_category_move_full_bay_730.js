'use strict';
// r730 (F341): moving a category between jobs on a full board. The resize uses the validator's minutes (no 60 minute
// clamp, r372 accepts a shorter booking that equals the estimate) and a lengthen that overlaps the bay pushes the
// later jobs with the planner cascade before it is refused.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261029220000_r730_category_move_on_full_bay.sql', 'utf8');

test('edits are anchored on the exact r680 text and the sublet_rule body md5', () => {
  assert.match(sql, /IS DISTINCT FROM 'b2de35bd65bd1021b4dfc14410244dc4' THEN RAISE EXCEPTION 'r730: set_vehicle_work_category is not the sublet_rule_20261029 \+ r721 body/);
  assert.match(sql, /r730: anchor lengthen block/);
  assert.match(sql, /r730: anchor shorten block/);
  assert.match(sql, /r730: anchor loop 1/);
  assert.match(sql, /r730: anchor loop 2/);
  assert.match(sql, /r730: body readback differs/);
});

test('both resize paths use the validator minutes and no clamp survives', () => {
  assert.match(sql, /mins:=coalesce\(public\.workshop_booking_capacity_duration_minutes\(rec\.id,v\.id,rec\.stage_id,rec\.bay_id\),pdc_work_categories_private\.minutes\(rec\.id,v\.id,rec\.stage_id\)\);/);
  assert.match(sql, /IF strpos\(v_new, 'IF mins<60 THEN mins:=60; END IF;'\) > 0 THEN RAISE EXCEPTION 'r730: a clamp survived'/);
  assert.match(sql, /minutes not replaced twice/);
  // both loops now read b.bay_id
  assert.match(sql, /c_new_loop1 text := \$n\$  FOR rec IN SELECT b\.id, b\.version, b\.stage_id, b\.bay_id,/);
  assert.match(sql, /c_new_loop2 text := \$n\$   FOR rec IN SELECT b\.id, b\.version, b\.stage_id, b\.bay_id,/);
});

test('a lengthen that fails in place pushes the bay with the planner cascade, started jobs never move, then refuses by name', () => {
  assert.match(sql, /r:=pdc_bay_seq_private\.plan_for_move\(rec\.id,rec\.bay_id,rec\.scheduled_start_at\);/);
  assert.match(sql, /pdc_bay_seq_private\.p_apply\(jsonb_build_object\('source','category_release_536','release','r730'/);
  assert.match(sql, /'pushed_for_earlier_stage'\);/);
  assert.match(sql, /could not be lengthened: the bay is full behind it and the later jobs could not be pushed/);
  assert.match(sql, /could not be shortened \(%\)\.', src_stage, rec\.bay_name/);
  // the r680 passed-start rule stays
  assert.match(sql, /c_new_len text := [\s\S]*IF rec\.scheduled_start_at >= clock_timestamp\(\) AND \(mins IS DISTINCT FROM rec\.default_duration_minutes/);
});

test('pin and the r568 literal follow the new body; pin count stays 241; post check must be green', () => {
  assert.match(sql, /SET prosrc_md5 = md5\(v_new\), note = coalesce\(note,''\) \|\| '; r730 \(F341\)/);
  assert.match(sql, /AND release = 'sublet_rule_20261029'/);
  assert.match(sql, /replace\(check_sql, 'b2de35bd65bd1021b4dfc14410244dc4', md5\(v_new\)\) WHERE check_name = 'bus_component_split_568'/);
  assert.match(sql, /'category_move_full_bay_730', 453, 'F341', 'r730'/);
  assert.match(sql, /r730: red after apply, rolled back/);
});
