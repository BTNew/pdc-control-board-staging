/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r586 (F200) / sort 358. Waiters on the vehicle board return the last snapshot.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const root = __dirname;
const up = fs.readFileSync(path.join(root, 'supabase/migrations/20261028063000_r586_board_waiter_cache.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261028063000_r586_board_waiter_cache.down.sql'), 'utf8');
const body = up.split('$function$')[1];

test('r586 is the next triple after r585 and leaves the r584 preview alone', () => {
  assert.match(up, /r586 \(F200\) \/ sort 358/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt is not a target/);
  assert.match(up, /sort_order=356 OR fault_id='F198'/);
  assert.match(up, /sort 358 \/ F200 is taken/);
  assert.match(down, /r586 \(F200\) undo/);
  assert.match(down, /ae706516b88574c1162e2c5889e4b4a9/);
});

test('the protected functions stay put and the board function is not newly pinned', () => {
  for (const file of [up, down]) {
    assert.match(file, /fd05b9eef69498002ac06dd68e01cdff/);
    assert.match(file, /9be0883b1a555f48f3c1ba9fa111c891/);
    assert.match(file, /b62fb7c29ffd2a1629f214f696e5cb14/);
    assert.match(file, /3b2398e33a2ea35fc137deeedeca4af5/);
    assert.match(file, /pin count is not 241|pin count changed/);
  }
  assert.match(up, /board function is pinned/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
});

test('a waiter returns the last snapshot and does not take the blocking lock', () => {
  assert.ok(body.indexOf('current_pdc_user_role') < body.indexOf('vehicle_board_snapshot_cache_545'));
  assert.match(body, /pg_catalog\.pg_try_advisory_xact_lock/);
  assert.equal(body.indexOf('pg_catalog.pg_advisory_xact_lock'), -1);
  assert.match(body, /interval '1500 milliseconds'/);
  assert.match(body, /board_busy/);
  assert.match(body, /interval '15 seconds'/);
  assert.match(body, /pdc-r545-vehicle-board/);
  assert.equal(body.split('FROM public.pdc_email_vehicle_revision').length - 1, 2);
  assert.match(down, /PERFORM pg_catalog\.pg_advisory_xact_lock/);
});
