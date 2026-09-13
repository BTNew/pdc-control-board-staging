'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const block = source.slice(source.indexOf('const qcPhotoEvidence = new Map();'), source.indexOf('function renderQualityControlPage()'));
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function harness() {
  const events = new Map(), calls = [], readers = [];
  const row = { id: 'fixture', __emailVehicleId: 'fixture', __emailVehicleServerAuthoritative: true, __emailVehicleVersion: 1,
    lines: [{ lineIdentity: 'line-a', lineVersion: 0, completed: false }, { lineIdentity: 'line-b', lineVersion: 0, completed: false }] };
  const ctx = { Map, Set, Promise, AbortController, console, setTimeout, clearTimeout,
    window: { PDC_AUTH_CONTEXT: { userId: 'operator-a', role: 'operator' }, setTimeout,
      confirm: () => true, alert() {}, scrollTo() {},
      addEventListener: (name, fn) => { if (!events.has(name)) events.set(name, []); events.get(name).push(fn); } },
    app: { emailVehicleLocationService: {} }, crypto: { randomUUID: () => 'test-request' },
    FileReader: class { constructor() { this.listeners = {}; readers.push(this); } addEventListener(n, fn) { this.listeners[n] = fn; } readAsDataURL() {} abort() { this.listeners.abort?.(); } },
    renderQualityControlPage() {}, refreshEmailVehicleLocations: async () => true,
  };
  vm.createContext(ctx); vm.runInContext(block, ctx);
  vm.runInContext(`qcPageVehicles = () => [fixture]; qcPageVehicleKey = v => v.id;
    qcPageOperationLines = v => v.lines || []; qcPagePhotoDisabledReason = () => '';
    qcPageAwaitOperationSnapshot = async () => true;
    this.inspect = () => ({ pending: qcPageOperationPending.size, photos: qcPhotoEvidence.size,
      uploading: qcPagePhotoUploadInFlight.size, notice: qcPageNotice, feedback: [...qcPageFeedback.values()] });
    this.waitQueue = () => qcPageOperationMutationChain;`, Object.assign(ctx, { fixture: row }));
  const lock = (nextActor = 'operator-b', reason = 'session-ended') => {
    delete ctx.window.PDC_AUTH_CONTEXT;
    for (const fn of events.get('pdc-auth-locked') || []) fn({ detail: { reason } });
    ctx.window.PDC_AUTH_CONTEXT = { userId: nextActor, role: 'operator' };
    for (const fn of events.get('pdc-auth-ready') || []) fn({});
  };
  return { ctx, row, calls, readers, lock };
}
function receipt(row, identity) {
  return { ok: true, data: { vehicle_version_after: 2, line: { line_identity: identity, version: 1, completed: true } } };
}
test('queued QC checks never execute under the next signed-in operator', async () => {
  const h = harness(), first = deferred();
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = (...args) => {
    h.calls.push({ actor: h.ctx.window.PDC_AUTH_CONTEXT.userId, line: args[2] });
    return h.calls.length === 1 ? first.promise : Promise.resolve(receipt(h.row, args[2]));
  };
  h.ctx.qcPageQueueOperationState('fixture', 'line-a', true);
  h.ctx.qcPageQueueOperationState('fixture', 'line-b', true);
  await tick(); h.lock(); first.resolve(receipt(h.row, 'line-a')); await tick(); await h.ctx.waitQueue();
  assert.deepEqual(h.calls, [{ actor: 'operator-a', line: 'line-a' }]);
  assert.equal(h.row.lines[0].completed, false, 'late previous-session receipt does not mutate the new view');
  assert.equal(h.ctx.inspect().pending, 0);
  assert.equal(h.ctx.inspect().feedback.length, 0);
});
test('desktop photo locks before reading so a rapid second selection cannot upload twice', async () => {
  const h = harness(), file = { name: 'photo.jpg', type: 'image/jpeg', size: 10 };
  h.ctx.app.emailVehicleLocationService.uploadQcPhotoEvidence = async () => { h.calls.push('upload'); return { ok: false, code: 'test' }; };
  const one = h.ctx.qcPageAttachPhoto('fixture', { files: [file] });
  const two = h.ctx.qcPageAttachPhoto('fixture', { files: [file] });
  assert.equal(h.readers.length, 1, 'second action is rejected before a second FileReader');
  h.readers[0].result = 'data:image/jpeg;base64,AA=='; h.readers[0].listeners.load();
  await Promise.all([one, two]); assert.equal(h.calls.length, 1);
});
test('signing out while a photo is being read prevents upload and receipt resurfacing', async () => {
  const h = harness(), file = { name: 'photo.jpg', type: 'image/jpeg', size: 10 };
  h.ctx.app.emailVehicleLocationService.uploadQcPhotoEvidence = async () => { h.calls.push('upload'); return { ok: false }; };
  const task = h.ctx.qcPageAttachPhoto('fixture', { files: [file] });
  h.lock(); h.readers[0].result = 'data:image/jpeg;base64,AA=='; h.readers[0].listeners.load();
  await task; assert.equal(h.calls.length, 0); assert.equal(h.ctx.inspect().photos, 0);
});
test('unchanged session serializes rapid checklist taps with the latest saved vehicle version', async () => {
  const h = harness();
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async (...args) => {
    h.calls.push({ version: args[1], line: args[2] }); return receipt(h.row, args[2]);
  };
  h.ctx.qcPageQueueOperationState('fixture', 'line-a', true);
  h.ctx.qcPageQueueOperationState('fixture', 'line-b', true);
  await h.ctx.waitQueue();
  assert.deepEqual(h.calls, [{ version: 1, line: 'line-a' }, { version: 2, line: 'line-b' }]);
  assert.equal(h.row.lines.every(line => line.completed), true);
});
test('same-operator session revalidation cancels queued checks and explains the interruption', async () => {
  const h = harness(), first = deferred();
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = (...args) => {
    h.calls.push(args[2]); return first.promise;
  };
  h.ctx.qcPageQueueOperationState('fixture', 'line-a', true);
  h.ctx.qcPageQueueOperationState('fixture', 'line-b', true);
  await tick(); h.lock('operator-a', 'session-revalidate');
  first.resolve(receipt(h.row, 'line-a')); await tick();
  assert.deepEqual(h.calls, ['line-a']);
  assert.match(h.ctx.inspect().notice, /Queued QC actions were cancelled/);
});
test('an old completion cannot clear a new operator’s pending check for the same line', async () => {
  const h = harness(), old = deferred(), next = deferred();
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = () => {
    h.calls.push(h.ctx.window.PDC_AUTH_CONTEXT.userId); return h.calls.length === 1 ? old.promise : next.promise;
  };
  h.ctx.qcPageQueueOperationState('fixture', 'line-a', true);
  await tick(); h.lock(); h.ctx.qcPageQueueOperationState('fixture', 'line-a', true); await tick();
  old.resolve(receipt(h.row, 'line-a')); await tick();
  assert.equal(h.ctx.inspect().pending, 1);
  next.resolve(receipt(h.row, 'line-a')); await h.ctx.waitQueue();
  assert.equal(h.ctx.inspect().pending, 0);
  assert.equal(h.row.lines[0].completed, true);
});
test('desktop QC signoff does not dispatch after identity resolution changes session', async () => {
  const h = harness(), identity = deferred();
  const start = source.indexOf('async function completeVehicleQualityControl(');
  const end = source.indexOf('\nfunction ', start + 1);
  Object.assign(h.ctx, { vehicleLifecycleSharedModeActive: () => true, selectedVehicle: () => h.row,
    vehicleInQualityControlGate: () => true, cleanNavisionText: value => value,
    localStorage: { getItem: () => 'operator' }, OPERATOR_NAME_KEY: 'name', OPERATOR_ROLE_KEY: 'role',
    vehicleIdentityTitle: () => 'Test fixture', vehicleLifecycleSharedRef: () => identity.promise });
  h.ctx.app.emailVehicleLocationService.finalizeQcToRft700 = async () => { h.calls.push('signoff'); return { ok: true }; };
  vm.runInContext(source.slice(start, end), h.ctx);
  const task = h.ctx.completeVehicleQualityControl('fixture', { photoReceiptId: 'receipt' });
  h.lock(); identity.resolve({ outcome: 'resolved', vehicleId: 'fixture', version: 1 });
  assert.equal(await task, false); assert.equal(h.calls.length, 0);
});
function mobileFunction(name) {
  const mobile = fs.readFileSync('pdc-qc-mobile.js', 'utf8');
  const start = mobile.indexOf(`  async function ${name}(`);
  const next = mobile.slice(start + 1).search(/\n  (?:async )?function /);
  return mobile.slice(start, start + 1 + next);
}
test('mobile QC photo cannot resume after a same-operator session replacement', async () => {
  const h = harness(), preview = deferred();
  Object.assign(h.ctx, { rowFor: () => h.row, canWrite: () => true, busy: () => false,
    restorePhoto() {}, retryFiles: new Map(), readPreview: () => preview.promise,
    feedback: (key, kind, message) => vm.runInContext(`qcPageFeedback.set('fixture', ${JSON.stringify({ kind, message })})`, h.ctx) });
  h.ctx.app.emailVehicleLocationService.uploadQcPhotoEvidence = async () => { h.calls.push('upload'); return { ok: false }; };
  vm.runInContext(mobileFunction('attachPhoto'), h.ctx);
  const task = h.ctx.attachPhoto('fixture', { name: 'test.jpg', type: 'image/jpeg', size: 10 });
  h.lock('operator-a', 'session-revalidate'); preview.resolve('preview');
  assert.equal(await task, false); assert.equal(h.calls.length, 0);
  assert.equal(h.ctx.inspect().feedback.length, 0);
});
test('mobile rejection error from an old request cannot appear in the replacement session', async () => {
  const h = harness(), response = deferred();
  h.row.lines[0].description = 'Test operation';
  Object.assign(h.ctx, { rowFor: () => h.row, canWrite: () => true, busy: () => false, pending: () => false,
    rejectionDrafts: new Map([['fixture', { selected: new Set(['line-a']), reason: 'Needs repair' }]]),
    displayStockNumber: () => 'fixture', getPdcSupabaseAccessToken: () => 'synthetic', URL,
    fetch: () => response.promise, feedback: (key, kind, message) => vm.runInContext(`qcPageFeedback.set('fixture', ${JSON.stringify({ kind, message })})`, h.ctx) });
  h.ctx.window.PDC_SUPABASE_CONFIG = { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co' };
  vm.runInContext(mobileFunction('rejectVehicle'), h.ctx);
  const task = h.ctx.rejectVehicle('fixture'); h.lock('operator-a', 'session-revalidate');
  response.resolve({ ok: false, json: async () => ({ ok: false, message: 'old request error' }) });
  assert.equal(await task, false); assert.equal(h.ctx.inspect().feedback.length, 0);
});
