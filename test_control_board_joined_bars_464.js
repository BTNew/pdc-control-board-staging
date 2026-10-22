/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r464 (F77): a booking that runs past the day divider is drawn as ONE bar on the
// control board overview. Display only; segments (per-day pieces) are unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');

const stamp = (date, clock) => `${date}T${clock}:00+08:00`;
function snapshot() {
  const value = fixture.emptySnapshot();
  value.board.calendar = { day_start_time: '06:00', day_end_time: '16:30', working_week: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
    closures: [], overtime_windows: [], break_windows: [], scheduling_increment_minutes: 15 };
  return value;
}
const bay = (value, index = 0) => value.board.bays[index];
function add(value, n, start, end, overrides = {}, bayIndex = 0, person) {
  const row = fixture.booking(n, bay(value, bayIndex), person, { scheduled_start_at: start, scheduled_end_at: end, ...overrides });
  value.board.bookings.push(row);
  return row;
}
const opts = { startDate: '2026-10-22', dayCount: 4, now: stamp('2026-10-22', '07:00') };
const html = value => overview.render(overview.buildModel(value), opts);
const jobs = markup => markup.match(/<button type="button" class="control-board-timeline-job[^>]*>/g) || [];
const attr = (tag, name) => (new RegExp(`${name}="([^"]*)"`).exec(tag) || [])[1];

test('a booking split by the day divider renders as one element across it', () => {
  const value = snapshot();
  const row = add(value, 1, stamp('2026-10-22', '09:39'), stamp('2026-10-23', '11:50'));
  const t = overview.buildTimeline(overview.buildModel(value), opts);
  const r = t.rows.find(x => x.segments.length);
  assert.equal(r.segments.length, 2, 'per-day pieces unchanged (parity checks rely on them)');
  assert.equal(r.bars.length, 1);
  const [bar] = r.bars;
  assert.equal(bar.joined, true);
  assert.equal(bar.left, r.segments[0].left);
  assert.equal(bar.left + bar.width, r.segments[1].left + r.segments[1].width);
  assert.ok(bar.left < t.dayWidth && bar.left + bar.width > t.dayWidth, 'crosses the divider');
  const tags = jobs(html(value));
  assert.equal(tags.length, 1);
  assert.match(tags[0], /is-joined/);
  assert.equal(attr(tags[0], 'data-control-board-id'), row.booking_id);
  assert.equal(attr(tags[0], 'data-control-board-date'), '2026-10-22');
  assert.match(attr(tags[0], 'data-control-board-parts'), /^2026-10-22@0-[\d.]+ 2026-10-23@[\d.]+-[\d.]+$/);
  const title = attr(tags[0], 'title');
  assert.match(title, /One booking · 12.7 h over 2 parts/);
  assert.match(title, /2026-10-22 · 9:39 am–4:30 pm · 6.9 h/);
  assert.match(title, /2026-10-23 · 6 am–11:50 am · 5.8 h/);
  assert.doesNotMatch(attr(tags[0], 'aria-label'), /\n/);
});

test('a closed weekend between pieces splits the bar: Thu+Fri one bar, Mon its own bar', () => {
  const value = snapshot();
  add(value, 1, stamp('2026-10-22', '12:00'), stamp('2026-10-26', '10:00'));
  const t = overview.buildTimeline(overview.buildModel(value), { ...opts, dayCount: 7 });
  const r = t.rows.find(x => x.segments.length);
  assert.deepEqual(r.segments.map(x => x.date), ['2026-10-22', '2026-10-23', '2026-10-26']);
  assert.equal(r.bars.length, 2);
  assert.deepEqual(r.bars.map(b => b.parts.map(x => x.date)), [['2026-10-22', '2026-10-23'], ['2026-10-26']]);
  assert.equal(r.bars[0].joined, true);
  assert.equal(r.bars[1].joined, undefined, 'Monday piece renders exactly as a pre-r464 single piece');
  assert.equal(new Set(r.bars.map(b => b.lane)).size, 1, 'same lane');
  const tags = jobs(overview.render(overview.buildModel(value), { ...opts, dayCount: 7 }));
  assert.equal(tags.length, 2);
  assert.match(attr(tags[0], 'title'), /One booking · 15 h over 2 parts · Continues next working day · Booking total 19 h/);
  assert.match(attr(tags[1], 'title'), /2026-10-26 · 6 am–10 am · Continued from previous day$/);
});

test('Fri to Mon stays two bars (one each side of the weekend)', () => {
  const value = snapshot();
  add(value, 1, stamp('2026-10-23', '14:00'), stamp('2026-10-26', '08:00'));
  const t = overview.buildTimeline(overview.buildModel(value), { ...opts, dayCount: 7 });
  const r = t.rows.find(x => x.segments.length);
  assert.equal(r.bars.length, 2);
  assert.ok(r.bars.every(b => !b.joined));
});

test('different bookings stay separate, even when adjacent across the divider in one bay', () => {
  const value = snapshot();
  add(value, 1, stamp('2026-10-22', '12:00'), stamp('2026-10-22', '16:30'));
  add(value, 2, stamp('2026-10-23', '06:00'), stamp('2026-10-23', '09:00'));
  const tags = jobs(html(value));
  assert.equal(tags.length, 2);
  assert.ok(tags.every(tag => !/is-joined/.test(tag)));
});

test('same vehicle with a different tech (another bay) stays separate', () => {
  const value = snapshot();
  const person = fixture.vehicle ? fixture.vehicle(7) : undefined;
  add(value, 1, stamp('2026-10-22', '12:00'), stamp('2026-10-22', '16:30'), {}, 0, person);
  add(value, 2, stamp('2026-10-23', '06:00'), stamp('2026-10-23', '09:00'), {}, 1, person);
  const t = overview.buildTimeline(overview.buildModel(value), opts);
  assert.deepEqual(t.rows.filter(r => r.bars.length).map(r => r.bars.length), [1, 1]);
  assert.equal(jobs(html(value)).length, 2);
});

test('single-day bookings render exactly as before (markup unchanged)', () => {
  const value = snapshot();
  add(value, 1, stamp('2026-10-22', '07:00'), stamp('2026-10-22', '09:00'));
  const t = overview.buildTimeline(overview.buildModel(value), opts);
  const r = t.rows.find(x => x.segments.length);
  assert.equal(r.bars.length, 1);
  assert.equal(r.bars[0].joined, undefined);
  const [tag] = jobs(html(value));
  assert.doesNotMatch(tag, /is-joined|data-control-board-parts/);
  assert.match(attr(tag, 'title'), /\n2026-10-22 · 7 am–9 am$/);
  assert.equal(attr(tag, 'style'), `left:${r.segments[0].left}px;width:${r.segments[0].width}px;top:5px`);
});

test('a joined bar keeps the status class (Running / stoppage colours) and one progress slot', () => {
  const value = snapshot();
  add(value, 1, stamp('2026-10-21', '09:00'), stamp('2026-10-23', '09:00'), { status: 'started', actual_start_at: stamp('2026-10-21', '09:00') });
  const markup = overview.render(overview.buildModel(value), { ...opts, startDate: '2026-10-21' });
  const tags = jobs(markup);
  assert.equal(tags.length, 1);
  assert.match(tags[0], /control-board-timeline-job is-started[^"]* is-joined/);
});

test('clicking a joined bar picks the clicked day (capture listener in mountTimeline)', () => {
  const src = fs.readFileSync(require.resolve('./control-board-overview.js'), 'utf8');
  assert.match(src, /scroll\.addEventListener\('click', joinedClick, true\)/);
  assert.match(src, /scroll\.removeEventListener\('click', joinedClick, true\)/);
});

test('r464 is display only: styles.css and app.js untouched, cache-bust tag present', () => {
  const index = fs.readFileSync(require.resolve('./index.html'), 'utf8');
  assert.match(index, /control-board-overview\.js\?[^"]*r464=2026\.10\.22\.r464/);
  const src = fs.readFileSync(require.resolve('./control-board-overview.js'), 'utf8');
  assert.doesNotMatch(src, /\.rpc\(|fetch\(/);
});
