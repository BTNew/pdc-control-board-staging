const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  function assert(condition, message) { if (!condition) throw new Error(message); }

  assert(/:v[34]$/.test(VEHICLE_TABLE_COLUMN_ORDER_KEY), 'Column order storage key should be bumped after current-stage column changes');
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

  const rftVehicle = { stock: 'RFT001', pdcLocation: 'RFT', manualLocation: 'RFT' };
  const completedRftVehicle = { stock: 'RFT002', pdcLocation: 'RFT', manualLocation: 'RFT', rftCollected: true, rftCollectedAt: '2026-07-06T01:00:00.000Z' };
  const pmbVehicle = { stock: 'PMB001', pdcLocation: 'PMB', manualLocation: 'PMB', pdcRequiresTint: true, pdcCompleteTint: true };
  assert(incomingBucketForVehicle(rftVehicle) === 'rft', 'Control Board should include RFT vehicles in their own bucket');
  assert(incomingBucketLabel('rft') === 'RFT', 'Control Board RFT bucket label should be RFT');
  assert(vehicleCollectedFromRft(completedRftVehicle), 'Collected RFT vehicles should be marked completed');
  assert(statusCategory(completedRftVehicle) === 'completed', 'Collected RFT vehicles should move out of live RFT status');
  assert(incomingBucketForVehicle(completedRftVehicle) === 'completed', 'Collected RFT vehicles should be assigned to completed bucket');
  app.data = [rftVehicle, completedRftVehicle];
  assert(rftHomeRows().length === 1 && rftHomeRows()[0].stock === 'RFT001', 'RFT home should hide vehicles collected from RFT');
  assert(completedVehicleRows().length === 1 && completedVehicleRows()[0].stock === 'RFT002', 'Completed vehicles side menu should show collected RFT vehicles');
  assert(incomingVehicleDetailRow(rftVehicle, 'rft').includes('data-rft-collected-key="RFT001"'), 'RFT rows should expose a collected checkbox');
  assert(incomingVehicleDetailRow(pmbVehicle, 'pmb').includes('data-transfer-rft-stock="PMB001"'), 'PMB workflow/control-board rows should expose transfer to RFT action');

  const stageValues = PMB_STAGE_DEFS.map(def => def.value);
  ['TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'].forEach(stage => {
    assert(stageValues.includes(stage), 'PMB bucket coverage missing ' + stage);
  });
  const bayBoardHtml = renderPmbBayBoardHtml('HOIST');
  assert(bayBoardHtml.includes('data-open-pmb-bays="TINT"'), 'PMB bay board should expose Tint bucket tab');
  assert(bayBoardHtml.includes('data-open-pmb-bays="PIT_INSPECTION"'), 'PMB bay board should expose Pit bucket tab');
  assert(bayBoardHtml.includes('pmb-bay-stage-tabs'), 'PMB bay board should include bucket navigation tabs');
  const bayActionVehicle = { stock: '10015802', keyNumber: '202', jobCardNumber: 'JC13920002', client: 'Kewdale Fleet', pdcLocation: 'PMB', manualLocation: 'PMB', pmbStage: 'HOIST', pdcRequiresHoist: true };
  app.data = [bayActionVehicle];
  const bayCardHtml = pmbBayVehicleCardHtml(bayActionVehicle, 'HOIST');
  assert(bayCardHtml.includes('pmb-bay-vehicle-pill'), 'PMB bay card should render as the rectangular pill variant');
  assert(bayCardHtml.includes('10015802') && bayCardHtml.includes('202') && bayCardHtml.includes('JC13920002'), 'PMB bay pill should show Key, Stock and JC identifiers');
  assert(bayCardHtml.includes('Kewdale Fleet'), 'PMB bay pill should show customer name under identifiers');
  assert(!bayCardHtml.includes('data-assign-pmb-bay-number='), 'PMB bay pill surface should not include bay assignment controls');
  const workflowCardHtml = pmbVehicleCardHtml(bayActionVehicle);
  assert(workflowCardHtml.includes('pmb-vehicle-pill'), 'PMB workflow cards should use the rectangular pill surface');
  assert(workflowCardHtml.includes('pmb-bay-pill-ids') && workflowCardHtml.includes('Kewdale Fleet'), 'PMB workflow pill should show only ID row plus customer');
  assert(workflowCardHtml.includes('pmb-outstanding-stations'), 'PMB workflow pill should show outstanding station chips');
  assert(!workflowCardHtml.includes('pmb-card-actions') && !workflowCardHtml.includes('RFT gate:'), 'PMB workflow pill should not show old action/meta/RFT gate clutter');
  assert(!workflowCardHtml.includes('pmb-card-requirements'), 'PMB workflow pill should not show the old all-job tick row');
  assert(pmbStageBayCount('FABRICATION') === 13, 'Fabrication should expose thirteen physical bays');
  const fabCardHtml = pmbBayVehicleCardHtml({ stock: '10015803', keyNumber: '203', jobCardNumber: 'JC13920003', client: 'Fremantle Council', pdcLocation: 'PMB', manualLocation: 'PMB', pmbStage: 'FABRICATION' }, 'FABRICATION');
  assert(!fabCardHtml.includes('data-assign-pmb-bay-number='), 'Fabrication bay pill should stay clean without bay assignment controls');

  const tyreRequiredOld = { stock: '1001', batch: '1001', client: 'Alpha', pdcLocation: 'PMB', pmbStage: 'TYRE', pmbEnteredAt: '2026-01-01T00:00:00.000Z', pdcRequiresTyre: true, pdcCompleteTyre: false };
  const tyreRequiredNew = { stock: '1002', batch: '1002', client: 'Bravo', pdcLocation: 'PMB', pmbStage: '', pmbEnteredAt: '2026-06-01T00:00:00.000Z', pdcRequiresTyre: true, pdcCompleteTyre: true, pdcBlocked: true };
  const tyreNotRequired = { stock: '1003', batch: '1003', client: 'Charlie', pdcLocation: 'PMB', pmbStage: 'FITTING', pmbEnteredAt: '2026-03-01T00:00:00.000Z', pdcRequiresTyre: false, pdcCompleteTyre: false };
  const filterRows = [tyreRequiredNew, tyreNotRequired, tyreRequiredOld];
  assert(workflowFilterAndSortRows(filterRows, { work: 'tyre', required: 'yes', sort: 'oldest' }).map(row => row.stock).join(',') === '1001,1002', 'Tyre required filter should include Yes rows oldest first');
  assert(workflowFilterAndSortRows(filterRows, { work: 'tyre', required: 'yes', sort: 'newest' }).map(row => row.stock).join(',') === '1002,1001', 'Newest sort should reverse PMB date order');
  assert(workflowFilterAndSortRows(filterRows, { work: 'tyre', required: 'no', sort: 'oldest' }).map(row => row.stock).join(',') === '1003', 'Tyre Required: No should show not-required rows');
  assert(workflowFilterAndSortRows(filterRows, { work: 'tyre', completion: 'outstanding', sort: 'oldest' }).map(row => row.stock).join(',') === '1001', 'Outstanding filter should exclude completed work');
  assert(workflowFilterAndSortRows(filterRows, { bucket: 'UNALLOCATED', sort: 'oldest' }).map(row => row.stock).join(',') === '1002', 'Unallocated bucket filter should match rows without a PMB stage');
  assert(workflowFilterAndSortRows(filterRows, { stoppage: 'yes', sort: 'oldest' }).map(row => row.stock).join(',') === '1002', 'Stoppage-only filter should match blocked rows');
  const filterHeaderHtml = productionGridHeaderHtml('workflow-production-grid-header', { workflowFilters: { sort: 'oldest', bucket: '', work: 'tyre', required: 'yes', completion: '', stoppage: '' } });
  assert(filterHeaderHtml.includes('data-workflow-header-filter="work"'), 'Workflow column row should contain selectable work filters');
  assert(filterHeaderHtml.includes('data-workflow-work-key="tyre"'), 'Tyre heading should expose its own filter selector');
  assert(filterHeaderHtml.includes('Yes</small>'), 'Active Tyre Yes filter should be visible in the heading');
  assert(filterHeaderHtml.includes('Oldest</small>'), 'Age / ETA heading should expose the active oldest sort');
  const partsHeaderStart = filterHeaderHtml.indexOf('pdc-grid-station-parts');
  const tintHeaderStart = filterHeaderHtml.indexOf('pdc-grid-station-tint');
  const partsHeaderHtml = filterHeaderHtml.slice(partsHeaderStart, tintHeaderStart);
  assert(!partsHeaderHtml.includes('value="no"'), 'Parts heading should not offer an impossible Not required filter');
  assert(filterHeaderHtml.includes('data-workflow-clear-column-filters'), 'Active column filters should expose a clear action in the heading row');
  app.workflowFilters = { sort: 'oldest', bucket: '', work: '', required: '', completion: '', stoppage: '' };
  applyWorkflowHeaderFilter('work', 'no', 'tyre');
  assert(app.workflowFilters.work === 'tyre' && app.workflowFilters.required === 'no', 'Selecting No from the Tyre heading should apply the Tyre no filter');
  applyWorkflowHeaderFilter('sort', 'newest');
  assert(app.workflowFilters.sort === 'newest', 'Selecting Newest from Age / ETA should update row order');

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
