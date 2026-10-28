'use strict';
// r641 (F256): chunked loading and set-based building for the one-step import.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028220000_r641_one_step_import_chunks.sql', 'utf8');

test('rows load in chunks into a private table; no quadratic appends', () => {
  assert.match(sql, /CREATE TABLE pdc_import_620\.job_rows/);
  assert.match(sql, /CREATE FUNCTION pdc_import_620\.submit_begin\(/);
  assert.match(sql, /CREATE FUNCTION pdc_import_620\.add_rows\(p_job uuid, p_rows jsonb\)/);
  assert.match(sql, /CREATE FUNCTION pdc_import_620\.submit_finish\(p_job uuid\)/);
  assert.doesNotMatch(sql, /v_send := v_send \|\|/);
  assert.match(sql, /IF v_cur > 0 AND v_cur \+ v_s\.n > 180 THEN/);
  assert.match(sql, /v_rows := pdc_import_620\.part_rows\(p_job, p_part\);/);
  assert.match(sql, /v_n := v_job\.n_parts;/);
  assert.match(sql, /coalesce\(p_envelope->>'filename', ''\) = ''/, 'envelope must carry the filename (job cc9b562d)');
});
test('same pins and guards, staging only, pins stay 241', () => {
  for (const pin of ['ea9a62537a146f05a01e866c636d367b', '9be0883b1a555f48f3c1ba9fa111c891', 'b62fb7c29ffd2a1629f214f696e5cb14']) assert.ok(sql.includes(pin));
  assert.match(sql, /project_ref = 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.doesNotMatch(sql.split('$chk641$')[1], /expected_function_md5/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028220000_r641_one_step_import_chunks.down.sql'));
});
