'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function fn(name) {
  const start = source.indexOf(`async function ${name}(`);
  const next = source.slice(start + 1).search(/\n(?:async )?function /);
  return source.slice(start, start + 1 + next);
}
const handlers = [
  ['markVehiclePartsOrdered', 'markPartsOrdered'], ['markVehiclePartsComplete', 'markPartsComplete'],
  ['markVehiclePartsStoppage', 'setPartsStoppage'], ['updateVehiclePartsWorstEta', 'updatePartsEta'],
  ['clearVehiclePartsStoppage', 'setPartsStoppage'],
];
function harness() {
  const events = new Map(), calls = [], row = { stock: 'SYNTHETIC', __emailVehicleVersion: 1, pdcPartsWorstEta: '2026-09-15' };
  const service = Object.fromEntries(handlers.map(([, method]) => [method, async () => { calls.push(method); return { ok: true }; }]));
  const target = { service, vehicle: row, vehicleId: 'fixture', expectedVersion: 1 };
  const ctx = { Map, Set, Promise, window: { PDC_AUTH_CONTEXT: { userId: 'operator-a', role: 'operator' },
      prompt: () => 'Test reason', alert: message => calls.push(`alert:${message}`),
      addEventListener: (name, callback) => { if (!events.has(name)) events.set(name, []); events.get(name).push(callback); } },
    app: {}, crypto: { randomUUID: () => 'test-request' }, selectedVehicle: () => row,
    vehicleLifecycleSharedModeActive: () => true, authenticatedPartsTarget: async () => target,
    cleanNavisionText: value => value, getCurrentOperatorName: () => 'Test operator',
    partsStoppageReason: () => 'Test stoppage', partsWorstEtaValue: v => v.pdcPartsWorstEta,
    partsHasValidAuthoritativeEta: () => true, partsOrdered: () => true,
    refreshEmailVehicleLocations: async () => true, refreshSharedVehicleWorkState: async () => true,
    renderPartsHome() {}, offerSalespersonChangeEmail: () => calls.push('email-draft'),
  };
  vm.createContext(ctx);
  vm.runInContext(source.slice(source.indexOf('const qcPhotoEvidence = new Map();'), source.indexOf('function qcPageIsMobile()')), ctx);
  for (const [name] of handlers) vm.runInContext(fn(name), ctx);
  const replaceSession = (actor = 'operator-b') => {
    delete ctx.window.PDC_AUTH_CONTEXT;
    for (const callback of events.get('pdc-auth-locked') || []) callback({ detail: { reason: 'session-revalidate' } });
    ctx.window.PDC_AUTH_CONTEXT = { userId: actor, role: 'operator' };
    for (const callback of events.get('pdc-auth-ready') || []) callback({});
  };
  return { ctx, target, row, service, calls, replaceSession };
}
for (const [name] of handlers) {
  test(`${name}: identity lookup cannot dispatch after changing operator`, async () => {
    const h = harness(), lookup = deferred(); h.ctx.authenticatedPartsTarget = () => lookup.promise;
    const task = h.ctx[name]('fixture', '2026-09-20'); h.replaceSession(); lookup.resolve(h.target);
    await task; assert.equal(h.calls.length, 0); assert.equal(h.row.pdcPartsWorstEta, '2026-09-15');
  });
}
test('Parts ordered keeps the original actor while awaiting authoritative ETA refresh', async () => {
  const h = harness(), refresh = deferred(); h.row.__emailVehicleServerAuthoritative = true;
  h.ctx.refreshEmailVehicleLocations = () => refresh.promise;
  const task = h.ctx.markVehiclePartsOrdered('fixture'); h.replaceSession(); refresh.resolve(true);
  await task; assert.equal(h.calls.length, 0);
});
test('a delayed accepted ETA receipt does not change the replacement session’s vehicle', async () => {
  const h = harness(), response = deferred(); h.service.updatePartsEta = () => response.promise;
  const task = h.ctx.updateVehiclePartsWorstEta('fixture', '2026-09-20'); await tick();
  h.replaceSession('operator-a'); response.resolve({ ok: true }); await task;
  assert.equal(h.row.pdcPartsWorstEta, '2026-09-15');
});
test('current operator Parts receipt still updates ETA after a validated save', async () => {
  const h = harness(); await h.ctx.updateVehiclePartsWorstEta('fixture', '2026-09-20');
  assert.deepEqual(h.calls, ['updatePartsEta']); assert.equal(h.row.pdcPartsWorstEta, '2026-09-20');
});
test('Parts completion response from an old session cannot offer an email draft', async () => {
  const h = harness(), response = deferred(); h.service.markPartsComplete = () => response.promise;
  const task = h.ctx.markVehiclePartsComplete('fixture'); await tick(); h.replaceSession();
  response.resolve({ ok: true, code: 'parts_completed', data: { changed: true } }); await task;
  assert.equal(h.calls.length, 0); assert.equal(h.ctx.app.partsCompletionInFlight.size, 0);
});
