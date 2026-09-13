'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const fs = require('node:fs'); const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
const fn = source.slice(source.indexOf('function workshopBookingSearchMeta('), source.indexOf('\nfunction workshopSearchResultsHtml('));
const c = vm.createContext({ parseIsoTimestamp: s => s ? new Date(s) : null, workshopEntryEnd: e => e.endAt ? new Date(e.endAt) : null, pmbStageLabel: s => s, workshopBookingSearchStatus: e => e.status });
vm.runInContext(fn, c);
test('multi-day search explicitly shows finish date across the weekend', () => {
  const m = c.workshopBookingSearchMeta({startAt:'2026-09-18T08:00:00Z', endAt:'2026-09-21T00:00:00Z'});
  assert.equal(m.date, '18/09/2026 → 21/09/2026'); assert.match(m.time, /4:00 pm–8:00 am/);
});
test('Perth same-day booking across UTC midnight retains a single date', () => {
  const m = c.workshopBookingSearchMeta({startAt:'2026-09-13T23:00:00Z', endAt:'2026-09-14T08:00:00Z'});
  assert.equal(m.date, '14/09/2026'); assert.equal(m.time, '7:00 am–4:00 pm');
});
test('missing dates remain clearly unavailable', () => {
  const m = c.workshopBookingSearchMeta({}); assert.equal(m.date, 'Unknown date'); assert.equal(m.time, 'Unknown time');
});
