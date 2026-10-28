'use strict';
// r606 (F220): the control board marks a job running past its end "Over time" in red, like the planner.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const board = require('./control-board-overview.js');

const now = Date.parse('2026-10-28T02:00:00Z');
const job = (status, end, extra = {}) => ({ kind: 'booking', status, source: { scheduled_end_at: end, ...extra } });

test('over time: started past its end, or stopped after its end', () => {
  assert.equal(board.isOvertime(job('started', '2026-10-28T01:00:00Z'), now), true);
  assert.equal(board.isOvertime(job('started', '2026-10-28T03:00:00Z'), now), false);
  assert.equal(board.isOvertime(job('stoppage', '2026-10-28T01:00:00Z', { stoppage_started_at: '2026-10-28T01:30:00Z' }), now), true);
  assert.equal(board.isOvertime(job('stoppage', '2026-10-28T01:00:00Z', { stoppage_started_at: '2026-10-28T00:30:00Z' }), now), false);
  assert.equal(board.isOvertime(job('planned', '2026-10-28T01:00:00Z'), now), false, 'planned work is never over time');
  assert.equal(board.isOvertime({ kind: 'admin', status: 'admin', source: {} }, now), false);
});

test('wired into bars and cards with a red style; cache-busted', () => {
  const src = fs.readFileSync('control-board-overview.js', 'utf8');
  assert.equal((src.match(/\$\{overClass\(item\)\}/g) || []).length, 3, 'day/week bars, month bars and bay cards');
  assert.match(src, /is-overtime\{background:#dc2626/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /control-board-overview\.js\?department-bays=2026\.10\.15\.02&amp;r606=2026\.10\.28\.r606&amp;/);
});
