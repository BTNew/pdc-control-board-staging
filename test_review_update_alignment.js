const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  function assert(condition, message) { if (!condition) throw new Error(message); }

  assert(VEHICLE_TABLE_COLUMN_ORDER_KEY.endsWith(':v3'), 'Column order storage key should be bumped after current-stage column changes');
  ['hoist', 'fitting', 'tyre', 'navisionNotes'].forEach(id => assert(VEHICLE_TABLE_DEFAULT_COLUMN_IDS.includes(id), 'Default columns missing ' + id));
  ['build', 'sublet'].forEach(id => assert(!VEHICLE_TABLE_DEFAULT_COLUMN_IDS.includes(id), 'Default columns should not include stale ' + id));

  const headers = ['PARTS', 'Parts Complete', 'HOIST', 'Fitting Complete', 'PIT INSPECTION'];
  const headerMap = buildHeaderMap(headers);
  const row = ['Yes', 'Yes', 'Y', 'true', '1'];
  const updates = buildExplicitPdcUpdatesFromImport(row, headerMap);
  assert(updates.pdcRequiresParts === true, 'PARTS import column should set pdcRequiresParts');
  assert(updates.pdcCompleteParts === true, 'Parts Complete import column should set pdcCompleteParts');
  assert(updates.pdcRequiresHoist === true, 'HOIST import column should set pdcRequiresHoist');
  assert(updates.pdcCompleteFitting === true, 'Fitting Complete import column should set pdcCompleteFitting');
  assert(updates.pdcRequiresPitInspection === true, 'PIT INSPECTION import column should set pdcRequiresPitInspection');

  app.data = [];
  exportCsv();
  const csv = __lastBlobText;
  assert(csv.includes('Requires HOIST'), 'CSV export should include current Hoist required header');
  assert(csv.includes('FITTING Complete'), 'CSV export should include current Fitting complete header');
  assert(csv.includes('Requires TYRE'), 'CSV export should include current Tyre required header');
  assert(csv.includes('Requires PIT'), 'CSV export should include current Pit required header');
  assert(!csv.includes('Requires Build'), 'CSV export should not include stale Build required header');
  assert(!csv.includes('Requires Sublet'), 'CSV export should not include stale Sublet required header');

  console.log('Review update alignment tests passed');
})();
`;

let __lastBlobText = '';
const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} } },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; }
  },
  document: {
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{add(){},remove(){},toggle(){}} })
  },
  navigator: {},
  FileReader: function(){},
  Blob: function(parts){ __lastBlobText = (parts || []).join(''); context.__lastBlobText = __lastBlobText; },
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
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
  __lastBlobText,
};
context.window.alert = () => {};
context.window.confirm = () => true;
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
