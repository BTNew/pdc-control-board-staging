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
