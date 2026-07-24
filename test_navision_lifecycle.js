const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  renderAll = function(){};
  populateFilters = function(){};
  renderNavisionSummary = function(){};
  updateNavisionControlStats = function(){};
  updateNavisionImportButton = function(){};
  updateNavisionSidebarMeta = function(){};
  renderKpis = function(){};
  renderVehicleTable = function(){};
  renderKanban = function(){};
  renderWorkflowBoard = function(){};
  renderTvBoard = function(){};
  renderScheduleBoard = function(){};
  renderPartsHome = function(){};
  renderRftHome = function(){};
  renderCompletedVehicles = function(){};
  renderIncomingDashboardBoard = function(){};
  renderAdminLists = function(){};
  renderCustomers = function(){};
  renderReviewTable = function(){};

  function assert(condition, message) { if (!condition) throw new Error(message); }
  function row(values) { return values.join('\t'); }
  const header = row(['Order','Batch','Model Description','Dealer Comments','Sub Location Description','ETA At Kewdale Yard','JITA PreOrder']);
  const backEndDay1 = row(['BE-1','90000001','Corolla','','Planned for Production','20/07/2026','']);
  const pdcDay1 = row(['PDC-1','90000002','Hilux','Purchase order for tray','In Transit to WA','21/07/2026','JITA-9002']);

  const day1 = parseNavisionInput(header + '\n' + backEndDay1 + '\n' + pdcDay1);
  assert(day1.vehicles.length === 2, 'Day-one Navision file should parse both vehicles');
  assert(day1.vehicles.find(v => v.stock === '90000001').pdcSheetVisible === false, 'A plain Navision vehicle should start in the back end only');
  assert(day1.vehicles.find(v => v.stock === '90000002').pdcSheetVisible === false, 'Even Navision rows mentioning PDC/PO work should remain back-end-only in a daily import');
  applyNavisionImportPlan(buildNavisionImportPlan(day1));
  app.data = buildVehicleData();
  assert(app.data.length === 2, 'Both Navision vehicles should be retained in active back-end data');
  assert(pdcSheetVehicles().length === 0, 'A daily Navision import must not place any new vehicle on the PDC Sheet');

  const workHeader = row(['Stock Number','Job Card']);
  const workFile = parseNavisionInput(workHeader + '\n' + row(['90000002','JC-9002']), { pmbOnly: true });
  assert(workFile.vehicles.length === 1 && workFile.vehicles[0].pdcJobcard === 'JC-9002', 'A separate job-card file should identify the matching back-end vehicle');
  applyNavisionImportPlan(buildNavisionImportPlan(workFile));
  app.data = buildVehicleData();
  assert(pdcSheetVehicles().length === 1 && pdcSheetVehicles()[0].stock === '90000002', 'The separate job-card file should promote its vehicle to the PDC Sheet');
  const jobCardPromoted = app.data.find(v => v.stock === '90000002');
  assert(jobCardPromoted.etaAtDealer === '21/07/2026' && jobCardPromoted.jitaPartsOrdered === 'Yes' && jobCardPromoted.jitQty === 'JITA-9002', 'A work/job file must not blank the daily Navision ETA or JITA number');

  const backEndDay2 = row(['BE-1','90000001','Corolla','','In Transit to WA','25/07/2026','JITA-9001']);
  const pdcDay2 = row(['PDC-1','90000002','Hilux','Purchase order for tray','Vehicle Yard Hold','26/07/2026','']);
  const activationDay2 = row(['ACTIVE-5','90000005','Kluger','','Planned for Production','28/07/2026','']);
  const bodyBuilderDay2 = row(['ACTIVE-6','90000006','LandCruiser','Tint, wheels, tray and electrical mentioned in a Navision note','At Body Builder','29/07/2026','JITA-9006']);
  const day2 = parseNavisionInput(header + '\n' + backEndDay2 + '\n' + pdcDay2 + '\n' + activationDay2 + '\n' + bodyBuilderDay2);
  applyNavisionImportPlan(buildNavisionImportPlan(day2));
  app.data = buildVehicleData();
  const refreshedBackEnd = app.data.find(v => v.stock === '90000001');
  assert(refreshedBackEnd.etaAtDealer === '25/07/2026', 'Daily Navision should refresh Kewdale ETA on a back-end-only vehicle');
  assert(refreshedBackEnd.jitaPartsOrdered === 'Yes' && refreshedBackEnd.jitQty === 'JITA-9001', 'Daily Navision should refresh the authoritative JITA number on a back-end-only vehicle');
  assert(isVehicleVisibleOnPdcSheet(app.data.find(v => v.stock === '90000002')), 'A later daily Navision upload must not hide a job-card-promoted vehicle');

  const backEndToActivate = app.data.find(v => v.stock === '90000005');
  assert(backEndToActivate && !isVehicleVisibleOnPdcSheet(backEndToActivate), 'A normal Navision vehicle should be searchable as back-end-only before manual activation');
  transferBackEndVehicleToActive('90000005');
  const activated = app.data.find(v => v.stock === '90000005');
  assert(activated.pdcSheetVisible === true && isVehicleVisibleOnPdcSheet(activated), 'Move to active should promote a back-end vehicle to the PDC Sheet');
  assert(activated.pdcVisibilitySource === 'Operator transfer from Back End Data', 'Manual activation should store durable promotion provenance');

  const bodyBuilderBackEnd = app.data.find(v => v.stock === '90000006');
  assert(bodyBuilderBackEnd && !isVehicleVisibleOnPdcSheet(bodyBuilderBackEnd), 'A Body Builder Navision row should remain back-end-only until activated');
  transferBackEndVehicleToActive('90000006');
  let bodyBuilderActive = app.data.find(v => v.stock === '90000006');
  assert(vehiclePdcLocation(bodyBuilderActive) === 'PMB', 'Activating a Body Builder vehicle should place it at PMB');
  assert(currentPdcLocationFromNavision({ navisionBuildStatus: 'BODYBUILDER' }) === 'PMB', 'A Body Builder value supplied in the Navision build-status field should also map to PMB');
  assert(inferredPmbStage(bodyBuilderActive) === '', 'A Body Builder activation should land in PMB Unallocated, not an inferred work bucket');
  assert(PDC_JOB_DEFS.filter(def => def.key !== 'parts').every(def => !pdcJobRequired(bodyBuilderActive, def)), 'Navision notes must not automatically tick non-Parts work boxes');
  assert(pdcJobRequired(bodyBuilderActive, PDC_JOB_BY_KEY.get('parts')), 'A real stock/batch number should retain the standard Parts gate');
  assert(pdcJobRequired({ ...bodyBuilderActive, pdcRequiresTint: true }, PDC_JOB_BY_KEY.get('tint')), 'An explicit imported/operator work requirement must still tick its matching box');

  const bodyBuilderDay3 = parseNavisionInput(header + '\n' + row(['ACTIVE-6','90000006','LandCruiser','','Vehicle Yard Hold','01/08/2026','No']));
  applyNavisionImportPlan(buildNavisionImportPlan(bodyBuilderDay3));
  app.data = buildVehicleData();
  bodyBuilderActive = app.data.find(v => v.stock === '90000006');
  assert(vehiclePdcLocation(bodyBuilderActive) === 'YH', 'A later Navision refresh should update a Navision-derived active location until staff manually lock it');

  const promoted = ensureVehicleForPo('90000001');
  assert(promoted.pdcSheetVisible === true && isVehicleVisibleOnPdcSheet(promoted), 'Loading a PO should permanently promote an existing back-end vehicle to the PDC Sheet');
  app.data = buildVehicleData();
  assert(pdcSheetVehicles().length === 4, 'The PO-promoted vehicle should now be visible with the job-card and both manually activated vehicles');

  const manualVehicle = {
    id: 'manual-keep', stock: '90000003', batch: '90000003', vehicle: 'Toyota Prado', source: 'Manual',
    recordLifecycle: 'manual', pdcSheetVisible: true, pdcVisibilitySource: 'Manual vehicle entry'
  };
  const added = loadAddedVehicles();
  added.unshift(manualVehicle);
  saveAddedVehicles(added);
  app.data = buildVehicleData();
  const missingAfterEmptyDump = vehiclesMissingFromNavisionImport(app.data, [], { fullRefresh: true });
  assert(missingAfterEmptyDump.length === 0, 'Manual, PO-promoted and PDC vehicles must not be cleanup candidates');

  const plainBackEnd = {
    id: 'navision-90000004', stock: '90000004', batch: '90000004', vehicle: 'Toyota Yaris', source: 'Navision',
    recordLifecycle: 'navision', pdcSheetVisible: false, pdcVisibilitySource: 'Navision back end only'
  };
  const addedAgain = loadAddedVehicles();
  addedAgain.unshift(plainBackEnd);
  saveAddedVehicles(addedAgain);
  app.data = buildVehicleData();
  const eligible = vehiclesMissingFromNavisionImport(app.data, [], { fullRefresh: true });
  assert(eligible.length === 1 && eligible[0].stock === '90000004', 'Only the unpromoted Navision-only back-end vehicle should be eligible for retirement');
  removeVehiclesFromTracker(eligible, { deletionType: 'navision-missing', reason: 'Missing from full Navision upload' });
  app.data = buildVehicleData();
  assert(!app.data.some(v => v.stock === '90000004'), 'A missing Navision-only back-end vehicle should retire from active data');
  assert(deletedVehicleRecords().some(record => record.vehicle.stock === '90000004' && record.deletionType === 'navision-missing'), 'Automatic retirement should keep a typed Deleted record');

  const returning = parseNavisionInput(header + '\n' + row(['BE-4','90000004','Yaris','','Planned for Production','30/07/2026','No']));
  applyNavisionImportPlan(buildNavisionImportPlan(returning));
  app.data = buildVehicleData();
  assert(app.data.some(v => v.stock === '90000004'), 'A Navision-missing retirement should restore if the vehicle returns in a later upload');

  const manualToDelete = app.data.find(v => v.stock === '90000003');
  removeVehiclesFromTracker([manualToDelete]);
  app.data = buildVehicleData();
  const manualReturn = parseNavisionInput(header + '\n' + row(['MAN-3','90000003','Prado','','Planned for Production','31/07/2026','Yes']));
  applyNavisionImportPlan(buildNavisionImportPlan(manualReturn));
  app.data = buildVehicleData();
  assert(!app.data.some(v => v.stock === '90000003'), 'A vehicle explicitly deleted by an operator must not be recreated by Navision');

  console.log('Navision lifecycle tests passed');
})();
`;

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
    querySelector: selector => {
      if (selector === '#navision-remove-missing') return { checked: false };
      if (selector === '#navision-pmb-only') return { checked: false };
      if (selector === '#search') return { value: '' };
      if (selector === '#source-filter') return { value: '' };
      return null;
    },
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{add(){},remove(){},toggle(){}} })
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
