'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
code += String.raw`
(function runWorkImportReviewChecks(){
  function check(condition, message) { if (!condition) throw new Error(message); }

  const parsed = parsePdCheckFormText([
    'Stock #: 12345678',
    'Job Card: JC-4102',
    'Customer: Broome Test Customer',
    'Vehicle: HiLux DCC SR',
    'Salesperson: CW',
    'Colour: Glacier White',
    'Window tint and steel tray body with dual battery',
  ].join('\n'), ['job-card.txt']);
  check(parsed.stock === '12345678', 'Job-card review must parse the stock number');
  check(parsed.jobcard === 'JC-4102', 'Job-card review must parse the job-card number');
  check(parsed.customer === 'Broome Test Customer', 'Job-card review must parse the customer');
  check(parsed.vehicle === 'HiLux DCC SR', 'Job-card review must parse the vehicle description');
  check(parsed.salesperson === 'CW', 'Job-card review must parse the salesperson');

  const labels = detectedWorkLabelsFromTasks(parsed.tasks);
  check(labels.includes('Tint'), 'Detected-work summary must say Tint');
  check(labels.includes('Tray'), 'Detected-work summary must say Tray');
  check(labels.includes('Electrical / 12V'), 'Detected-work summary must identify electrical work');

  const detected = pdFlagsFromTasks(parsed.tasks);
  check(detected.pdcRequiresTint === true, 'Tint detection must map to the Tint requirement');
  check(detected.pdcRequiresFitting === true, 'Tray detection must map to Fitting');
  check(detected.pdcRequiresFabrication === true, 'Tray detection must map to Fabrication');
  check(detected.pdcRequiresElectrical === true, 'Dual battery detection must map to Electrical');

  const vehicle = { stock: '12345678', pdcCompleteTint: true };
  const reviewed = workImportRequirementUpdates({
    stock: '12345678',
    reviewRequirementUpdates: {
      pdcRequiresTint: false,
      pdcRequiresHoist: false,
      pdcRequiresFitting: false,
      pdcRequiresFabrication: true,
      pdcRequiresElectrical: false,
      pdcRequiresTyre: false,
      pdcRequiresPitInspection: false,
      pdcRequiresParts: false,
    },
  }, vehicle, parsed.tasks);
  check(reviewed.pdcRequiresTint === true, 'Completed work must remain required during review');
  check(reviewed.pdcRequiresFabrication === true, 'An operator-selected work area must be saved');
  check(reviewed.pdcRequiresElectrical === false, 'Detected work must not be ticked when the operator did not select it');
  check(reviewed.pdcRequiresParts === true, 'A real stock number must retain the standard Parts gate');

  const amended = workImportVehicleUpdates({ reviewVehicleUpdates: {
    client: 'Amended Customer', vehicle: 'Amended HiLux', consultant: 'BG', pdcJobcard: 'JC-99',
    order: 'SO-55', vin: 'JTMAA7BJ504124838', colour: 'White', trim: 'Black',
  }});
  check(amended.client === 'Amended Customer' && amended.vehicle === 'Amended HiLux', 'Vehicle-card amendments must be returned for saving');
  check(amended.consultant === 'BG' && amended.pdcJobcard === 'JC-99', 'Salesperson and job-card amendments must be returned for saving');
  console.log('PO / job-card review checks passed');
})();
`;

const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} }, location: { search: '', pathname: '' } },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; },
  },
  document: {
    readyState: 'loading',
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{ add(){}, remove(){}, toggle(){} } }),
  },
  navigator: {},
  FileReader: function(){},
  Blob: function(){},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
  Intl, Date, Map, Set, JSON, String, Number, Boolean, Array, Object, RegExp, Math, Error, Promise, setTimeout, clearTimeout,
};
context.window.alert = () => {};
context.window.confirm = () => true;
context.window.prompt = () => 'QA';
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
assert.ok(source.includes('function showWorkImportReviewModal'), 'Shared PO / job-card review modal is missing');
assert.ok(source.includes('No changes have been saved yet'), 'Review modal must clearly state that parsing has not saved anything');
assert.ok(source.includes('Would you like us to tick the matching work areas automatically?'), 'Detected-work confirmation question is missing');
assert.ok(source.includes("await showWorkImportReviewModal({\n        kind: 'jobcard'"), 'Job-card upload must wait for review');
assert.ok(source.includes("await showWorkImportReviewModal({\n        kind: 'po'"), 'PO upload must wait for review');
assert.ok(source.includes('focusVehiclesAfterWorkImport(successfulImports.map(result => result.vehicleKey))'), 'Reviewed job-card imports must reveal and highlight the vehicle');

