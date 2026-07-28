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

  app.data = [{ id: 'raw-email-row', stock: '13056899', pdcRequiresElectrical: false, pdcEmailOperationLines: [] }];
  app.emailVehicleLocationRows = [{ stock: '13056899', pdcRequiresElectrical: true, pdcEmailOperationLines: [{ operation_no: 'OP4', work_key: 'electrical', description: 'Shu Roo supply and fit' }] }];
  window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE = {
    reconcileVehicleRows(localRows, serverRows) {
      return { rows: localRows.map(row => row.stock === '13056899' ? { ...row, ...serverRows[0], __emailVehicleServerAuthoritative: true } : row) };
    },
  };
  const authoritativeEmailVehicle = selectedVehicle('13056899');
  assert(authoritativeEmailVehicle?.pdcRequiresElectrical === true, 'Vehicle detail must use authoritative email work state instead of the stale raw row');
  assert(authoritativeEmailVehicle?.pdcEmailOperationLines?.[0]?.operation_no === 'OP4', 'Vehicle detail must retain authenticated operation lines from the reconciled row');
  const operationGroups = vehicleWorkshopGroups(authoritativeEmailVehicle, { requirements: [{ work_key: 'electrical', stage_code: 'ELECTRICAL', required: true, completed: false }], bookings: [] });
  assert(operationGroups.length === 1 && operationGroups[0].lines[0].description === 'OP4 · Shu Roo supply and fit', 'Work & bookings must render the authenticated operation number and description in its canonical station');
  const duplicateGroups = vehicleWorkshopGroups({
    ...authoritativeEmailVehicle,
    pdcJobLines: [{ category: 'Electrical', description: 'Shu Roo supply and fit' }],
  }, { requirements: [{ work_key: 'electrical', stage_code: 'ELECTRICAL', required: true, completed: false }], bookings: [] });
  assert(duplicateGroups[0].lines.length === 1, 'A stale local line identical to authenticated evidence must not render twice');
  const pmbStationGroups = vehicleWorkshopGroups({}, {
    requirements: [
      { work_key: 'electrical', stage_code: 'ELECTRICAL', required: true, completed: false },
      { work_key: 'parts', stage_code: 'PARTS', required: true, completed: false },
      { work_key: 'sublet', stage_code: 'SUBLET', required: true, completed: false },
    ],
    bookings: [],
  });
  assert(pmbStationGroups.map(group => group.stage).join(',') === 'ELECTRICAL', 'Vehicle Work & bookings must show PMB stations only, excluding Parts and Sublet');
  const escapedOperationHtml = authenticatedEmailOperationLinesHtml({
    pdcEmailOperationLines: [{ operation_no: 'PD003-A75EB7AE', work_key: 'fitting', description: '<img src=x onerror=alert(1)>' }],
  });
  assert(!escapedOperationHtml.includes('<img'), 'Authenticated PD descriptions must not render raw HTML');
  assert(escapedOperationHtml.includes('&lt;img'), 'Authenticated PD descriptions must be HTML-escaped');

  const canonicalOrdinary = { stock: 'ORDINARY-1', vin: 'VIN-ORDINARY', marker: 'canonical' };
  const reconciledOrdinary = { ...canonicalOrdinary, id: 'c0a80101-0000-4000-8000-000000000001', permanentVehicleId: 'c0a80101-0000-4000-8000-000000000001', marker: 'reconciled-navision' };
  app.data = [canonicalOrdinary];
  app.emailVehicleLocationRows = [reconciledOrdinary];
  window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE = { reconcileVehicleRows(_localRows, serverRows) { return { rows: serverRows }; } };
  assert(selectedVehicle('ORDINARY-1') === reconciledOrdinary, 'Vehicle detail must preserve the authoritative reconciled snapshot object and canonical UUID used by PMB transfer');

  app.data = [{ stock: 'CONFLICT-1', vin: 'VIN-A' }];
  app.emailVehicleLocationRows = [{ stock: 'CONFLICT-1', vin: 'VIN-B' }];
  window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE = {
    reconcileVehicleRows() { return { rows: [{ stock: 'CONFLICT-1', vin: 'VIN-A', __emailVehicleIdentityConflict: true, __locationIdentityReadOnly: true }] }; },
  };
  assert(selectedVehicle('CONFLICT-1') === null, 'Authenticated Stock/VIN identity conflicts must fail closed');

  delete window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE;
  app.emailVehicleLocationRows = [];
  app.data = [first, second];

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
