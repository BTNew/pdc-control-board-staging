'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
function harness() {
  const events = new Map();
  const context = { Map, Set, Promise, app: {}, window: { PDC_AUTH_CONTEXT: { userId: 'test-operator', role: 'operator' },
    addEventListener: (name, callback) => { if (!events.has(name)) events.set(name, []); events.get(name).push(callback); } } };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('const qcPhotoEvidence = new Map();'), source.indexOf('function qcPageIsMobile()')), context);
  vm.runInContext(source.slice(source.indexOf('function beginRftTransportAction('), source.indexOf('async function markRftConfirmation(')), context);
  context.replaceSession = () => {
    delete context.window.PDC_AUTH_CONTEXT;
    for (const callback of events.get('pdc-auth-locked') || []) callback({ detail: { reason: 'session-ended' } });
    context.window.PDC_AUTH_CONTEXT = { userId: 'replacement-operator', role: 'operator' };
    for (const callback of events.get('pdc-auth-ready') || []) callback({});
  };
  return context;
}
test('RFT actions for different vehicles retain independent completion ownership', () => {
  const ctx = harness();
  const first = ctx.beginRftTransportAction('vehicle-a'), second = ctx.beginRftTransportAction('vehicle-b');
  assert.equal(ctx.rftTransportActionIsCurrent(first), true);
  assert.equal(ctx.rftTransportActionIsCurrent(second), true);
  ctx.finishRftTransportAction(first);
  assert.equal(ctx.rftTransportActionIsCurrent(second), true);
  assert.equal(ctx.app.rftTransportActionInFlight.size, 1);
});
test('rapid duplicate RFT action for the same vehicle stays blocked until completion', () => {
  const ctx = harness(), first = ctx.beginRftTransportAction('vehicle-a');
  assert.equal(ctx.beginRftTransportAction('vehicle-a'), null);
  ctx.finishRftTransportAction(first);
  assert.ok(ctx.beginRftTransportAction('vehicle-a'));
});
test('logout invalidates RFT callbacks and an old finally cannot clear a replacement action', () => {
  const ctx = harness(), first = ctx.beginRftTransportAction('vehicle-a');
  ctx.replaceSession();
  assert.equal(ctx.rftTransportActionIsCurrent(first), false);
  assert.equal(ctx.app.rftTransportActionInFlight.size, 0);
  const next = ctx.beginRftTransportAction('vehicle-a');
  ctx.finishRftTransportAction(first);
  assert.equal(ctx.rftTransportActionIsCurrent(next), true);
  assert.equal(ctx.app.rftTransportActionInFlight.size, 1);
});
test('a viewer or locked session cannot acquire RFT mutation ownership', () => {
  const ctx = harness(); ctx.window.PDC_AUTH_CONTEXT.role = 'viewer';
  assert.equal(ctx.beginRftTransportAction('vehicle-a'), null);
  delete ctx.window.PDC_AUTH_CONTEXT;
  assert.equal(ctx.beginRftTransportAction('vehicle-a'), null);
});
