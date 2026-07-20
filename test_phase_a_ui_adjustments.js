'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const plannerCss = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');

assert.ok(planner.includes('WORKSHOP_DETAIL_SESSION_KEY'), 'Job Details preference must use browser-session storage');
assert.ok(planner.includes('data-workshop-detail-toggle'), 'Job Details needs an accessible expand/collapse control');
assert.ok(planner.includes('data-workshop-detail-pin'), 'Job Details needs a session-scoped pin control');
assert.ok(planner.includes('workshop-detail-panel is-collapsed'), 'Empty Job Details must render in the compact collapsed state');
assert.ok(planner.includes('workshop-detail-panel is-expanded'), 'Selected booking Job Details must render expanded');
assert.ok(plannerCss.includes('min-height: 40px'), 'Collapsed Job Details target height must remain within 36–44px');
assert.ok(plannerCss.includes('.workshop-detail-panel.is-collapsed .workshop-detail-content'), 'Collapsed details must remove blank content height');

for (const field of ['Key', 'Stock', 'JC', 'Customer', 'Vehicle', 'Station', 'Bay', 'Date', 'Time', 'Status']) {
  assert.ok(planner.includes(field), `Planner search result is missing ${field}`);
}
assert.ok(planner.includes('function workshopSearchMatches('), 'Planner needs explicit deterministic search results');
assert.ok(planner.includes('function workshopSelectSearchBooking('), 'Planner result selection must use stable booking identity');
assert.ok(planner.includes('data-workshop-search-booking-id'), 'Search selection must preserve booking UUID/id');
assert.ok(planner.includes('data-workshop-search-vehicle-identity'), 'Search selection must preserve canonical shared or local vehicle identity');
assert.ok(planner.includes('This vehicle has ${bookings.length} bookings. Showing the selected booking.'), 'Multiple bookings need an explicit selected-booking prompt');
assert.ok(planner.includes('Previous booking') && planner.includes('Next booking'), 'Multiple booking navigation controls are required');
assert.ok(planner.includes('workshopSortBookingsClosest'), 'Closest booking selection must be deterministic');
assert.ok(planner.includes("event.key === 'Escape'"), 'Planner search result overlay must close on Escape');
assert.ok(planner.includes('window.clearTimeout(app.workshopPlannerSearchTimer);'), 'Selecting a result must cancel the pending debounce so the overlay stays closed');
assert.ok(plannerCss.includes('.workshop-plan-chip.is-search-match'), 'Selected search booking must retain a visible pulse/highlight');

const detailStart = app.indexOf('function renderDetail()');
const detailEnd = app.indexOf('function saveVehicleEditsFromModal', detailStart);
const detailSection = app.slice(detailStart, detailEnd > detailStart ? detailEnd : app.length);
assert.ok(!detailSection.includes('${actionSelectHtml(key)}'), 'Vehicle detail must not render Select Action');
assert.ok(!detailSection.includes("$('[data-action-stock]', panel)"), 'Vehicle detail must not retain an obsolete Select Action listener');
assert.ok(app.includes('function actionSelectHtml('), 'Underlying actions used by other screens must remain available');

const etaCell = app.match(/<div class="parts-worst-eta-wrap">[\s\S]*?<\/td>/)?.[0] || '';
assert.ok(!etaCell.includes('data-parts-eta-email'), 'Email Sales must not remain inside the ETA cell');
assert.ok(app.includes('parts-email-sales-secondary'), 'Email Sales must move to a compact secondary action line');
assert.ok(app.includes('data-parts-more-button'), 'Parts More action must use an overlay trigger');
assert.ok(app.includes('function openPartsMoreMenu('), 'Parts More overlay positioning helper is missing');
assert.ok(app.includes('role="group"'), 'Parts More overlay must expose a labelled native-button group without incomplete ARIA menu semantics');
assert.ok(app.includes("event.key === 'Escape'"), 'Parts More overlay must close on Escape');
assert.ok(app.includes("document.addEventListener('pointerdown'"), 'Parts More overlay must close on outside click');
assert.ok(app.includes("document.addEventListener('focusin'"), 'Parts More overlay must close when keyboard focus leaves it');
assert.ok(app.includes("classList.toggle('opens-upward'"), 'Parts More overlay must open upward near the viewport bottom');
assert.ok(styles.includes('.parts-more-popover'), 'Parts More popover styles are missing');
assert.ok(styles.includes('position: fixed'), 'Parts More menu must be outside table flow');
assert.ok(styles.includes('.parts-queue-table th:nth-child(6)'), 'JITA requires a narrow explicit column rule');
assert.ok(styles.includes('width: 44px'), 'JITA compact target width is missing');
assert.ok(styles.includes('.parts-queue-row > td') && styles.includes('padding: 5px 6px'), 'Parts rows need materially reduced cell padding');

for (const selector of ['.incoming-work-transfer', 'select[name="pdcLocation"]', '[data-pmb-bay-provider-key]', '[data-sublet-field="pmbSubletProvider"]']) {
  assert.ok(styles.includes(selector), `Transfer selector contrast coverage missing: ${selector}`);
}
assert.ok(styles.includes('color: #0f172a') && styles.includes('background: #fff'), 'Transfer options need readable normal-state contrast');
assert.ok(styles.includes('option:disabled'), 'Transfer selectors need an explicit disabled option state');

global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
const plannerApi = require('./workshop-planner.js');
const now = new Date('2026-07-20T10:00:00+08:00').getTime();
const ordered = plannerApi.workshopSortBookingsClosest([
  { id: 'future-far', startAt: '2026-07-22T09:00:00+08:00', hours: 1 },
  { id: 'future-near', startAt: '2026-07-20T11:00:00+08:00', hours: 1 },
  { id: 'past-near', startAt: '2026-07-20T09:30:00+08:00', hours: 1 },
], now);
assert.deepStrictEqual(ordered.map(row => row.id), ['past-near', 'future-near', 'future-far'], 'Multiple bookings must select the one closest to the current date/time deterministically');
const tied = plannerApi.workshopSortBookingsClosest([
  { id: 'b', startAt: '2026-07-20T09:00:00+08:00', hours: 1 },
  { id: 'a', startAt: '2026-07-20T11:00:00+08:00', hours: 1 },
], now);
assert.deepStrictEqual(tied.map(row => row.id), ['b', 'a'], 'Equal-distance bookings must use start time then booking id as deterministic tie-breakers');

const sharedBookings = [
  { id: 'closest', sharedVehicleId: 'vehicle-a', vehicleKey: 'DUPLICATE', startAt: '2026-07-20T10:15:00+08:00' },
  { id: 'clicked', sharedVehicleId: 'vehicle-a', vehicleKey: 'DUPLICATE', startAt: '2026-07-22T09:00:00+08:00' },
  { id: 'other-vehicle', sharedVehicleId: 'vehicle-b', vehicleKey: 'DUPLICATE', startAt: '2026-07-20T10:05:00+08:00' },
];
assert.strictEqual(plannerApi.workshopResolveBookingSelection(sharedBookings, 'clicked', 'shared:vehicle-a')?.id, 'clicked', 'Clicking a non-closest result must preserve that exact booking UUID');
assert.deepStrictEqual(plannerApi.workshopBookingsForEntry(sharedBookings, sharedBookings[0]).map(row => row.id), ['closest', 'clicked'], 'Duplicate legacy keys must not merge different shared vehicle UUIDs');
assert.strictEqual(plannerApi.workshopResolveBookingSelection(sharedBookings, 'clicked', 'shared:vehicle-b'), null, 'A booking/vehicle UUID mismatch must fail closed');
assert.strictEqual(plannerApi.workshopResolveBookingSelection([...sharedBookings, { ...sharedBookings[1] }], 'clicked', 'shared:vehicle-a'), null, 'Duplicate booking IDs must fail closed');
assert.deepStrictEqual(plannerApi.workshopSortBookingsClosest([
  { id: 'invalid', startAt: 'not-a-date' },
  { id: 'valid', startAt: '2026-07-20T12:00:00+08:00' },
], now).map(row => row.id), ['valid', 'invalid'], 'Malformed booking dates must sort after valid bookings rather than becoming closest');
assert.strictEqual(plannerApi.workshopResolveBookingSelection([{ id: 'invalid', vehicleKey: 'LOCAL', startAt: '' }], 'invalid', 'legacy:LOCAL'), null, 'Malformed booking dates must not become an operational selection');

console.log('Phase A UI adjustment regression contracts passed.');
