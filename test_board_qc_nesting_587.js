/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r587 (F201) / sort 359. QC lines and candidate work items are read once.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const root = __dirname;
const up = fs.readFileSync(path.join(root, 'supabase/migrations/20261028064500_r587_board_qc_nesting.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261028064500_r587_board_qc_nesting.down.sql'), 'utf8');

test('r587 is the next triple after r586 and leaves the r584 preview alone', () => {
  assert.match(up, /r587 \(F201\) \/ sort 359/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt is not a target/);
  assert.match(up, /sort_order=356 OR fault_id='F198'/);
  assert.match(up, /sort 359 \/ F201 is taken/);
  assert.match(down, /r587 \(F201\) undo/);
  assert.match(down, /f744636778e0f10128d6457605430c2f/);
  assert.match(down, /633a0124502c70d88a552985af2c6e2e/);
});

test('the protected functions stay put and nothing is newly pinned', () => {
  for (const file of [up, down]) {
    assert.match(file, /fd05b9eef69498002ac06dd68e01cdff/);
    assert.match(file, /9be0883b1a555f48f3c1ba9fa111c891/);
    assert.match(file, /b62fb7c29ffd2a1629f214f696e5cb14/);
    assert.match(file, /3b2398e33a2ea35fc137deeedeca4af5/);
    assert.match(file, /pin count is not 241|pin count changed/);
    assert.match(file, /b7f90bff12643229ff80f8ca552663a2|QC wrapper/);
  }
  assert.match(up, /b7f90bff12643229ff80f8ca552663a2/);
  assert.match(up, /97fc4caaf7b462163d35b4a3511bc487/);
  assert.match(up, /a93005010cf96ab6eb804ef879039861/);
  assert.match(up, /1b8106327e68624c8f235c2e84641842/);
  assert.match(up, /9207f7c1664552122775bb4a2e6d9f25/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
});

test('the rewrite reads the QC cache and aggregates work items once', () => {
  assert.match(up, /qc_operation_lines_cache/);
  assert.match(up, /work_items_587/);
  assert.match(up, /ORDER BY wi\.ctid/);
  assert.match(up, /old_snap IS DISTINCT FROM new_snap/);
  assert.match(up, /board_qc_nesting_587/);
  assert.match(up, /second_ms < 2000/);
  assert.match(down, /workshop_stage_code_for_work_key\(wi\.work_key\)=e\.stage_code/);
  assert.match(down, /public\.pdc_qc_operation_lines_379\(v\.id\) lines/);
});
