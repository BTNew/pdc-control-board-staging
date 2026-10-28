'use strict';
// r688 (F298): QC functions use the shown location (override first), and leaving QC clears the override.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261029030000_r688_qc_follows_override.sql', 'utf8');
test('guard checks override before current_location', () => {
  assert.match(sql, /coalesce\(nullif\(btrim\(\\2\.location_override\),''\),\\2\.current_location,''\)\)\)<>'QC'/);
});
test('moving to RFT or back to PMB clears the override', () => {
  assert.match(sql, /current_location='\\1',location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,/);
  assert.match(sql, /expected 1/);
});
test('public schema only, never pinned or checked functions, originals backed up, 9 bodies', () => {
  assert.match(sql, /p\.pronamespace = 'public'::regnamespace/);
  assert.match(sql, /is pinned or named by a check/);
  assert.match(sql, /pdc_ops\.r688_function_backup/);
  assert.match(sql, /v_total <> 9/);
  assert.match(sql, /import window/);
});
test('rollback restores from backup', () => {
  const down = fs.readFileSync('supabase/rollbacks/20261029030000_r688_qc_follows_override.down.sql', 'utf8');
  assert.match(down, /r688_function_backup/);
  assert.match(down, /qc_follows_override_688/);
});
