'use strict';
// r802 (F417, Craig 1 Nov 12:04): "Shouldnt it just tell me whats changing?" A file that matches the last import shows nothing changing.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ts = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');

function loadPreviewOther(rpcResult) {
  const start = ts.indexOf('async function previewOther802(');
  const end = ts.indexOf('\nasync function changedRows782(');
  assert.ok(start > 0 && end > start);
  const src = ts.slice(start, end);
  // eslint-disable-next-line no-new-func
  return new Function('rpcAs', `${src}; return previewOther802;`)(async (_u, _a, name) => {
    assert.equal(name, 'revolution_upload_other_delta_802');
    return rpcResult;
  });
}

test('r802: CW parts matched job cards that match the last import are unchanged, not updated', async () => {
  const fn = loadPreviewOther({ ok: true, since: '2026-11-01T04:02:39Z', unchanged: ['J1', 'J2'], changed: ['J3'], first_time: [], skipped_last: [] });
  const result = { counts: { updated: 3, skipped: 82 }, errors: [], changes: { updated: [{ ro: 'J1' }, { ro: 'J2' }, { ro: 'J3' }] } };
  await fn('', '', { kind: 'cw_parts', rows: [] }, result);
  assert.equal(result.counts.updated, 1);
  assert.equal(result.counts.unchanged, 2);
  assert.match(result.summary, /^1 job cards changed, 2 unchanged, 82 not on the board/);
});

test('r802: deal items skipped last time (not on Navision) are not new', async () => {
  const fn = loadPreviewOther({ ok: true, since: 'x', unchanged: ['A', 'B', 'C'], changed: [], first_time: ['D'], skipped_last: ['A'] });
  const result = { counts: { new: 3, updated: 1 }, errors: [], changes: { new: [{ stock: 'A' }, { stock: 'B' }, { stock: 'D' }], updated: [{ stock: 'C' }], unchanged: [] } };
  await fn('', '', { kind: 'kta_deal_items', rows: [] }, result);
  assert.deepEqual(result.changes.new.map((e) => e.stock), ['D']);
  assert.deepEqual(result.changes.skipped_last.map((e) => e.stock), ['A']);
  assert.deepEqual(result.changes.unchanged.map((e) => e.stock).sort(), ['B', 'C']);
  assert.equal(result.counts.updated, 0);
});

test('r802: no compare available leaves the board counts alone', async () => {
  const fn = loadPreviewOther({ ok: false, error: 'administrator_required' });
  const result = { counts: { updated: 5 }, errors: [], changes: { updated: [{ ro: 'J1' }] } };
  await fn('', '', { kind: 'cw_parts', rows: [] }, result);
  assert.equal(result.counts.updated, 5);
  assert.equal(result.delta.ok, false);
});

test('r802: wiring, service stays-off bucket, page labels, migration and cache tag', () => {
  assert.match(ts, /if \(OTHER_781\.has\(parsed\.kind\)\) await previewOther802\(/);
  assert.match(ts, /heldBefore\.has\(up\(entry\.stock\)\) \? staysOff : stillNew/);
  assert.match(ts, /changes\.stays_off = staysOff;/);
  const js = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(js, /\['stays_off', 'Staying off the board'/);
  assert.match(js, /\['skipped_last', 'Not on Navision \(skipped\)'/);
  assert.match(js, /'New in this report'/);
  const up = fs.readFileSync('supabase/migrations/20261101140000_r802_honest_previews.sql', 'utf8');
  assert.match(up, /FUNCTION public\.revolution_upload_other_delta_802\(p_kind text, p_rows jsonb\)/);
  assert.match(up, /CREATE TRIGGER vehicles_back_on_board_unpurge_802 BEFORE UPDATE OF visible_on_board/);
  assert.match(up, /'board_car_not_purged_802', 'F417'/);
  assert.match(up, /'other_upload_delta_802', 'F417'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-revolution-upload\.js\?[^"]*&amp;r802=2026\.11\.01\.r802/);
});
