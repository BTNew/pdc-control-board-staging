'use strict';
// r660 (F270): Status 80 goes to QC with every checkable item ticked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028233000_r660_status80_to_qc.sql', 'utf8');
test('edits the r511 text in place, ticks panel items, clears stoppage, moves the pin and its checks', () => {
  assert.match(sql, /md5\(v_old\) <> '9808feb2a0a93a79b0d67aebdca0a4aa'/);
  assert.match(sql, /active_stoppage_requires_review[\s\S]*sublet_return_requires_review[\s\S]*pending_operation_changes_require_review/);
  assert.match(sql, /INSERT INTO public\.pdc_panel_line_completion_565/);
  assert.match(sql, /NOT IN\(''JOB_CARD_NOTES'',''PIT_INSPECTION''\)/);
  assert.match(sql, /pmb_stoppage_started_at=NULL/);
  assert.match(sql, /IF v_n <> 4 THEN RAISE EXCEPTION 'r660: expected 4 checks/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.doesNotMatch(sql, /pdc_pilbara_service_apply_v1\(|CREATE OR REPLACE FUNCTION public\.pdc_pilbara/);
});
