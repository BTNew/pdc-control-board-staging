'use strict';
// r614 (F229): moving a vehicle to QC by location override ticks every item as completed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('QC override trigger ticks every item; tick-all runs as the caller through the controller tick', () => {
  const sql = fs.readFileSync('supabase/migrations/20261028170000_r614_qc_override_ticks.sql', 'utf8');
  assert.match(sql, /SECURITY INVOKER/);
  assert.match(sql, /AFTER UPDATE OF location_override ON public\.vehicles/);
  assert.match(sql, /WHEN \(NEW\.location_override = 'QC' AND OLD\.location_override IS DISTINCT FROM 'QC'/);
  assert.match(sql, /public\.set_panel_line_completion_565\(p_vehicle_id, v_line->>'line_identity', true\)/);
  assert.match(sql, /project_ref = 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.doesNotMatch(sql.split('$chk614$')[1], /expected_function_md5/, 'checks never lock the pin total (F227)');
  assert.ok(fs.existsSync('supabase/rollbacks/20261028170000_r614_qc_override_ticks.down.sql'));
});
