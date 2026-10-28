'use strict';
// r670 (F280): one bad stock never stops the import run.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028240000_r670_import_self_isolating.sql', 'utf8');
test('preview isolates refused stocks; apply holds a refused part; run holds are not permanent', () => {
  assert.match(sql, /v_one := pdc_import_620\.preview_rows\(v_job, p_part \+ 1, pdc_import_620\.stock_rows\(p_job, p_part, v_s\)\);/);
  assert.match(sql, /'refused:' \|\| coalesce\(v_one->>'code'/);
  assert.match(sql, /''apply_refused:'' \|\| left\(SQLERRM, 200\)/);
  assert.match(sql, /SQLSTATE IN \(''55P03'', ''57014'', ''40P01'', ''40001''\)/, 'lock waits and timeouts still retry');
  const hold = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION pdc_import_620.hold_stocks'), sql.indexOf('CREATE FUNCTION pdc_import_620.stock_rows'));
  assert.doesNotMatch(hold, /INSERT INTO pdc_import_620\.holds/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\./);
});
