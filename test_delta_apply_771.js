'use strict';
// r771 (F372, Craig 31 Oct 05:58): "maybe view whats already on and only applys changes?" The worker skips unchanged parts.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r771: run_jobs skips unchanged parts, never the last part, no gap after a skip; helpers private; rollback restores run_jobs', () => {
  const up = fs.readFileSync('supabase/migrations/20261031081500_r771_delta_apply.sql', 'utf8');
  assert.match(up, /22538aba31b44f2bb667f98a1cb9a15c/, 'pins the pre-r771 run_jobs body');
  assert.match(up, /CASE WHEN v_i < v_n - 1 THEN pdc_import_620\.part_skip_771\(v_job\.job_id, v_i\) END/);
  assert.match(up, /held_reason IS NOT NULL\) THEN RETURN NULL/);
  assert.match(up, /- 'upload' - 'source_filename' - 'snapshot_sha256' - 'parent_attachment_sha256'/);
  assert.match(up, /no gap after a skipped part/);
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_import_620\.part_skip_771/);
  assert.match(up, /'delta_apply_771', 'F372'/);
  const down = fs.readFileSync('supabase/rollbacks/20261031081500_r771_delta_apply.down.sql', 'utf8');
  assert.match(down, /sig = 'pdc_import_620\.run_jobs\(\)'/);
  assert.match(down, /DROP FUNCTION IF EXISTS pdc_import_620\.part_skip_771/);
});

test('r772: archive releases bay bookings before completing the car; duplicate only when every part applied; preview has no open-job-card exemption', () => {
  const up = fs.readFileSync('supabase/migrations/20261031083000_r772_archive_release_before_complete.sql', 'utf8');
  assert.match(up, /96a4aa80c2a2320dc0fdc082599b8683/, 'pins the r763 archive body');
  assert.match(up, /guard \|\| v_rel \|\| a_upd/);
  assert.match(up, /bookings are still released after the vehicle update/);
  assert.match(up, /IS DISTINCT FROM ''true''\)\) THEN -- r772/);
  assert.match(up, /'archive_release_before_complete_772', 'F373'/);
  assert.match(fs.readFileSync('supabase/rollbacks/20261031083000_r772_archive_release_before_complete.down.sql', 'utf8'), /@r763/);
  const parse = fs.readFileSync('supabase/functions/revolution-upload/parse.js', 'utf8');
  assert.doesNotMatch(parse, /kept_open_job_card/);
  assert.doesNotMatch(fs.readFileSync('pdc-revolution-upload.js', 'utf8'), /Kept, job card still open/);
});
