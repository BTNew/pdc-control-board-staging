'use strict';
// r674 (F283): an apply import puts every stock it sends on the board (New Vehicles counts).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028260000_r674_import_boards_every_stock.sql', 'utf8');
test('apply releases owner holds and requeues hidden vehicles; preview only counts', () => {
  assert.match(sql, /board_every_stock_674\(p_job, v_job\.mode = ''apply'' AND v_status = ''queued''\)/);
  assert.match(sql, /UPDATE pdc_codex_intake_private\.owner_board_visibility_holds_20261019/);
  assert.match(sql, /ON CONFLICT \(vehicle_id\) DO UPDATE SET status = 'pending'/);
  assert.match(sql, /add_hold\('BUSPARTS', 'standing_hold:not_a_vehicle'\)/);
  assert.match(sql, /sort_order = 422 OR fault_id = 'F283'/);
});
