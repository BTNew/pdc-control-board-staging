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
    'PRE DELIVERY CHECK FORM',
    '(112) New Toyota Fleet Sales (BG) Bryce Guthrie Deal: 47836',
    'CUSTOMER SALES DETAILS',
    'Nyamba Buru Yawuru Ltd Fleet Govt GST Exempt',
    'Work: 91929600',
    'Est PD Completion Stock # 13047164',
    'Make & Model HiLux 4x4 2.8L DSi D/C/C 6AT SR 48V 2U24100 0001 Unit Colour Glacier White Trim Colour Black Fabric',
    'VIN/HIN No. MR0PEBHV500404232',
    'Window tint and steel tray body with dual battery',
    'Supplier: Hidrive',
  ].join('\n'), ['CRAIGW_PD Document 47836_PDCheckform.pdf']);
  check(parsed.stock === '13047164', 'PD review must use Stock # and must not mistake the Work phone number for Stock');
  check(parsed.customer === 'Nyamba Buru Yawuru Ltd', 'PD review must parse the customer from the CUSTOMER section');
  check(parsed.vehicle.startsWith('HiLux 4x4 2.8L DSi'), 'PD review must parse Make & Model');
  check(parsed.salesperson === 'BG', 'PD review must parse the salesperson code from the form header');
  check(parsed.colour === 'Glacier White', 'PD review must parse Unit Colour');
  check(parsed.vin === 'MR0PEBHV500404232', 'PD review must parse VIN');
  check(parsed.subletProvider === 'Hidrive', 'PD review must preserve the named Sublet provider');
  check(!Object.prototype.hasOwnProperty.call(parsed, 'order'), 'PD parsing must not expose a Toyota order field');
  check(!Object.prototype.hasOwnProperty.call(parsed, 'jobcard'), 'PD parsing must not create a job-card field');

  const labelled = parsePdCheckFormText([
    'Stock # 13047164',
    'Customer: Nyamba Buru Yawuru Ltd Fleet Govt',
    'Salesperson: (BG) Bryce Guthrie',
    'Make & Model: HiLux 4x4 2.8L Dsl D/C/C 6AT SR 48V 2U24100 001',
    'Unit Colour: Glacier White',
    'VIN: MR0PEBHV500404232',
    'Sublet Provider: Hidrive',
  ].join('\n'), ['PDCheckform.pdf']);
  check(labelled.stock === '13047164' && labelled.customer === 'Nyamba Buru Yawuru Ltd Fleet Govt', 'Labelled PD fields must retain Stock and customer');
  check(labelled.salesperson === 'BG', 'Labelled Salesperson must retain its staff code');
  check(labelled.vehicle.startsWith('HiLux 4x4 2.8L Dsl'), 'Labelled Make & Model must be parsed after its colon');
  check(labelled.colour === 'Glacier White', 'Labelled Unit Colour must be parsed after its colon');
  check(labelled.vin === 'MR0PEBHV500404232' && labelled.subletProvider === 'Hidrive', 'Labelled VIN and Sublet provider must be preserved');

  const labels = detectedWorkLabelsFromTasks(parsed.tasks);
  check(labels.includes('Tint'), 'Detected-work summary must say Tint');
  check(labels.includes('Tray'), 'Detected-work summary must say Tray');
  check(labels.includes('Electrical / 12V'), 'Detected-work summary must identify electrical work');
  check(labels.includes('Sublet'), 'Named provider evidence must identify Sublet work');

  const detected = pdFlagsFromTasks(parsed.tasks);
  check(detected.pdcRequiresTint === true, 'Tint detection must map to the Tint requirement');
  check(detected.pdcRequiresFitting === true, 'Tray detection must map to Fitting');
  check(detected.pdcRequiresFabrication === true, 'Tray detection must map to Fabrication');
  check(detected.pdcRequiresElectrical === true, 'Dual battery detection must map to Electrical');
  check(detected.pdcRequiresSublet === true, 'Named provider evidence must select Sublet');

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
    client: 'Amended Customer', vehicle: 'Amended HiLux', consultant: 'BG',
    vin: 'JTMAA7BJ504124838', colour: 'White', trim: 'Black', pmbSubletProvider: 'Hidrive',
  }});
  check(amended.client === 'Amended Customer' && amended.vehicle === 'Amended HiLux', 'Vehicle-card amendments must be returned for saving');
  check(amended.consultant === 'BG' && amended.pmbSubletProvider === 'Hidrive', 'Salesperson and Sublet provider amendments must be returned for saving');
  check(!Object.prototype.hasOwnProperty.call(amended, 'order') && !Object.prototype.hasOwnProperty.call(amended, 'pdcJobcard'), 'Review updates must not save order or job-card fields');

  app.navisionSharedBackendService = { visibleSnapshot() {} };
  app.sharedNavisionVisibleState = 'idle';
  app.sharedNavisionVisibleRealtimeState = 'idle';
  app.sharedNavisionVisibleRealtimeReconciled = false;
  const unavailableActivation = activateSharedNavisionForApprovedDocumentReview({ stock: '13047164' });
  check(unavailableActivation.ok === false && unavailableActivation.code === 'shared_authority_unavailable', 'PD import must fail closed when configured shared Navision authority is not ready');

  console.log('PD Document review checks passed');
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
assert.ok(source.includes('function showWorkImportReviewModal'), 'PD Document review modal is missing');
assert.ok(source.includes('No changes have been saved yet'), 'Review modal must clearly state that parsing has not saved anything');
assert.ok(source.includes('Would you like us to tick the matching work areas automatically?'), 'Detected-work confirmation question is missing');
assert.ok(/await\s+showWorkImportReviewModal\(\{[\s\S]{0,180}?kind:\s*'pd'/.test(source), 'PD Document upload must wait for review');
assert.ok(!source.includes('id="po-scan-card"'), 'Purchase-order upload card must not remain in generated application markup');
assert.ok(!source.includes("on($('#po-upload')") && !source.includes('data-vehicle-po-upload'), 'Purchase-order upload events and generated controls must be absent');
assert.ok(!source.includes('function handlePoSelect') && !source.includes('function handleVehiclePoSelect'), 'Purchase-order file handlers must not remain callable');
assert.ok(!source.includes('function applyPurchaseOrderImport') && !source.includes('function parsePurchaseOrderText'), 'Purchase-order parsing/import entry points must not remain callable');
assert.ok(source.includes('Purchase-order vehicle-work intake is disabled. Upload the approved PD Document instead.'), 'Legacy purchase-order internals must fail closed if reached');
assert.ok(source.includes('focusVehiclesAfterWorkImport(successfulImports.map(result => result.vehicleKey))'), 'Reviewed PD imports must reveal and highlight the vehicle');

for (const htmlName of ['index.html', 'staging.html', 'no-vehicles.html']) {
  const html = fs.readFileSync(path.join(__dirname, htmlName), 'utf8');
  assert.ok(html.includes('id="dashboard-pd-drop"'), `${htmlName} must provide the PD Document upload path`);
  assert.ok(!html.includes('id="po-scan-card"') && !html.includes('id="po-file"'), `${htmlName} must not provide a purchase-order upload path`);
  assert.ok(!/job\s*card\s*\/\s*pd|upload\s+job\s*card/i.test(html), `${htmlName} must not offer a job-card upload path`);
  assert.ok(!/toyota\s+order/i.test(html), `${htmlName} must not display Toyota order`);
}
assert.ok(!/toyota\s+order/i.test(source), 'Application UI and matching logic must not display or name Toyota order');
assert.ok(!/(?:row|vehicle|record|incoming|v)\.(?:order|orderNumber)\b/.test(source), 'Application runtime must not use legacy Toyota-order properties');
for (const scriptName of ['workshop-planner.js', 'vehicle-lifecycle-actions.js']) {
  const script = fs.readFileSync(path.join(__dirname, scriptName), 'utf8');
  assert.ok(!/toyota\s*order|toyota_order|(?:row|vehicle|record|incoming|v)\.(?:order|orderNumber)\b/i.test(script), `${scriptName} must not display, map or match Toyota order`);
}

