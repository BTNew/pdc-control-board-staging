const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

const sampleDefinitions = [
  ['CRAIGW_PO11204260_PurchaseOrder.pdf', '12111759', 'PO11204260', 9],
  ['CRAIGW_PO11016825_PurchaseOrder.pdf', '12435803', 'PO11016825', 5],
  ['CRAIGW_PO11016848_PurchaseOrder.pdf', '12423633', 'PO11016848', 10],
];
const uploadDir = [
  path.resolve(__dirname, '..', '..', 'upload'),
  path.resolve(__dirname, '..', 'upload'),
].find(candidate => fs.existsSync(candidate)) || path.resolve(__dirname, '..', '..', 'upload');
const samples = sampleDefinitions.map(([name, stock, po, tasks]) => {
  const filePath = path.join(uploadDir, name);
  if (!fs.existsSync(filePath)) return null;
  return { name, stock, po, tasks, text: execFileSync('pdftotext', ['-layout', filePath, '-'], { encoding: 'utf8' }) };
}).filter(Boolean);

assert.strictEqual(samples.length, 3, 'The three supplied Broome Toyota PO examples are required for this regression test');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
code += String.raw`
(function runPurchaseOrderTests(){
  function check(condition, message) { if (!condition) throw new Error(message); }
  check(extractStockFromPoFilename('CRAIGW_PO11204260_PurchaseOrder.pdf') === '', 'A PO number in a filename must not be treated as a stock number');
  const parsed = PO_TEST_SAMPLES.map(sample => ({ sample, result: parsePurchaseOrderText(sample.text, sample.name) }));
  parsed.forEach(({ sample, result }) => {
    check(result.stock === sample.stock, sample.po + ' stock number was not read from inside the PDF');
    check(result.purchaseOrderNumber === sample.po, sample.po + ' number was not parsed');
    check(result.tasks.length === sample.tasks, sample.po + ' work-item count was not parsed (expected ' + sample.tasks + ', got ' + result.tasks.length + ': ' + result.tasks.join(' | ') + ')');
    check(Boolean(result.vehicle), sample.po + ' vehicle description was not parsed');
    check(Boolean(result.colour), sample.po + ' colour was not parsed');
    check(Boolean(result.trim), sample.po + ' trim was not parsed');
  });
  const trayPo = parsed.find(entry => entry.result.purchaseOrderNumber === 'PO11204260').result;
  check(trayPo.tasks.some(task => /Charges May Apply/.test(task)), 'A work description continued onto page two was not joined');
  const lcPo = parsed.find(entry => entry.result.purchaseOrderNumber === 'PO11016825').result;
  check(lcPo.vin === 'JTMAA7BJ504124838', 'VIN was not parsed from the LC300 PO');
  check(lcPo.vehicle === 'LC300 3.3L Dsl Wgn 10AT VX 7 Seat', 'Vehicle model code was not separated from the LC300 description');

  app.data = [{
    id: 'navision-12435803', stock: '12435803', batch: '12435803', source: 'Navision',
    recordLifecycle: 'navision', pdcSheetVisible: false, client: '', vehicle: '', consultant: ''
  }];
  const matched = applyPurchaseOrderImport(lcPo, lcPo.sourceFilename);
  check(!matched.created, 'The LC300 PO should match its existing Navision back-end vehicle');
  check(matched.vehicle.pdcSheetVisible === true, 'A PO-matched back-end vehicle should become active');
  check(matched.vehicle.purchaseOrderNumber === 'PO11016825', 'PO metadata was not saved to the matched vehicle');
  check(matched.vehicle.vin === 'JTMAA7BJ504124838', 'PO VIN was not saved to the matched vehicle');

  const newPo = parsed.find(entry => entry.result.purchaseOrderNumber === 'PO11016848').result;
  const created = applyPurchaseOrderImport(newPo, newPo.sourceFilename);
  check(created.created, 'A PO stock number absent from Navision should create a new vehicle');
  check(created.vehicle.recordLifecycle === 'purchase-order', 'The new vehicle should retain PO lifecycle protection');
  check(created.vehicle.client === 'Broome Toyota Retail Sales', 'The Broome retail department should populate the customer field');
  check(created.vehicle.vehicle === 'HiLux 4x4 2.8L Dsl D/C/C 6AT SR + Steel Wheels', 'The PO vehicle description should populate the active row');
  check(created.vehicle.pdcRequiresTint === true, 'Window tint should set the Tint work requirement');
  check(created.vehicle.pdcRequiresElectrical === true, 'Battery/camera/12V work should set the Electrical requirement');
  check(isVehicleVisibleOnPdcSheet(created.vehicle), 'A PO-created vehicle should be visible on the PDC Sheet');
  const navisionText = [
    ['Order','Batch','Model Description','Dealer Customer Name','Sub Location Description','ETA At Kewdale Yard','JITA PreOrder'].join('\t'),
    ['NAV-12423633','12423633','HiLux SR','Real Navision Customer','In Transit to WA','22/07/2026','Yes'].join('\t'),
  ].join('\n');
  applyNavisionImportPlan(buildNavisionImportPlan(parseNavisionInput(navisionText)));
  app.data = buildVehicleData();
  const enriched = app.data.filter(vehicle => vehicle.stock === '12423633');
  check(enriched.length === 1, 'A later Navision upload should enrich the PO-created vehicle without duplicating it');
  check(enriched[0].purchaseOrderNumber === 'PO11016848' && enriched[0].poTasks.length === 10, 'Navision enrichment should retain PO details and work lines');
  check(enriched[0].pdcSheetVisible === true, 'A later Navision upload must not hide a PO-created active vehicle');
  console.log('Purchase-order PDF import regression checks passed');
})();
`;

const storage = new Map();
const context = {
  console,
  PO_TEST_SAMPLES: samples,
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
