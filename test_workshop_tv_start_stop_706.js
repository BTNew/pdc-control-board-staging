'use strict';
// r706 (F316): Tint and Tyres on the Workshop TV: side by side at the bottom, full key, Start / Stop for operator logins.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const tv = require('./workshop-tv.js');
const now = Date.parse('2026-10-29T03:00:00Z');
const day = { date: '2026-10-29', from: '2026-10-28T23:00:00Z', to: '2026-10-29T09:00:00Z' };
const next = { date: '2026-10-30', from: '2026-10-29T23:00:00Z', to: '2026-10-30T09:00:00Z' };
const job = (over) => ({ id: 'b1', booking_version: 3, status: 'planned', start: '2026-10-29T04:00:00Z', end: '2026-10-29T05:00:00Z', key: '627', stock: 'S1', ...over });
const data = (canAct, jobs) => ({ can_act: canAct, days: [day, next], stations: [
  { code: 'HOIST', name: 'Hoist', bays: [{ id: 'h1', name: 'Hoist 1', jobs: [job({ id: 'hx' })] }] },
  { code: 'TINT', name: 'Tint', work_key: 'tint', bays: [{ id: 't1', name: 'Tint Bay 01', jobs }] },
  { code: 'TYRE', name: 'Tyres', work_key: 'tyre', bays: [{ id: 'y1', name: 'Tyre Bay 01', jobs: [job({ id: 'y', status: 'started', start: '2026-10-29T02:00:00Z' })] }] },
] });

test('Tint and Tyres sit side by side at the bottom with the full key', () => {
  const html = tv.boardHtml(data(true, [job()]), { now });
  assert.ok(html.indexOf('tv-actions') > html.indexOf('data-station="HOIST"'));
  // r710 (F320): four zones, one per bay; key, car type and the button only.
  assert.match(html, /<div class="tv-actions"><section class="tv-astation tv-zone" data-station="TINT" data-bay="t1"><h2>Tint Bay 01<\/h2>[\s\S]*<section class="tv-astation tv-zone" data-station="TYRE" data-bay="y1">/);
  assert.doesNotMatch(html.slice(html.indexOf('tv-actions')), /S1/);
  assert.match(html, /Key 627/);
});
test('Start for planned, Stop for running; Hoist has no buttons', () => {
  const html = tv.boardHtml(data(true, [job()]), { now });
  assert.match(html, /data-tv-act="start" data-id="b1" data-v="3" data-work="tint"/);
  assert.match(html, /data-tv-act="stop" data-id="y" data-v="3" data-work="tyre"/);
  assert.doesNotMatch(html, /data-id="hx"/);
});
test('no buttons when this login cannot start work', () => {
  assert.doesNotMatch(tv.boardHtml(data(false, [job()]), { now }), /data-tv-act/);
});
test('the read carries ids, version and can_act; the page cache-busts', () => {
  const sql = fs.readFileSync('supabase/migrations/20261029120000_r706_tv_tint_tyre_start_stop.sql', 'utf8');
  assert.match(sql, /''can_act'', coalesce\(public\.workshop_is_planner_operator\(\), false\)/);
  assert.match(fs.readFileSync('workshop-tv.html', 'utf8'), /&amp;r706=2026\.10\.29\.r706(&amp;r710=2026\.10\.29\.r710)?(&amp;r711=2026\.10\.29\.r711)?(&amp;r720=2026\.10\.29\.r720)?"/);
});
test('r710: each zone shows the current job, the next and the one after; no done jobs', () => {
  const jobs = [
    job({ id: 'd', status: 'completed', actual_start: '2026-10-29T00:00:00Z', actual_end: '2026-10-29T01:00:00Z', key: '900' }),
    job({ id: 'c', status: 'started', start: '2026-10-29T02:00:00Z', key: '901' }),
    job({ id: 'n1', start: '2026-10-29T04:00:00Z', key: '902' }),
    job({ id: 'n2', start: '2026-10-29T05:00:00Z', key: '903' }),
    job({ id: 'n3', start: '2026-10-29T06:00:00Z', key: '904' }),
  ];
  const zone = tv.boardHtml(data(true, jobs), { now }).split('data-bay="t1"')[1].split('</section>')[0];
  assert.deepEqual([...zone.matchAll(/Key (\d+)/g)].map(m => m[1]), ['901', '902', '903']);
});
test('r711: a refused Start or Stop shows the reason on the bay in big type and the board reloads straight away', () => {
  const js = fs.readFileSync('workshop-tv.js', 'utf8');
  assert.match(js, /admin_block_conflict: 'an admin block is booked in this bay/);
  assert.match(js, /paintNotes\(\);\n      await load\(\); \/\/ refresh straight away\n      paintNotes\(\);/);
  assert.match(fs.readFileSync('workshop-tv.html', 'utf8'), /\.tv-znote\.is-bad/);
});
