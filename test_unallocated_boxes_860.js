'use strict';
// r860 (F410, Craig 30 Oct 2026): every station's Unallocated list is two boxes,
// At PMB (longest at PMB first) and In transit / Yard hold (IT by Kewdale ETA, then YH).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

function fn(name) {
  const start = planner.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  const end = planner.indexOf('\nfunction ', start + 1);
  return planner.slice(start, end);
}

function context(extra = {}) {
  const ctx = {
    String, Number, Math, Date, Array, Set, Map, Infinity, Object,
    cleanNavisionText: value => String(value ?? '').trim(),
    escapeHtml: value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    vehicleKey: vehicle => vehicle.stock,
    WORKSHOP_INCREMENTAL_RENDER_BATCH: 40,
    workshopReturnedQueueCardHtml: () => '<article class="returned"></article>',
    workshopQueueCardHtml: vehicle => `<article data-stock="${vehicle.stock}"><span>x</span><div class="workshop-queue-actions"></div></article>`,
    pmbArrivalAgeTimestamp: vehicle => vehicle.keyAt || '',
    ...extra,
  };
  vm.createContext(ctx);
  for (const name of ['workshopDateKey', 'workshopValidDateKey', 'workshopVehiclePlanningLocation', 'workshopUnallocatedGroup',
    'workshopKewdaleEtaDateKey', 'workshopDaysUntilDateKey', 'workshopPmbSinceMs', 'workshopUnallocatedLocationLabel',
    'workshopUnallocatedGroups', 'workshopQueueCardWithLocationHtml', 'workshopIncrementalRenderRows',
    'workshopIncrementalLoadMoreHtml', 'workshopUnallocatedBoxesHtml']) vm.runInContext(fn(name), ctx);
  ctx.statusCategory = () => '';
  return ctx;
}

const now = new Date('2026-10-30T03:00:00Z'); // 11:00 Perth
const cars = [
  { stock: 'YH1', currentLocation: 'YH' },
  { stock: 'IT9', currentLocation: 'IT', navisionKewdaleEta: '08/11/2026' },
  { stock: 'K281', keyNumber: '281', currentLocation: 'PMB', keyAt: '2026-10-27T01:00:00Z' },
  { stock: 'OTH', currentLocation: 'Other' },
  { stock: 'IT2', currentLocation: 'IT', navisionKewdaleEta: '01/11/2026' },
  { stock: 'K13', keyNumber: '13', currentLocation: 'PMB', keyAt: '2026-10-20T01:00:00Z' },
  { stock: 'ITX', currentLocation: 'IT' },
  { stock: 'QC1', keyNumber: '315', currentLocation: 'QC', keyAt: '2026-10-25T01:00:00Z' },
];

test('cars split into At PMB (longest first) and In transit / Yard hold (soonest ETA, then no ETA, then YH)', () => {
  const ctx = context();
  const groups = ctx.workshopUnallocatedGroups(cars, '', now);
  assert.deepEqual([...groups.pmb].map(v => v.stock), ['K13', 'QC1', 'K281']);
  assert.deepEqual([...groups.incoming].map(v => v.stock), ['IT2', 'IT9', 'ITX', 'YH1']);
  assert.equal(groups.hidden, 1);
});

test('a searched car in Other is still shown so search highlight works', () => {
  const ctx = context();
  const groups = ctx.workshopUnallocatedGroups(cars, 'OTH', now);
  assert.ok(groups.incoming.some(v => v.stock === 'OTH'));
  assert.equal(groups.hidden, 0);
});

test('location line: PMB days, Kewdale countdown, yard hold', () => {
  const ctx = context();
  assert.equal(ctx.workshopUnallocatedLocationLabel(cars[5], 'PMB', now), 'At PMB · 10 days');
  assert.equal(ctx.workshopUnallocatedLocationLabel(cars[4], 'IT', now), 'In transit · Kewdale in 2 days');
  assert.equal(ctx.workshopUnallocatedLocationLabel({ navisionKewdaleEta: '2026-10-30' }, 'IT', now), 'In transit · Kewdale today');
  assert.equal(ctx.workshopUnallocatedLocationLabel({ navisionKewdaleEta: '27/10/2026' }, 'IT', now), 'In transit · Kewdale ETA 3 days ago');
  assert.equal(ctx.workshopUnallocatedLocationLabel({}, 'IT', now), 'In transit · no Kewdale ETA');
  assert.equal(ctx.workshopUnallocatedLocationLabel({}, 'YH', now), 'Yard hold');
});

test('boxes render with counts, location lines sit above the buttons, returned bookings go in At PMB', () => {
  const ctx = context();
  const html = ctx.workshopUnallocatedBoxesHtml({ returnedPlans: [{ id: 'p1' }], queue: cars, stage: 'FABRICATION', dateKey: '2026-10-30', plans: [], limit: 40 });
  assert.match(html, /<strong>At PMB<\/strong><span>4<\/span>/);
  assert.match(html, /<strong>In transit \/ Yard hold<\/strong><span>4<\/span>/);
  assert.match(html, /workshop-unallocated-location is-it">In transit · Kewdale in[^<]*<\/small><div class="workshop-queue-actions">/);
  assert.ok(html.indexOf('class="returned"') < html.indexOf('data-workshop-unallocated-box="incoming"'));
  assert.doesNotMatch(html, /data-stock="OTH"/);
});

test('planner uses the boxes for every station and loads key dates; app re-renders the planner when they land', () => {
  assert.match(planner, /workshopUnallocatedBoxesHtml\(\{ returnedPlans, queue, stage, dateKey, plans, highlightVehicleKey: state\.highlightVehicleKey, limit: state\.incrementalQueueLimit \}\)/);
  assert.match(planner, /if \(!focusedBookingMode && typeof ensurePmbKeyAssigned === 'function'\) ensurePmbKeyAssigned\(\);/);
  assert.match(app, /if \(changed && app\.currentView === 'workshop' && typeof scheduleWorkshopPlannerRender === 'function'\) scheduleWorkshopPlannerRender\(\);/);
  assert.equal((app.match(/r860=2026\.10\.30\.r860`, 'workshop-planner-script'/g) || []).length, 2);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /app\.js\?[^"]*&amp;r860=2026\.10\.30\.r860"/);
  assert.match(html, /workshop-planner\.css\?[^"]*&amp;r860=2026\.10\.30\.r860"/);
  assert.doesNotMatch(html, /^(<<<<<<<|=======|>>>>>>>)/m);
});
