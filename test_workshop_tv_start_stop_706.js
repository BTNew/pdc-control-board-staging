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
  // r744 (F349) replaces r710's four bay zones: two halves, Tyres then Tint; key, car type, time and the button.
  assert.match(html, /<div class="tv-actions"><section class="tv-astation tv-zone" data-station="TYRE" data-bay="TYRE"><h2>Tyres [\s\S]*<section class="tv-astation tv-zone" data-station="TINT" data-bay="TINT"><h2>Tint /);
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
  assert.match(fs.readFileSync('workshop-tv.html', 'utf8'), /&amp;r706=2026\.10\.29\.r706(&amp;r710=2026\.10\.29\.r710)?(&amp;r711=2026\.10\.29\.r711)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?(&amp;r\d+=[\d.]+r\d+)*"/);
});
test('r744 (F349): each half lists the whole day: running, then waiting by time, then done; every waiting job has Start', () => {
  const jobs = [
    job({ id: 'd', status: 'completed', actual_start: '2026-10-29T00:00:00Z', actual_end: '2026-10-29T01:00:00Z', key: '900' }),
    job({ id: 'c', status: 'started', start: '2026-10-29T02:00:00Z', key: '901' }),
    job({ id: 'n3', start: '2026-10-29T06:00:00Z', key: '904' }),
    job({ id: 'n1', start: '2026-10-29T04:00:00Z', key: '902' }),
    job({ id: 'n2', start: '2026-10-29T05:00:00Z', key: '903' }),
    job({ id: 'tm', start: '2026-10-30T00:00:00Z', key: '905' }),
  ];
  const zone = tv.boardHtml(data(true, jobs), { now }).split('data-bay="TINT"')[1].split('</section>')[0];
  assert.deepEqual([...zone.matchAll(/Key (\d+)/g)].map(m => m[1]), ['901', '902', '903', '904', '900'], 'tomorrow waits while today has work');
  assert.equal((zone.match(/data-tv-act="start"/g) || []).length, 3, 'two fitters: every waiting job can be started');
  assert.match(zone, /1 running · 3 to start · 1 done/);
});
test('r744: two bays in a station show as one list with the bay named', () => {
  const d = data(true, []);
  d.stations[2].bays.push({ id: 'y2', name: 'Tyre Bay 02', jobs: [job({ id: 'z', key: '777', start: '2026-10-29T03:30:00Z' })] });
  const zone = tv.boardHtml(d, { now }).split('data-bay="TYRE"')[1].split('</section>')[0];
  assert.deepEqual([...zone.matchAll(/Key (\d+)/g)].map(m => m[1]), ['627', '777']);
  assert.match(zone, /Tyre Bay 02/);
  assert.doesNotMatch(tv.boardHtml(d, { now, hidden: new Set([tv.bayKey('y2')]) }), /Key 777/, 'a bay hidden on this TV stays hidden');
});
test('r744: nothing left to start today shows the next working day dashed', () => {
  const jobs = [job({ id: 'tm', start: '2026-10-30T00:00:00Z', key: '905' })];
  const zone = tv.boardHtml(data(true, jobs), { now }).split('data-bay="TINT"')[1].split('</section>')[0];
  assert.match(zone, /tv-aj is-plan is-later[\s\S]*Key 905[\s\S]*Fri 30 Oct 08:00[\s\S]*data-tv-act="start"/);
});
test('r744: a refused second Start in the same bay says why', () => {
  assert.match(fs.readFileSync('workshop-tv.js', 'utf8'), /bay_already_started: 'another job is already running in this bay/);
});
test('r711: a refused Start or Stop shows the reason on the bay in big type and the board reloads straight away', () => {
  const js = fs.readFileSync('workshop-tv.js', 'utf8');
  assert.match(js, /admin_block_conflict: 'an admin block is booked in this bay/);
  assert.match(js, /paintNotes\(\);\n      await load\(\); \/\/ refresh straight away\n      paintNotes\(\);/);
  assert.match(fs.readFileSync('workshop-tv.html', 'utf8'), /\.tv-znote\.is-bad/);
});
test('r741: Tint and Tyre button reads Complete; a busy-lock refusal retries once', () => {
  const html = tv.boardHtml(data(true, [job()]), { now });
  assert.match(html, /data-tv-act="stop"[^>]*>Complete<\/button>/);
  assert.doesNotMatch(html, />Stop<\/button>/);
  const js = fs.readFileSync('workshop-tv.js', 'utf8');
  assert.match(js, /lock timeout\|deadlock/);
  assert.match(js, /'Completing…'/);
});
