'use strict';
// r764 (F372, Craig 31 Oct 05:58): "maybe view whats already on and only applys changes?" The worker skips unchanged parts.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r764: run_jobs skips unchanged parts, never the last part, no gap after a skip; helpers private; rollback restores run_jobs', () => {
  const up = fs.readFileSync('supabase/migrations/20261031081500_r764_delta_apply.sql', 'utf8');
  assert.match(up, /22538aba31b44f2bb667f98a1cb9a15c/, 'pins the pre-r764 run_jobs body');
  assert.match(up, /CASE WHEN v_i < v_n - 1 THEN pdc_import_620\.part_skip_764\(v_job\.job_id, v_i\) END/);
  assert.match(up, /held_reason IS NOT NULL\) THEN RETURN NULL/);
  assert.match(up, /- 'upload' - 'source_filename' - 'snapshot_sha256' - 'parent_attachment_sha256'/);
  assert.match(up, /no gap after a skipped part/);
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_import_620\.part_skip_764/);
  assert.match(up, /'delta_apply_764', 'F372'/);
  const down = fs.readFileSync('supabase/rollbacks/20261031081500_r764_delta_apply.down.sql', 'utf8');
  assert.match(down, /sig = 'pdc_import_620\.run_jobs\(\)'/);
  assert.match(down, /DROP FUNCTION IF EXISTS pdc_import_620\.part_skip_764/);
});
