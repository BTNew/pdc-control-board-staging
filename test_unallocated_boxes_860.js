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
    workshopReturnedQueueCardHtml: entry => `<article class="returned" data-plan="${entry.id}"><div class="workshop-queue-actions"></div></article>`,
    workshopVehicle: key => cars.find(car => car.stock === key) || null,
    workshopQueueCardHtml: vehicle => `<article data-stock="${vehicle.stock}"><span>x</span><div class="workshop-queue-actions"></div></article>`,
    pmbArrivalAgeTimestamp: vehicle => vehicle.keyAt || '',
    ...extra,
  };
  vm.createContext(ctx);
  for (const name of ['workshopDateKey', 'workshopValidDateKey', 'workshopVehiclePlanningLocation', 'workshopUnallocatedGroup',
    'workshopKewdaleEtaDateKey', 'workshopDaysUntilDateKey', 'workshopPmbSinceMs', 'workshopUnallocatedLocationLabel',
    'workshopUnallocatedGroups', 'workshopFullVehicleRow', 'workshopUnallocatedPartsStatus', 'workshopUnallocatedMetaHtml', 'workshopQueueCardWithLocationHtml', 'workshopIncrementalRenderRows',
    'workshopIncrementalLoadMoreHtml', 'workshopReturnedCardWithLocationHtml', 'workshopPmbSortChoice', 'workshopUnallocatedBoxesHtml']) vm.runInContext(fn(name), ctx);
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
  { stock: 'NK1', keyNumber: '—', currentLocation: 'PMB' },
];

test('cars split into At PMB (longest first) and In transit / Yard hold (soonest ETA, then no ETA, then YH)', () => {
  const ctx = context();
  const groups = ctx.workshopUnallocatedGroups(cars, '', now);
  assert.deepEqual([...groups.pmb].map(v => v.stock), ['K13', 'QC1', 'K281']);
  assert.deepEqual([...groups.incoming].map(v => v.stock), ['IT2', 'IT9', 'ITX', 'YH1', 'NK1']);
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
  assert.equal(ctx.workshopUnallocatedLocationLabel({}, 'NOKEY', now), 'No key number');
});

const returnedCars = [
  { stock: 'RK1', keyNumber: '500', currentLocation: 'PMB', keyAt: '2026-10-29T01:00:00Z' },
  { stock: 'RK0', keyNumber: '501', currentLocation: 'PMB', keyAt: '2026-10-10T01:00:00Z' },
  { stock: 'RIT', currentLocation: 'IT', navisionKewdaleEta: '05/11/2026' },
  { stock: 'RNK', currentLocation: 'PMB' },
];

test('boxes: returned bookings go by their own car and are sorted in, not pinned on top (r861, r862)', () => {
  const ctx = context({ workshopVehicle: key => [...cars, ...returnedCars].find(car => car.stock === key) || null });
  const returnedPlans = returnedCars.map(car => ({ id: `r-${car.stock}`, vehicleKey: car.stock }));
  const html = ctx.workshopUnallocatedBoxesHtml({ returnedPlans, queue: cars, stage: 'FITTING', dateKey: '2026-10-30', plans: [], limit: 40 });
  const incomingAt = html.indexOf('data-workshop-unallocated-box="incoming"');
  assert.match(html, /<strong>At PMB<\/strong><span>5<\/span>/);
  assert.match(html, /<strong>In transit \/ Yard hold<\/strong><span>7<\/span>/);
  const order = [...html.slice(0, incomingAt).matchAll(/data-(?:stock|plan)="([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(order, ['r-RK0', 'K13', 'QC1', 'K281', 'r-RK1'], 'longest at PMB first, returned bookings sorted in');
  assert.ok(html.indexOf('data-plan="r-RIT"') > incomingAt);
  assert.ok(html.indexOf('data-plan="r-RNK"') > incomingAt);
  assert.match(html, /data-plan="r-RIT"><div class="workshop-unallocated-meta"><small class="workshop-unallocated-location is-it">In transit · Kewdale in[^<]*<\/small><\/div><div class="workshop-queue-actions">/);
  assert.match(html, /workshop-unallocated-location is-nokey">No key number<\/small>/);
  assert.doesNotMatch(html, /workshop-unallocated-parts/, 'no parts chip when nothing is known');
  assert.doesNotMatch(html, /data-stock="OTH"/);
  assert.match(html, /<select class="workshop-pmb-sort" data-workshop-pmb-sort[^>]*><option value="longest" selected>Longest at PMB first<\/option><option value="newest">Newest at PMB first<\/option><option value="key">Key number<\/option><\/select>/);
});

test('At PMB sort: newest first and key number', () => {
  const ctx = context();
  assert.deepEqual([...ctx.workshopUnallocatedGroups(cars, '', now, 'newest').pmb].map(v => v.stock), ['K281', 'QC1', 'K13']);
  assert.deepEqual([...ctx.workshopUnallocatedGroups(cars, '', now, 'key').pmb].map(v => v.stock), ['K13', 'K281', 'QC1']);
  assert.deepEqual([...ctx.workshopUnallocatedGroups(cars, '', now).pmb].map(v => v.stock), ['K13', 'QC1', 'K281']);
});

test('planner uses the boxes for every station and loads key dates; app re-renders the planner when they land', () => {
  assert.match(planner, /workshopUnallocatedBoxesHtml\(\{ returnedPlans, queue, stage, dateKey, plans, highlightVehicleKey: state\.highlightVehicleKey, limit: state\.incrementalQueueLimit, pmbSort: workshopPmbSortChoice\(\) \}\)/);
  assert.match(planner, /if \(!focusedBookingMode && typeof ensurePmbKeyAssigned === 'function'\) ensurePmbKeyAssigned\(\);/);
  assert.match(app, /if \(changed && app\.currentView === 'workshop' && typeof scheduleWorkshopPlannerRender === 'function'\) scheduleWorkshopPlannerRender\(\);/);
  assert.equal((app.match(/r860=2026\.10\.30\.r860&r861=2026\.10\.30\.r861&r862=2026\.10\.30\.r862&r863=2026\.10\.30\.r863`, 'workshop-planner-script'/g) || []).length, 2);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /app\.js\?[^"]*&amp;r860=2026\.10\.30\.r860&amp;r861=2026\.10\.30\.r861&amp;r862=2026\.10\.30\.r862&amp;r863=2026\.10\.30\.r863"/);
  assert.match(html, /workshop-planner\.css\?[^"]*&amp;r860=2026\.10\.30\.r860&amp;r861=2026\.10\.30\.r861&amp;r862=2026\.10\.30\.r862&amp;r863=2026\.10\.30\.r863"/);
  assert.doesNotMatch(html, /^(<<<<<<<|=======|>>>>>>>)/m);
});

test('r863: one compact parts chip: Stoppage, Parts here, Parts ETA, Parts outstanding', () => {
  const status = {};
  const fullRows = [
    { id: 'p-here', stock: 'S1', pdcPartsFlags: { colour: 'green' } },
    { id: 'p-out', stock: 'S2', pdcPartsFlags: { colour: 'orange' } },
  ];
  const ctx = context({
    app: { emailVehicleLocationRows: fullRows },
    window: { PDC_PARTS_STOPPAGE: { partsStatusFor: v => status[v.id] || { placed: false, partsDone: false, eta: '' } } },
  });
  const chip = v => { const r = ctx.workshopUnallocatedPartsStatus(v); return r ? `${r.kind}|${r.label}` : ''; };
  const plus = n => ctx.workshopDateKey(new Date(Date.now() + n * 86400000));
  status.stop = { placed: true, eta: plus(3) };
  status.eta = { eta: plus(5) };
  status.late = { eta: plus(-2) };
  status.done = { partsDone: true };
  assert.match(chip({ id: 'stop' }), /^stoppage\|Stoppage · \d\d\/\d\d · 3d$/);
  assert.match(chip({ id: 'eta' }), /^eta\|Parts ETA \d\d\/\d\d · 5d$/);
  assert.match(chip({ id: 'late' }), /^late\|Parts ETA \d\d\/\d\d · 2d late$/);
  assert.equal(chip({ id: 'done' }), 'here|Parts here');
  assert.equal(chip({ id: 'x1', stock: 'S1' }), 'here|Parts here', 'flags from the full board row (matched by stock)');
  assert.equal(chip({ id: 'p-out' }), 'out|Parts outstanding');
  assert.equal(chip({ id: 'nothing' }), '');
  const meta = ctx.workshopUnallocatedMetaHtml({ id: 'eta', keyNumber: '9', keyAt: new Date(Date.now() - 2 * 86400000).toISOString() }, 'PMB');
  assert.match(meta, /^<div class="workshop-unallocated-meta"><small class="workshop-unallocated-location is-pmb">At PMB · 2 days<\/small><small class="workshop-unallocated-parts is-eta">Parts ETA [^<]+<\/small><\/div>$/);
});

test('r863: parts stoppage module exposes partsStatusFor and is cache-busted', () => {
  const src = fs.readFileSync('pdc-parts-stoppage.js', 'utf8');
  assert.match(src, /window\.PDC_PARTS_STOPPAGE = Object\.freeze\(\{ VERSION, reload: load, shownEta, plannerSectionHtml, partsStatusFor \}\);/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-parts-stoppage\.js\?[^']*&r863=2026\.10\.30\.r863'/);
});
