'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function vehicleLookupSafetyChecks() {
  function assert(condition, message) {
    if (!condition) throw new Error(message);
  }

  renderKpis = function() {};
  renderVehicleTable = function() {};
  renderKanban = function() {};
  renderWorkflowBoard = function() {};
  renderTvBoard = function() {};
  renderScheduleBoard = function() {};
  renderPartsHome = function() {};
  renderRftHome = function() {};
  renderCompletedVehicles = function() {};
  renderIncomingDashboardBoard = function() {};
  renderAdminLists = function() {};
  renderCustomers = function() {};
  renderReviewTable = function() {};

  const first = { id: 'vehicle-one', stock: '10000001', batch: 'BATCH-ONE', internalStatus: 'Keep first' };
  const second = { id: 'vehicle-two', stock: '10000002', batch: 'BATCH-TWO', internalStatus: 'Keep second' };
  app.data = [first, second];
  app.selectedStock = first.stock;

  assert(selectedVehicle('10000002') === second, 'An exact stock key should resolve the requested vehicle');
  assert(selectedVehicle('BATCH-TWO') === second, 'A unique Batch alias should resolve the requested vehicle');
  assert(selectedVehicle('missing-key') === null, 'A missing key must return null instead of the first vehicle');

  const editsBefore = localStorage.getItem(EDITS_KEY);
  const saveResult = saveVehicleEdits('missing-key', { internalStatus: 'Wrongly changed' });
  assert(saveResult === false, 'Saving an unknown vehicle should report failure');
  assert(first.internalStatus === 'Keep first' && second.internalStatus === 'Keep second', 'A stale key must not mutate another vehicle');
  assert(localStorage.getItem(EDITS_KEY) === editsBefore, 'A stale key must not create a saved edit');

  const previousSelection = app.selectedStock;
  const previousHref = window.location.href;
  assert(openVehicleModal('missing-key') === false, 'Opening an unknown vehicle should fail cleanly');
  assert(app.selectedStock === previousSelection, 'A failed modal lookup must retain the prior selection');
  assert(window.__alerts.length === 1, 'A failed modal lookup should give a controlled user-facing warning');
  draftReleasedVehicleEmail('missing-key');
  assert(window.location.href === previousHref, 'A stale key must not draft an email for another vehicle');

  app.data = [
    { id: 'alias-one', stock: '20000001', batch: 'SHARED-BATCH' },
    { id: 'alias-two', stock: '20000002', batch: 'SHARED-BATCH' },
  ];
  assert(selectedVehicle('SHARED-BATCH') === null, 'An ambiguous Batch alias must fail closed');

  app.data = [
    { id: 'duplicate-one', stock: '30000001' },
    { id: 'duplicate-two', stock: '30000001' },
  ];
  assert(selectedVehicle('30000001') === null, 'An ambiguous canonical vehicle key must fail closed');

  app.data = [];
  app.sharedNavisionVisibleRows = [{
    id: 'shared-record-one', stock_number: '40000001', dealer_code: '14450',
    customer_name: 'Shared customer', model: 'HiAce', vehicle_status: 'PMB',
    is_current: true, board_activated: true,
  }];
  const intakeVehicle = aiIntakeVehicleForStock('40000001');
  assert(intakeVehicle && vehicleKey(intakeVehicle) === '40000001', 'AI Intake must resolve the canonical Vehicle Locations row, not a raw Navision item');
  assert(aiIntakeStockNavigationHtml('40000001').includes('data-open-stock="40000001"'), 'AI Intake must link the exact canonical Vehicle Locations key');
  const locationIdentity = vehicleIdentityStackHtml(intakeVehicle, { button: true, buttonLabel: 'SN' });
  assert(/identity-stock[\s\S]*data-open-stock="40000001"/.test(locationIdentity), 'Vehicle Locations Stock must render as a vehicle-card link');
  assert(!/identity-key[\s\S]*data-open-stock/.test(locationIdentity.split('identity-stock')[0]), 'Vehicle Locations Key must remain plain text when Stock is the requested link');
  const alertsBeforeSharedOpen = window.__alerts.length;
  assert(openVehicleModal('40000001') !== false, 'A unique shared Vehicle Locations row must open read-only instead of reporting that it does not exist');
  assert(app.selectedStock === '40000001', 'Shared Vehicle Locations opening must select the exact Stock');
  assert(window.__alerts.length === alertsBeforeSharedOpen, 'Opening a valid shared vehicle must not show a missing-vehicle alert');

  app.sharedNavisionVisibleRows = [
    { id: 'shared-duplicate-one', stock_number: '50000001', dealer_code: '14450', model: 'HiAce', vehicle_status: 'PMB', is_current: true, board_activated: true },
    { id: 'shared-duplicate-two', stock_number: '50000001', dealer_code: '37047', model: 'Coaster', vehicle_status: 'PMB', is_current: true, board_activated: true },
  ];
  assert(aiIntakeVehicleForStock('50000001') === null, 'AI Intake must keep duplicate shared Stock identities fail-closed');

  console.log('Vehicle lookup safety checks passed');
})();
`;

const storage = new Map();
const alerts = [];
const context = {
  console,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    location: { search: '', pathname: '/index.html', href: 'about:blank' },
    alert: message => alerts.push(String(message)),
    confirm: () => true,
    prompt: () => 'QA',
    setTimeout,
    requestAnimationFrame: callback => callback(),
    __alerts: alerts,
  },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; },
  },
  document: {
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add() {}, remove() {}, toggle() {} }, appendChild() {}, dataset: {} },
    createElement: () => ({ setAttribute() {}, appendChild() {}, addEventListener() {}, remove() {}, click() {}, focus() {}, style: {}, classList: { add() {}, remove() {}, toggle() {} } }),
  },
  navigator: {},
  FileReader: function FileReader() {},
  Blob: function Blob() {},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
  URLSearchParams,
  Intl,
  Date,
  Map,
  Set,
  JSON,
  String,
  Number,
  Boolean,
  Array,
  Object,
  RegExp,
  Math,
  Error,
  Promise,
  setTimeout,
  clearTimeout,
};
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
