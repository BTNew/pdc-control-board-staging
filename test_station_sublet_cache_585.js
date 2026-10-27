/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r585 (F199) / sort 357. The station snapshot and the sublet board keep their old calculations.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const root = __dirname;
const up = fs.readFileSync(path.join(root, 'supabase/migrations/20261028054500_r585_station_sublet_cache.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261028054500_r585_station_sublet_cache.down.sql'), 'utf8');

test('r585 is the next triple after the r584 preview and stays on staging', () => {
  assert.match(up, /r585 \(F199\) \/ sort 357/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt is not a target/);
  assert.match(up, /sort_order=356 OR fault_id='F198'/);
  assert.match(up, /sort 357 \/ F199 is taken/);
  assert.match(down, /r585 \(F199\) undo/);
});

test('the calculation checksums and the protected functions are guarded', () => {
  for (const file of [up, down]) {
    assert.match(file, /98cc6aafa9cc7627c77eda8b46b389fa/);
    assert.match(file, /7dde7e19d31b269136a93ebecd12217a/);
    assert.match(file, /fd05b9eef69498002ac06dd68e01cdff/);
    assert.match(file, /9be0883b1a555f48f3c1ba9fa111c891/);
    assert.match(file, /b62fb7c29ffd2a1629f214f696e5cb14/);
    assert.match(file, /pin count is not 241|pin count changed/);
  }
  assert.match(up, /release='r439'/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
});

test('authorisation happens before the cache is read', () => {
  const station = up.slice(up.indexOf('FUNCTION public.get_station_workshop_snapshot'), up.indexOf('FUNCTION public.get_pdc_sublet_po_board_439'));
  const sublet = up.slice(up.indexOf('FUNCTION public.get_pdc_sublet_po_board_439'), up.indexOf('REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot'));
  assert.ok(station.indexOf('workshop_require_planner_operator') < station.indexOf('station_workshop_snapshot_cache_585'));
  assert.ok(sublet.indexOf('PDC_439_UNAUTHORIZED') < sublet.indexOf('sublet_po_board_cache_585'));
  assert.match(station, /pdc-r585-station:/);
  assert.match(sublet, /pdc-r585-sublet-board/);
  assert.match(station, /interval '15 seconds'/);
  assert.match(up, /fresh IS DISTINCT FROM once OR once IS DISTINCT FROM twice/);
});
