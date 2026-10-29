'use strict';
// r605 (F219): Workshop TV. Pure rendering only; no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const tv = require('./workshop-tv.js');

const at = (h, m = 0) => new Date(Date.UTC(2026, 9, 28, h - 8, m)).toISOString(); // Perth wall clock on 28 Oct
const at2 = (h, m = 0) => new Date(Date.UTC(2026, 9, 29, h - 8, m)).toISOString(); // next working day
const data = {
  days: [{ date: '2026-10-28', from: at(6), to: at(16, 30) }, { date: '2026-10-29', from: at2(6), to: at2(16, 30) }],
  day_start: '06:00', day_end: '16:30',
  stations: [
    { code: 'HOIST', name: 'Hoist', bays: [
      { id: 'h1', name: 'Hoist 1', technician: 'Jason', jobs: [
        { status: 'started', start: at(7), end: at(9), key: '460', stock: '13071838', vehicle: 'HiLux', overrun: true },
        { status: 'planned', start: at(9), end: at(12), key: '359', stock: '13094080', vehicle: 'LC79', overrun: false },
      ] },
      { id: 'h2', name: 'Hoist 2', technician: 'Gary', jobs: [{ status: 'stoppage', start: at(8), end: at(15), key: '307', stock: '13073300', stoppage: 'Parts', overrun: false },
        { status: 'planned', start: at2(7), end: at2(10), key: '264', stock: 'IS60270754', vehicle: 'Coaster', overrun: false }] },
    ] },
    { code: 'TINT', name: 'Tint', bays: [{ name: 'Tint 1', jobs: [{ status: 'completed', start: at(6, 30), end: at(8), key: '1', stock: 'A', overrun: false }] }] },
  ],
};
const now = Date.parse(at(10));

test('job state follows the planner: running, over time, stoppage, done, planned', () => {
  assert.equal(tv.jobState({ status: 'started', end: at(11) }, now), 'live');
  assert.equal(tv.jobState({ status: 'started', end: at(9) }, now), 'over', 'past its end goes red even before the next read');
  assert.equal(tv.jobState({ status: 'stoppage', end: at(15) }, now), 'stop');
  assert.equal(tv.jobState({ status: 'stoppage', end: at(9), overrun: true }, now), 'over');
  assert.equal(tv.jobState({ status: 'completed' }, now), 'done');
  assert.equal(tv.jobState({ status: 'planned' }, now), 'plan');
});

test('bars sit on the day window; an over-time job stretches to now', () => {
  const day = { from: Date.parse(data.days[0].from), to: Date.parse(data.days[0].to) };
  const html = tv.barHtml(data.stations[0].bays[0].jobs[0], { ...day, now });
  assert.match(html, /tv-job is-over/);
  assert.match(html, /left:9\.52%;width:28\.57%/, '07:00 to now 10:00 on a 06:00 to 16:30 day');
  assert.match(html, /K460 · 13071838 · HiLux · due 09:00/);
  assert.equal(tv.barHtml({ status: 'planned', start: at(17), end: at(18) }, { ...day, now }), '', 'planned work after the day is not drawn');
  assert.match(tv.barHtml({ status: 'started', start: at(17), end: at(18) }, { ...day, now }), /is-edge/, 'live work outside the window still shows at the edge');
});

test('board: every station, over-time count, hidden stations drop out', () => {
  const html = tv.boardHtml(data, { now });
  // r706 (F316): Tint is in the Start / Stop strip at the bottom, not a timeline.
  assert.equal((html.match(/<section class="tv-station"/g) || []).length, 1);
  assert.equal((html.match(/<section class="tv-astation tv-zone" data-station="TINT"/g) || []).length, 1);
  assert.match(html, /data-station="HOIST"[\s\S]*1 over time/);
  assert.match(html, /tv-bay has-over/);
  assert.match(html, /is-stop[\s\S]*STOP/);
  const hidden = tv.boardHtml(data, { now, hidden: new Set(['HOIST']) });
  assert.doesNotMatch(hidden, /data-station="HOIST"/);
  assert.match(tv.boardHtml(data, { now, hidden: new Set(['HOIST', 'TINT']) }), /Every station is hidden/);
});

test('two days: today and the next working day side by side; tomorrow has no edge marks or now line', () => {
  const html = tv.boardHtml(data, { now });
  assert.match(html, /<em>Today<\/em>[\s\S]*<em>Thu 29 Oct<\/em>/);
  const hoist2 = html.slice(html.indexOf('Hoist 2'));
  const tracks = hoist2.match(/<div class="tv-track[^"]*">[\s\S]*?<\/div><\/div>|<div class="tv-track[^"]*">[\s\S]*?(?=<div class="tv-track|<\/div><\/section>)/g);
  assert.ok(tracks.length >= 2);
  assert.match(tracks[0], /is-today/);
  assert.match(tracks[0], /13073300/);
  assert.match(tracks[1], /IS60270754/, 'tomorrow shows tomorrow\'s booking');
  assert.doesNotMatch(tracks[1], /is-edge/);
});

test('hide a single bay; a station with every bay hidden drops out', () => {
  const one = tv.boardHtml(data, { now, hidden: new Set([tv.bayKey('h2')]) });
  assert.doesNotMatch(one, /Hoist 2/);
  assert.match(one, /Hoist 1/);
  const none = tv.boardHtml(data, { now, hidden: new Set([tv.bayKey('h1'), tv.bayKey('h2')]) });
  assert.doesNotMatch(none, /data-station="HOIST"/);
  assert.match(none, /data-station="TINT"/);
});

test('hidden stations: the address wins over this screen\'s saved list', () => {
  assert.deepEqual([...tv.parseHidden('?hide=tint,Tyre', ['HOIST'])], ['TINT', 'TYRE']);
  assert.deepEqual([...tv.parseHidden('', ['hoist'])], ['HOIST']);
  assert.deepEqual([...tv.parseHidden('', null)], []);
});

test('Perth clock labels', () => {
  assert.equal(tv.hhmm(Date.parse(at(9, 5))), '09:05');
  assert.equal(tv.dayLabel(Date.parse(at(9))), 'Wed 28 Oct');
});

test('view only and wired: no write RPCs, page ships, staging only', () => {
  const js = fs.readFileSync('workshop-tv.js', 'utf8');
  const rpcs = [...js.matchAll(/rpc\('([a-z0-9_]+)'/g)].map(m => m[1]);
  // r706 (F316): the only writes are Start / Stop for Tint and Tyres, through the planner's own start and complete.
  assert.deepEqual([...rpcs].sort(), ['complete_workshop_work', 'get_pdc_workshop_tv_605', 'start_workshop_work']);
  assert.match(js, /const ACTION_STATIONS = \['TINT', 'TYRE'\];/);
  assert.doesNotMatch(js, /\.from\(/, 'no direct table access, so no table writes');
  assert.doesNotMatch(js, /channel\(|subscribe\(/, 'no realtime channel');
  const html = fs.readFileSync('workshop-tv.html', 'utf8');
  assert.match(html, /workshop-tv\.js\?r605=2026\.10\.28\.r605&amp;r608=2026\.10\.28\.r608&amp;r609=2026\.10\.28\.r609/);
  assert.match(html, /<form id="tv-signin"/, 'r608 (F222): the TV signs in on its own screen');
  assert.match(html, /\[hidden\] \{ display: none !important; \}/, 'r609 (F223): the sign-in gate can hide');
  assert.match(js, /signInWithPassword/);
  assert.match(html, /id="tv-full"/);
  assert.match(js, /requestFullscreen/);
  assert.match(html, /pdc-supabase-config\.staging\.js/);
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(build, /'workshop-tv\.html'/);
  assert.match(build, /'workshop-tv\.js'/);
  const sql = fs.readFileSync('supabase/migrations/20261028140000_r605_workshop_tv.sql', 'utf8');
  assert.match(sql, /STABLE SECURITY DEFINER/);
  assert.match(sql, /expected_function_md5\) <> 241/);
});
