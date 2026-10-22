/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r491 (F104): Sublet page 'Away now' filter and days-away / days-overdue status (offsite tracking).
const test = require('node:test');
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
function between(source, start, end) {
  const a = source.indexOf(start); const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `expected ${start} section`);
  return source.slice(a, b);
}
const helpers = between(app, 'function subletDateOrdinal(', 'function subletCalendarEvents(');
const overdue = between(app, 'function subletIsOverdue(', 'function subletVehicleByKey(');
const away = between(app, 'function subletAwayOnDate(', 'function subletDateChangeError(');

function context(today) {
  const ctx = {
    plainDateValue: value => String(value || '').match(/^(\d{4}-\d{2}-\d{2})/)?.[1] || '',
    displayStockNumber: v => v.stock || '', vehicleKey: v => v.stock || '',
    Intl, Date, Math, Number, String, Array,
  };
  vm.createContext(ctx);
  vm.runInContext(`${helpers}\n${overdue}\n${away}\nsubletTodayDateKey = () => ${JSON.stringify(today)};\nthis.api = { subletDaysAway, subletDaysOverdue, subletStatusText, subletMatchesOperationalFilter, subletBookingState };`, ctx);
  return ctx.api;
}
const TODAY = '2026-10-23';
const out = (o) => Object.assign({ pmbSubletBookingDate: '', pmbSubletExpectedReturnDate: '', pmbSubletActualReturnDate: '' }, o);

test('days away counts from out date to today (Perth) or to the return date', () => {
  const api = context(TODAY);
  assert.strictEqual(api.subletDaysAway(out({ pmbSubletBookingDate: '2026-10-16' })), 7);
  assert.strictEqual(api.subletDaysAway(out({ pmbSubletBookingDate: '2026-10-23' })), 0);
  assert.strictEqual(api.subletDaysAway(out({ pmbSubletBookingDate: '2026-10-01', pmbSubletActualReturnDate: '2026-10-13' })), 12);
  assert.strictEqual(api.subletDaysAway(out({})), null, 'not out yet');
  assert.strictEqual(api.subletDaysAway(out({ pmbSubletBookingDate: '2026-10-30' })), null, 'future out date');
});

test('status text: Away N days, OVERDUE N days, Back · N days, otherwise unchanged labels', () => {
  const api = context(TODAY);
  assert.strictEqual(api.subletStatusText(out({ pmbSubletBookingDate: '2026-10-22', pmbSubletExpectedReturnDate: '2026-10-30' })), 'Away 1 day');
  assert.strictEqual(api.subletStatusText(out({ pmbSubletBookingDate: '2026-10-10', pmbSubletExpectedReturnDate: '2026-10-20' })), 'OVERDUE 3 days');
  assert.strictEqual(api.subletStatusText(out({ pmbSubletBookingDate: '2026-10-01', pmbSubletActualReturnDate: '2026-10-13' })), 'Back · 12 days');
  assert.strictEqual(api.subletStatusText(out({ pmbSubletBookingDate: '2026-11-02' })), 'Sublet Booked');
  assert.strictEqual(api.subletStatusText(out({})), 'Sublet To Book');
  assert.strictEqual(api.subletDaysOverdue(out({ pmbSubletBookingDate: '2026-10-01', pmbSubletExpectedReturnDate: '2026-10-05', pmbSubletActualReturnDate: '2026-10-09' })), 0, 'returned is never overdue');
});

test("'away' filter = booked, out on or before today, not back; existing filters unchanged", () => {
  const api = context(TODAY);
  const awayNow = out({ pmbSubletBookingDate: '2026-10-20' });
  const later = out({ pmbSubletBookingDate: '2026-10-28' });
  const back = out({ pmbSubletBookingDate: '2026-10-01', pmbSubletActualReturnDate: '2026-10-05' });
  const toBook = out({});
  assert.ok(api.subletMatchesOperationalFilter(awayNow, 'away'));
  assert.ok(!api.subletMatchesOperationalFilter(later, 'away'));
  assert.ok(!api.subletMatchesOperationalFilter(back, 'away'));
  assert.ok(!api.subletMatchesOperationalFilter(toBook, 'away'));
  assert.ok(!api.subletMatchesOperationalFilter({ ...awayNow, __subletBookingStatus: 'cancelled' }, 'away'), 'cancelled never away');
  assert.ok(api.subletMatchesOperationalFilter(awayNow, 'booked') && api.subletMatchesOperationalFilter(later, 'booked'));
  assert.ok(api.subletMatchesOperationalFilter(back, 'returned') && api.subletMatchesOperationalFilter(toBook, 'to-book'));
  assert.ok(api.subletMatchesOperationalFilter(toBook, 'nonsense'), 'unknown filter still falls back to to-book');
});

test('page wiring: chip, filter whitelist, longest-away sort, tooltip, read-only (no new writes), cache bust', () => {
  const summary = between(app, 'function renderSubletSummary(', 'function syncSubletProviderFilter(');
  assert.match(summary, /\['away', 'Away now'\]/);
  assert.match(summary, /\['booked', 'away', 'returned'\]\.includes/);
  const render = between(app, 'function renderSubletHome()', 'function getNotes');
  assert.match(render, /\['booked', 'away', 'returned'\]\.includes\(app\.subletOperationalFilter\)/);
  assert.match(render, /app\.subletOperationalFilter === 'away'[\s\S]{0,120}subletDaysAway\(b\)/);
  assert.match(render, /const statusLabel = subletStatusText\(vehicle\)/);
  assert.match(render, /title="\$\{escapeHtml\(statusTitle\)\}"/);
  const added = between(app, '// r491 (F104): whole days', 'function compareSubletBookingDate(');
  assert.doesNotMatch(added, /rpc|fetch\(|saveVehicleEdits|update[A-Z]\w*\(/, 'r491 helpers only read');
  assert.match(index, /app\.js\?[^"]*sublet-away=2026\.10\.23\.r491/);
});
