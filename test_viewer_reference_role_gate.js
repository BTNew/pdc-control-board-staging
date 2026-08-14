'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(require('path').join(__dirname, 'app.js'), 'utf8');

function extractFunction(name, nextName) {
  const start = source.indexOf(`function ${name}`);
  const end = source.indexOf(`function ${nextName}`, start + 1);
  assert.ok(start >= 0 && end > start, `missing ${name}`);
  return source.slice(start, end);
}

const context = {
  window: { PDC_AUTH_CONTEXT: { role: 'viewer' }, __workshopReferenceDataService: null },
  initCalls: 0,
  stopCalls: 0,
  initWorkshopReferenceDataServiceIfAvailable() {
    context.initCalls += 1;
    return { listTechnicians() { throw new Error('viewer requested technicians'); } };
  },
  resetWorkshopReferenceDataAuthorityState() { context.stopCalls += 1; },
};
vm.createContext(context);
vm.runInContext(
  `${extractFunction('workshopReferenceDataRoleCanRead', 'refreshWorkshopReferenceData')}\n${extractFunction('refreshWorkshopReferenceData', 'startWorkshopReferenceDataReconciliationTimer')}`,
  context,
);
assert.strictEqual(context.workshopReferenceDataRoleCanRead('viewer'), false);
assert.strictEqual(context.workshopReferenceDataRoleCanRead('operator'), true);
assert.strictEqual(context.workshopReferenceDataRoleCanRead('administrator'), true);
context.refreshWorkshopReferenceData();
assert.strictEqual(context.initCalls, 0, 'viewer bootstrap must not construct or call the operator-only reference service');
assert.strictEqual(context.stopCalls, 1, 'viewer bootstrap must tear down any prior reference reconciliation');

context.window.PDC_AUTH_CONTEXT.role = 'operator';
const requested = [];
context.initWorkshopReferenceDataServiceIfAvailable = () => ({
  listTechnicians: async () => requested.push('technicians'),
  listSalespeople: async () => requested.push('salespeople'),
  listSubletProviders: async () => requested.push('providers'),
  listWorkshopBays: async () => requested.push('bays'),
  getWorkshopConfiguration: async () => requested.push('configuration'),
  subscribeTechnicians() {}, subscribeSalespeople() {}, subscribeSubletProviders() {}, subscribeWorkshopBays() {}, subscribeWorkshopSettings() {},
});
context.startWorkshopReferenceDataReconciliationTimer = () => {};
context.refreshWorkshopReferenceData();
setImmediate(() => {
  assert.deepStrictEqual(requested.sort(), ['bays', 'configuration', 'providers', 'salespeople', 'technicians']);
  console.log('Viewer reference bootstrap role-gate checks passed');
});
