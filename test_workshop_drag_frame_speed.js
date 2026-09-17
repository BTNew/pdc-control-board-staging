'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
function section(start, end) { return source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start))); }

function frames() {
  let id = 0; const pending = new Map();
  return { requestAnimationFrame: fn => { pending.set(++id, fn); return id; }, cancelAnimationFrame: key => pending.delete(key),
    tick() { const callbacks = [...pending.values()]; pending.clear(); callbacks.forEach(fn => fn()); }, get size() { return pending.size; } };
}
function laneFixture(bay = 1, vertical = false) {
  const counts = { geometry: 0, styles: 0, labels: 0 }; const styles = new Map(); const classes = new Set(); const listeners = new Map();
  const pill = { label: '', setAttribute(name, value) { this.label = value; counts.labels++; }, removeAttribute() { this.label = ''; } };
  const preview = { hidden: true, classList: { contains: name => name === 'is-vertical' && vertical },
    style: { setProperty(name, value) { styles.set(name, value); counts.styles++; }, removeProperty(name) { styles.delete(name); } }, querySelector: () => pill };
  const lane = { isConnected: true, dataset: vertical ? { workshopWeekDropStage: 'FITTING', workshopWeekDropBay: String(bay), workshopWeekDropDate: '2026-09-17' } : { workshopDropStage: 'FITTING', workshopDropBay: String(bay) },
    rect: { left: 100, top: 20, width: 600, height: 600 }, getBoundingClientRect() { counts.geometry++; return this.rect; },
    querySelector: () => preview, querySelectorAll: selector => selector.includes('drop-preview') ? [preview] : [lane],
    contains: node => node === lane, closest: () => lane,
    classList: { add: value => classes.add(value), remove: value => classes.delete(value) },
    addEventListener: (name, fn) => listeners.set(name, fn) };
  return { lane, counts, styles, preview, pill, listeners, fire(name, event = {}) { return listeners.get(name)({ preventDefault() {}, ...event }); } };
}
function fixture() {
  const raf = frames(); const lanes = Array.from({ length: 43 }, (_, i) => laneFixture(i + 1)); const saves = [];
  const root = { querySelectorAll: selector => lanes.flatMap(f => f.lane.querySelectorAll(selector)), contains: lane => lanes.some(f => f.lane === lane) };
  const c = { app: {}, window: raf, document: root, WORKSHOP_PLANNER_CONFIG: { dayLengthMinutes: 600 },
    workshopClampStartMinutes: value => Math.max(0, Math.min(599, Math.round(value))), workshopDefaultBookingHours: () => 1,
    workshopBayAllocatedHours: (stage, bay, hours) => hours * (bay === 2 ? 2 : 1), workshopBookingDestinationHours: (entry, stage, bay, hours) => hours,
    workshopState: () => ({ date: '2026-09-17' }), workshopTimeLabelFromMinutes: value => `minute ${value}`,
    moveWorkshopDroppedPlan: (...args) => saves.push(args), scheduleWorkshopVehicle: value => saves.push(value),
    workshopLoadAdminBlocks: () => [], workshopCreatePaletteAdminBlock: (...args) => saves.push(args) };
  vm.createContext(c);
  vm.runInContext(section('function workshopCurrentDragPreview()', 'function workshopProgressSummary(') +
    section('function bindWorkshopLane(', 'async function saveWorkshopBayMechanic('), c);
  c.workshopSetDragPreview({ type: 'queue', hours: 1 });
  return { c, raf, lanes, root, saves };
}
const transfer = { getData: key => key === 'application/x-workshop-plan-id' ? 'booking-1' : '' };

test('native drag bursts do one geometry read per frame and unchanged minute does not repaint', () => {
  const f = fixture(); const lane = f.lanes[0]; f.c.bindWorkshopLane(lane.lane);
  for (let i = 0; i < 240; i++) lane.fire('dragover', { clientX: 150 + i / 1000, clientY: 30 });
  assert.equal(f.raf.size, 1); assert.equal(lane.counts.geometry, 0);
  f.raf.tick(); assert.equal(lane.counts.geometry, 1); assert.equal(lane.counts.styles, 2); assert.equal(lane.pill.label, 'minute 50 · 1h');
  lane.fire('dragover', { clientX: 150.25, clientY: 30 }); f.raf.tick();
  assert.equal(lane.counts.geometry, 2); assert.equal(lane.counts.styles, 2); assert.equal(lane.counts.labels, 1);
});

test('drop before a paint saves final release coordinates once through the existing move path', () => {
  const f = fixture(); const lane = f.lanes[0]; f.c.bindWorkshopLane(lane.lane);
  lane.fire('dragover', { clientX: 150, clientY: 30 });
  lane.fire('drop', { clientX: 250, clientY: 30, dataTransfer: transfer });
  assert.equal(f.raf.size, 0); assert.equal(f.saves.length, 1); assert.equal(f.saves[0][4], 150);
  assert.equal(lane.preview.hidden, true); f.raf.tick(); assert.equal(lane.preview.hidden, true);
});

test('preview uses current scrolling geometry and destination efficiency', () => {
  const f = fixture(); const lane = f.lanes[1]; f.c.bindWorkshopLane(lane.lane);
  lane.fire('dragover', { clientX: 250, clientY: 30 }); lane.lane.rect.left = 200; f.raf.tick();
  assert.equal(lane.lane.dataset.workshopRequestedStartMinutes, '50'); assert.equal(lane.pill.label, 'minute 50 · 2h');
  assert.equal(lane.styles.get('--drop-preview-width'), '20%');
});

test('leaving, clearing, ending or disconnecting a drag cannot paint a stale lane', () => {
  for (const action of ['leave', 'clear', 'end', 'disconnect']) {
    const f = fixture(); const lane = f.lanes[0]; f.c.bindWorkshopLane(lane.lane);
    lane.fire('dragover', { clientX: 250, clientY: 30 });
    if (action === 'leave') lane.fire('dragleave', { relatedTarget: null });
    if (action === 'clear') f.c.workshopClearLanePreviews(f.root);
    if (action === 'end') f.c.workshopSetDragPreview(null);
    if (action === 'disconnect') lane.lane.isConnected = false;
    f.raf.tick(); assert.equal(lane.preview.hidden, true, action); assert.equal(lane.counts.geometry, 0, action);
  }
});

test('switching bays in one frame only paints the current bay and retains its destination', () => {
  const f = fixture(); const first = f.lanes[0], second = f.lanes[1];
  [first, second].forEach(lane => f.c.bindWorkshopLane(lane.lane));
  first.fire('dragover', { clientX: 200, clientY: 30 });
  second.fire('dragover', { clientX: 300, clientY: 30 });
  first.fire('dragleave', { relatedTarget: second.lane }); f.raf.tick();
  assert.equal(first.counts.geometry, 0); assert.equal(second.counts.geometry, 1);
  assert.equal(f.c.workshopCurrentDropTarget().bay, 2); assert.equal(f.c.workshopCurrentDropTarget().startMinutes, 200);
});

test('weekly vertical preview coalesces and final release follows the vertical coordinate', () => {
  const f = fixture(); const lane = laneFixture(1, true);
  const weeklyStart = source.indexOf("overlay.querySelectorAll('[data-workshop-week-drop-date]').forEach");
  const weeklyEnd = source.indexOf("overlay.querySelectorAll('[data-workshop-job-vehicle]')", weeklyStart);
  Object.assign(f.c, { overlay: { querySelectorAll: () => [lane.lane] }, normalizedStage: 'FITTING', bay: 1,
    weekStart: '2026-09-14', workshopDateKey: value => value, moveWorkshopWeeklyPlan: (...args) => f.saves.push(args) });
  vm.runInContext(source.slice(weeklyStart, weeklyEnd), f.c);
  lane.fire('dragover', { clientX: 0, clientY: 80 }); lane.fire('dragover', { clientX: 0, clientY: 100 }); f.raf.tick();
  assert.equal(lane.counts.geometry, 1); assert.equal(lane.styles.get('--drop-preview-top'), `${80 / 600 * 100}%`);
  lane.fire('drop', { clientX: 0, clientY: 200, dataTransfer: transfer });
  assert.equal(f.saves[0][4], 180); assert.equal(f.raf.size, 0);
});

function touchFixture() {
  const f = fixture(), cardListeners = new Map(), windowListeners = new Map(); let hits = 0;
  const card = { dataset: { workshopVehicleKey: 'vehicle-1' }, getAttribute: () => null,
    addEventListener: (name, fn) => cardListeners.set(name, fn), removeEventListener: name => cardListeners.delete(name),
    setPointerCapture() {}, hasPointerCapture: () => false };
  Object.assign(f.c.window, { addEventListener: (name, fn) => windowListeners.set(name, fn), removeEventListener: name => windowListeners.delete(name) });
  Object.assign(f.c.document, { elementFromPoint(x, y) { hits++; return y < 0 ? null : f.lanes[y >= 100 ? 1 : 0].lane; } });
  Object.assign(f.c, { card, root: f.root, workshopVehicle: () => ({ id: 'vehicle-1' }), workshopSchedulingDuration: () => ({ hours: 1 }) });
  const start = source.indexOf("card.addEventListener('pointerdown', downEvent => {");
  const end = source.indexOf("\n  });\n  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragend'", start);
  vm.runInContext('let workshopActiveQueuePointerDrag = null, workshopSuppressMouseDragUntil = 0;' + source.slice(start, end), f.c);
  cardListeners.get('pointerdown')({ pointerType: 'touch', pointerId: 4, clientX: 110, clientY: 30, target: { closest: () => null } });
  return { ...f, cardListeners, windowListeners, get hits() { return hits; }, fire(name, values = {}) { return windowListeners.get(name)({ pointerId: 4, preventDefault() {}, ...values }); } };
}

test('touch drag batches hit tests and releases into the final bay before its pending frame', () => {
  const f = touchFixture();
  f.fire('pointermove', { clientX: 112, clientY: 30 }); assert.equal(f.raf.size, 0, 'small movement remains normal scrolling/tapping');
  for (let i = 0; i < 100; i++) f.fire('pointermove', { clientX: 150 + i / 10, clientY: 30 });
  assert.equal(f.hits, 0); f.raf.tick(); assert.equal(f.hits, 1);
  f.fire('pointermove', { clientX: 250, clientY: 30 });
  f.fire('pointerup', { clientX: 300, clientY: 150 });
  assert.equal(f.raf.size, 0); assert.equal(f.saves.length, 1); assert.equal(f.saves[0].bay, 2); assert.equal(f.saves[0].startMinutes, 200);
  assert.equal(f.saves[0].preferRequestedTime, true); assert.equal(f.windowListeners.size, 0);
});

test('touch cancellation and release outside the planner cancel pending work without scheduling', () => {
  for (const action of ['pointercancel', 'outside']) {
    const f = touchFixture(); f.fire('pointermove', { clientX: 160, clientY: 30 });
    if (action === 'pointercancel') f.fire('pointercancel');
    else f.fire('pointerup', { clientX: 160, clientY: -10 });
    f.raf.tick(); assert.equal(f.saves.length, 0); assert.equal(f.raf.size, 0); assert.equal(f.windowListeners.size, 0);
  }
});

function resizeFixture() {
  const raf = frames(), listeners = new Map(), commands = []; let reads = 0, writes = 0, renders = 0;
  const entry = { id: 'a', sharedBookingId: 'a', sharedVersion: 5, hours: 1, scheduledDurationMinutes: 60, startAt: '2026-09-17T00:00:00Z', stage: 'FITTING', bay: 1 };
  const chip = { isConnected: true, dataset: {}, style: { setProperty() { writes++; } } };
  const lane = { isConnected: true, getBoundingClientRect: () => { reads++; return { width: 600 }; } };
  const c = { window: raf, document: { addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name) },
    workshopLoadPlans: () => [entry], workshopState: () => ({ date: '2026-09-17' }), workshopEntrySegmentForDate: () => ({ start: 0 }),
    workshopSnapMinutes: Math.round, WORKSHOP_PLANNER_CONFIG: { dayLengthMinutes: 600 }, renderWorkshopPlanner: () => renders++,
    nowIsoString: () => '2026-09-17T01:00:00Z', workshopRequireSchedulableCandidate: () => true, workshopConfirmOtherDepartmentPlans: () => true,
    workshopSharedModeActive: () => true, workshopExactDurationHours: value => value, workshopExactDurationMinutesFromHours: value => Math.round(value * 60),
    workshopDispatchSharedAction: async (...args) => commands.push(args) };
  vm.createContext(c); vm.runInContext('let workshopActivePointerResize = null;' + section('function startWorkshopResize(', 'function workshopWeeklyCardHtml('), c);
  c.startWorkshopResize({ dataset: { workshopResizePlan: 'a' }, closest: selector => selector.includes('plan-id') ? chip : lane },
    { pointerId: 7, clientX: 0, preventDefault() {}, stopPropagation() {} });
  return { c, raf, listeners, chip, commands, get reads() { return reads; }, get writes() { return writes; }, get renders() { return renders; } };
}

test('resize coalesces bursts, ignores unrelated pointers and saves the release size with authoritative version', async () => {
  const f = resizeFixture();
  f.listeners.get('pointermove')({ pointerId: 8, clientX: 500 }); assert.equal(f.raf.size, 0);
  for (let i = 0; i < 200; i++) f.listeners.get('pointermove')({ pointerId: 7, clientX: i / 10 });
  assert.equal(f.reads, 0); f.raf.tick(); assert.equal(f.reads, 1); assert.equal(f.writes, 1);
  await f.listeners.get('pointerup')({ pointerId: 8, clientX: 400 }); assert.equal(f.commands.length, 0);
  f.listeners.get('pointermove')({ pointerId: 7, clientX: 40 });
  await f.listeners.get('pointerup')({ pointerId: 7, clientX: 60 });
  assert.equal(f.raf.size, 0); assert.equal(f.listeners.size, 0); assert.equal(f.commands.length, 1);
  assert.equal(f.commands[0][0], 'cascadeSchedule'); assert.equal(f.commands[0][1].durationMinutes, 120);
  assert.equal(f.commands[0][1].shiftMinutes, 60); assert.equal(f.commands[0][1].targetExpectedVersion, 5);
});

test('resize shortening keeps ordinary resize validation and cancellation never dispatches', async () => {
  const f = resizeFixture(); await f.listeners.get('pointerup')({ pointerId: 7, clientX: -30 });
  assert.equal(f.commands[0][0], 'resizeBooking'); assert.equal(f.commands[0][1].durationMinutes, 30);
  const cancelled = resizeFixture(); cancelled.listeners.get('pointermove')({ pointerId: 7, clientX: 50 });
  cancelled.listeners.get('pointercancel')({ type: 'pointercancel', pointerId: 8 });
  assert.equal(cancelled.raf.size, 1, 'an unrelated touch must not cancel the active resize');
  cancelled.listeners.get('pointercancel')({ type: 'pointercancel', pointerId: 7 }); cancelled.raf.tick();
  assert.equal(cancelled.reads, 0); assert.equal(cancelled.writes, 0); assert.equal(cancelled.commands.length, 0);
  assert.equal(cancelled.listeners.size, 0); assert.equal(cancelled.renders, 1);
});

test('43-bay synthetic high-rate drag reduces geometry reads by 75% while preserving every frame target', () => {
  const f = fixture(); f.lanes.forEach(lane => f.c.bindWorkshopLane(lane.lane));
  const frameCount = 240;
  for (let frame = 0; frame < frameCount; frame++) {
    const lane = f.lanes[Math.floor(frame / 6) % f.lanes.length];
    for (let event = 0; event < 4; event++) lane.fire('dragover', { clientX: 100 + frame + event / 10, clientY: 30 });
    f.raf.tick(); assert.equal(f.c.workshopCurrentDropTarget().startMinutes, frame);
  }
  const reads = f.lanes.reduce((sum, lane) => sum + lane.counts.geometry, 0);
  const writes = f.lanes.reduce((sum, lane) => sum + lane.counts.styles + lane.counts.labels, 0);
  assert.equal(reads, frameCount); assert.equal(writes, frameCount * 3);
  console.log(`Planner drag fixture: 43 bays, 960 pointer events; geometry reads 960 -> ${reads}, visual writes 2880 -> ${writes}.`);
});
