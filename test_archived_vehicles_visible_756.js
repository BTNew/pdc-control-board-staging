'use strict';
// r756a (F361, Craig 30 Oct 11:55): administrators can see archived cars on the Completed page (Archived | All left the board).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r756a: list_archived_vehicles_756 lists archived, not deleted or completed cars; check 468; Completed page scope', () => {
  const up = fs.readFileSync('supabase/migrations/20261030120500_r756a_archived_vehicles_list.sql', 'utf8');
  assert.match(up, /CREATE FUNCTION public\.list_archived_vehicles_756\(\)/);
  assert.match(up, /board_purged_at IS NOT NULL/);
  assert.match(up, /'archived_vehicles_visible_756', 'F361',/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261030120500_r756a_archived_vehicles_list.down.sql'));
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /client\.rpc\('list_archived_vehicles_756'\)/);
  assert.match(app, /function leftBoardRows756\(scope, archived\)/);
  assert.match(app, /if \(scope === 'all'\) \{[\s\S]*completedHistoryRows\(\)[\s\S]*deletedVehicleRecords\(\)/);
  const html = fs.readFileSync('index.html', 'utf8');
  for (const pick of ['completed', 'archived', 'all']) assert.match(html, new RegExp(`data-completed-scope-pick="${pick}"`));
  assert.match(html, /r756=2026\.10\.30\.r756/);
});
