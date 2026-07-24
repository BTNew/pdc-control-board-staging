const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const pages = ['index.html', 'staging.html', 'no-vehicles.html']
  .map(name => fs.readFileSync(path.join(__dirname, name), 'utf8'))
  .join('\n');

assert.ok(!source.includes('function parsePurchaseOrderText'), 'Public PO parser must be absent');
assert.ok(!source.includes('function applyPurchaseOrderImport'), 'Public PO importer must be absent');
assert.ok(!source.includes('function handlePoSelect'), 'Page-level PO handler must be absent');
assert.ok(!source.includes('function handleVehiclePoSelect'), 'Vehicle-level PO handler must be absent');
assert.ok(!source.includes("on($('#po-upload')"), 'PO upload event binding must be absent');
assert.ok(!source.includes('[data-vehicle-po-upload]'), 'Vehicle PO upload event binding must be absent');
assert.ok(!pages.includes('id="po-scan-card"'), 'PO upload card must be absent from deployed pages');
assert.ok(!pages.includes('data-vehicle-po-upload'), 'Generated PO upload controls must be absent from deployed pages');

let code = source;
code += String.raw`
(function runDisabledPurchaseOrderContract(){
  function check(condition, message) { if (!condition) throw new Error(message); }
  check(typeof parsePurchaseOrderText === 'undefined', 'Public PO parser must not exist at runtime');
  check(typeof applyPurchaseOrderImport === 'undefined', 'Public PO importer must not exist at runtime');
  check(typeof handlePoSelect === 'undefined', 'Page-level PO handler must not exist at runtime');
  check(typeof handleVehiclePoSelect === 'undefined', 'Vehicle-level PO handler must not exist at runtime');

  app.data = [{ id: 'navision-1', stock: '13047164', batch: '13047164', source: 'Navision', recordLifecycle: 'navision', pdcSheetVisible: false }];
  const before = JSON.stringify(app.data);
  for (const attempt of [
    () => legacyDisabledParsePurchaseOrderText('Stock 13047164', 'legacy.pdf'),
    () => legacyDisabledEnsureVehicleForPo({ stock: '13047164' }),
    () => legacyDisabledApplyPurchaseOrderImport({ stock: '13047164' }, 'legacy.pdf'),
    () => legacyDisabledApplyPurchaseOrderImportUnsafe({ stock: '13047164' }, 'legacy.pdf'),
  ]) {
    let blocked = false;
    try { attempt(); } catch (error) { blocked = /disabled/i.test(String(error && error.message || error)); }
    check(blocked, 'Every retained legacy helper entry must fail closed as disabled');
  }
  check(JSON.stringify(app.data) === before, 'Disabled legacy PO entry points must not mutate vehicle data');
  console.log('Purchase-order upload removal contract passed');
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
  navigator: {}, FileReader: function(){}, Blob: function(){},
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
