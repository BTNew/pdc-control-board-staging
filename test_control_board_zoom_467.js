'use strict';
// r467 (F80): control board overview zoom levels (Day default, Week, Month), saved
// per user per device. Display only.
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
  const bay = value.board.bays[0];
  value.board.bookings.push(fixture.booking(1, bay, undefined, { scheduled_start_at: stamp('2026-10-22', '09:00'), scheduled_end_at: stamp('2026-10-23', '11:00') }));
  value.board.bookings.push(fixture.booking(2, bay, undefined, { scheduled_start_at: stamp('2026-11-16', '07:00'), scheduled_end_at: stamp('2026-11-16', '15:00') }));
  return value;
}
const opts = { startDate: '2026-10-22', dayCount: 14, now: stamp('2026-10-22', '07:00') };
const jobs = markup => markup.match(/<button type="button" class="control-board-timeline-job[^>]*>[\s\S]*?<\/button>/g) || [];
const attr = (tag, name) => (new RegExp(`${name}="([^"]*)"`).exec(tag) || [])[1];
function fakeScope(userId) {
  const store = new Map();
  return { PDC_AUTH_CONTEXT: { userId }, localStorage: { getItem: k => store.has(k) ? store.get(k) : null, setItem: (k, v) => store.set(k, String(v)) }, store };
}

test('levels: Day is today, Week and Month squeeze more days and load at least 14 / 31 days', () => {
  const model = overview.buildModel(snapshot());
  const day = overview.buildTimeline(model, opts), dflt = overview.buildTimeline(model, { ...opts, zoom: undefined });
  const week = overview.buildTimeline(model, { ...opts, zoom: 'week' }), month = overview.buildTimeline(model, { ...opts, zoom: 'month' });
  assert.deepEqual(overview.ZOOM_LEVELS, ['day', 'week', 'month']);
  assert.equal(day.zoom, 'day'); assert.equal(dflt.zoom, 'day');
  assert.equal(day.dayWidth, 672); assert.equal(day.dayCount, 14);
  assert.equal(week.dayWidth, 150); assert.equal(week.dayCount, 14);
  assert.equal(month.dayWidth, 34); assert.equal(month.dayCount, 31);
  assert.equal(overview.buildTimeline(model, { ...opts, dayCount: 42, zoom: 'month' }).dayCount, 42, 'More days still adds days');
  assert.equal(overview.buildTimeline(model, { ...opts, zoom: 'bogus' }).zoom, 'day');
  assert.equal(day.outside.length, 1, 'Day: the 16 Nov booking is outside these dates');
  assert.equal(month.outside.length, 0, 'Month: the same read shows it');
  assert.deepEqual(day.rows.map(r => r.segments.length), month.rows.map(r => r.segments.length).map((n, i) => i === 0 ? n - 1 : n), 'same per-day pieces, plus the later booking');
});

test('default unchanged: Day markup equals the explicit Day markup and has no zoom classes', () => {
  const model = overview.buildModel(snapshot());
  const a = overview.render(model, opts), b = overview.render(model, { ...opts, zoom: 'day' });
  assert.equal(a, b);
  assert.doesNotMatch(a, /is-zoom-|is-zoom-block/);
  assert.match(a, /control-board-time-ticks"><span/);
  assert.match(a, /<button type="button" data-control-board-zoom="week" title="Zoom out[^"]*">− Zoom out<\/button>/);
  assert.match(a, /data-control-board-zoom="day" aria-pressed="true" class="is-active">Day</);
  assert.match(a, /data-control-board-zoom="day" disabled title="Zoom in[^"]*">Zoom in \+</);
  assert.match(a, /data-control-board-more[^>]*>More days →<\/button><span class="control-board-zoom"/);
});

test('Month is slimline: coloured blocks, no inline text, hover title Key + JC + customer and never Stock', () => {
  const markup = overview.render(overview.buildModel(snapshot()), { ...opts, zoom: 'month' });
  assert.match(markup, /class="control-board-timeline-shell is-zoom-month"/);
  assert.match(markup, /--hour-width:34px/);
  assert.doesNotMatch(markup, /control-board-time-ticks"><span/);
  const tags = jobs(markup);
  assert.equal(tags.length, 2);
  for (const tag of tags) {
    assert.match(tag, /is-zoom-block/);
    assert.match(tag, /><\/button>$/, 'no inline text');
    const title = attr(tag, 'title');
    assert.match(title, /^Key \d+ · JC DEMO-JC-\d+ · Demonstration customer \d+\n/);
    assert.doesNotMatch(title + attr(tag, 'aria-label'), /Stock|DEMO-\d{4}/);
  }
  assert.match(attr(tags[0], 'title'), /Planned · 2026-10-22 to 2026-10-23$/);
  assert.match(markup, /--row-height:22px/);
  assert.match(markup, /data-control-board-zoom="month" disabled[^>]*>− Zoom out/);
});

test('Week keeps the Day bar markup (labels from the bar renderer) with ticks hidden', () => {
  const markup = overview.render(overview.buildModel(snapshot()), { ...opts, zoom: 'week' });
  assert.match(markup, /is-zoom-week/);
  assert.doesNotMatch(markup, /is-zoom-block/);
  assert.match(jobs(markup)[0], /<strong>Key 101 · JC DEMO-JC-1/);
});

test('persistence: per user per device, falls back to Day without storage', () => {
  const a = fakeScope('user-a'), b = fakeScope('user-b');
  assert.equal(overview.getZoom(a), 'day');
  assert.equal(overview.setZoom('month', a), 'month');
  assert.equal(overview.getZoom(a), 'month');
  assert.deepEqual([...a.store.keys()], ['pdc.control-board-zoom.v1:user-a']);
  assert.equal(overview.getZoom(b), 'day', 'another user on the device keeps their own level');
  overview.setZoom('nonsense', a);
  assert.equal(overview.getZoom(a), 'day');
  assert.equal(overview.getZoom({}), 'day');
  assert.equal(overview.getZoom({ get localStorage() { throw new Error('blocked'); } }), 'day');
  assert.equal(overview.getZoom(null), 'day');
});

test('zoom buttons are handled in mountTimeline and redraw through renderWorkflowBoard; no data writes', () => {
  const src = fs.readFileSync(require.resolve('./control-board-overview.js'), 'utf8');
  assert.match(src, /host\.addEventListener\?\.\('click', zoomClick\)/);
  assert.match(src, /host\.removeEventListener\?\.\('click', zoomClick\)/);
  assert.match(src, /view\.renderWorkflowBoard\(\)/);
  assert.doesNotMatch(src, /\.rpc\(|fetch\(|draggable/);
  const index = fs.readFileSync(require.resolve('./index.html'), 'utf8');
  assert.match(index, /control-board-overview\.js\?[^"]*r467=2026\.10\.22\.r467/);
  assert.match(index, /<link rel="stylesheet" href="control-board-zoom\.css\?control-board-zoom=2026\.10\.22\.r467">/);
  const css = fs.readFileSync(require.resolve('./control-board-zoom.css'), 'utf8');
  assert.match(css, /is-zoom-month \.control-board-timeline-job \{ height:10px/);
  assert.match(fs.readFileSync(require.resolve('./scripts/build_pages_runtime.js'), 'utf8'), /'control-board-zoom\.css'/);
});
