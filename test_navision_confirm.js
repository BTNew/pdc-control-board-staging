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
  renderCustomers = function(){};
  function assert(condition, message) { if (!condition) throw new Error(message); }
  function row(values) { return values.join('\t'); }
  const header = row(['Order','Batch','Production Month','Model Description','Suffix Description','Trim Description','Colour Description','Customer Surname','Dealer Comments','Sub Location Description','ETA At Dealer/BB','ETA At Kewdale Yard','ETA Date','Port/Plant ETA Date','JITA PreOrder','Tray Fitment Ordered','Tray Fitment Complete','WMI','VDS Number','Frame']);
  const incomingChanged = row(['ORD1','12345678','202608','Hilux','SR','Fabric','White','MERCER','New dealer note','In Transit to WA','20/08/2026','18/08/2026','17/08/2026','16/08/2026','Yes','Yes','Yes','MR0','BA3FS2','01361094']);
  const parsed = parseNavisionInput(header + '\n' + incomingChanged);
  assert(parsed.vehicles.length === 1, 'Navision parser should read one vehicle');
  assert(parsed.vehicles[0].etaAtDealer === '18/08/2026', 'Dashboard ETA should use ETA At Kewdale Yard, not ETA At Dealer/BB');
  assert(parsed.vehicles[0].navisionEtaAtDealerBB === '20/08/2026', 'ETA At Dealer/BB should still be stored for reference');
  assert(parsed.vehicles[0].navisionEtaDate === '17/08/2026', 'ETA Date should be stored for reference');
  saveJson(EDITS_KEY, { '12345678': { buildPoRaised: true, tintRaised: true, internalStatus: 'Manual salesperson task' } });
  app.data = buildVehicleData();
  const plan = buildNavisionImportPlan(parsed);
  assert(plan.requiresConfirmation === true, 'Existing vehicle changes should require confirmation');
  assert(plan.updated.length === 1, 'One existing vehicle should be in the pending update list');
  assert(plan.updated[0].changes.some(change => change.key === 'toyotaStatus'), 'Pending review should show Toyota Status change');
  assert(app.data.find(v => v.stock === '12345678').toyotaStatus === 'Waiting PD1', 'Tracker must not change before confirmation');
  applyNavisionImportPlan(plan);
  app.data = buildVehicleData();
  const updated = app.data.find(v => v.stock === '12345678');
  assert(updated.toyotaStatus === 'In Transit to WA', 'Confirmed import should apply Navision Toyota Status');
  assert(updated.etaAtDealer === '18/08/2026', 'Confirmed import should apply Kewdale ETA, not Dealer/BB ETA');
  assert(updated.navisionEtaAtDealerBB === '20/08/2026', 'Confirmed import should preserve Dealer/BB ETA for popup reference only');
  assert(updated.navisionEtaDate === '17/08/2026', 'Confirmed import should preserve ETA Date for popup reference');
  assert(updated.prodMth === '08/26', 'Confirmed import should apply P/Month');
  assert(updated.jitaPartsOrdered === 'Yes', 'Confirmed import should apply JITA');
  assert(updated.navisionDealerComments === 'New dealer note', 'Confirmed import should apply Navision Notes');
  assert(updated.trayOrdered === true, 'Confirmed import should apply Tray Fitment Ordered');
  assert(updated.trayFitmentComplete === true, 'Confirmed import should apply Tray Fitment Complete');
  assert(plan.updated[0].changes.some(change => change.key === 'trayFitmentComplete'), 'Pending review should show Tray Fitment Complete change');
  assert(updated.buildPoRaised === true && updated.tintRaised === true, 'Protected PMB PO and Tint should survive Navision update');
  assert(updated.internalStatus === 'Manual salesperson task', 'Manual Task should survive Navision update');

  // If Kewdale is blank, leave dashboard ETA blank. Do not use ETA Date, Port/Plant or Dealer/BB.
  localStorage.clear();
  app.data = buildVehicleData();
  const incomingEtaDateOnly = row(['ORD1','12345678','202608','Hilux','SR','Fabric','White','MERCER','ETA Date only','In Transit to WA','30/08/2026','','22/08/2026','21/08/2026','Yes','No','No','MR0','BA3FS2','01361094']);
  const parsedEtaDate = parseNavisionInput(header + '\n' + incomingEtaDateOnly);
  assert(parsedEtaDate.vehicles[0].etaAtDealer === '', 'When Kewdale is blank, dashboard ETA should stay blank and ignore ETA Date, Port/Plant and Dealer/BB');

  // Selected-only apply should skip unselected existing updates but still add new vehicles.
  localStorage.clear();
  app.data = buildVehicleData();
  const incomingNew = row(['ORD2','87654321','202609','RAV4','GXL','','Blue','NEW CUSTOMER','','Planned for Production','29/09/2026','21/09/2026','','','No','No','No','JTM','AAAAAA','12345678']);
  const parsed2 = parseNavisionInput(header + '\n' + incomingChanged + '\n' + incomingNew);
  const plan2 = buildNavisionImportPlan(parsed2);
  assert(plan2.requiresConfirmation === true, 'Mixed existing/new import should still require confirmation');
  applyNavisionImportPlan(plan2, new Set());
  app.data = buildVehicleData();
  assert(app.data.find(v => v.stock === '12345678').toyotaStatus === 'Waiting PD1', 'Unselected existing update should not apply');
  assert(app.data.some(v => v.stock === '87654321'), 'New vehicle should still be added after selected-only confirmation');

  // PMB-only import should accept rows with a Body Builder signal and skip plain Navision rows.
  const pmbOnlyHeader = row(['Order','Batch','Production Month','Model Description','Body Builder','Tray Fitment Ordered']);
  const pmbOnlyMatch = row(['ORD3','33333333','202610','Landcruiser','2','No']);
  const pmbOnlySkip = row(['ORD4','44444444','202610','Corolla','','No']);
  const parsedPmbOnly = parseNavisionInput(pmbOnlyHeader + '\n' + pmbOnlyMatch + '\n' + pmbOnlySkip, { pmbOnly: true });
  assert(parsedPmbOnly.vehicles.length === 1, 'PMB-only import should keep only rows with PMB/body-builder work signals');
  assert(parsedPmbOnly.vehicles[0].stock === '33333333', 'PMB-only import should keep the body-builder row');
  assert(parsedPmbOnly.warnings.some(warning => warning.includes('44444444') && warning.includes('skipped')), 'PMB-only import should report skipped non-PMB rows');

  console.log('Navision confirmation tests passed');
})();
`;
const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [{
    id: 'base-1', stock: '12345678', batch: '12345678', order: 'ORD1', client: 'MERCER', toyotaCustomer: 'MERCER', vehicle: 'Hilux SR', toyotaVehicle: 'Hilux', suffix: 'SR', trim: 'Fabric', colour: 'White', prodMth: '07/26', toyotaStatus: 'Waiting PD1', etaAtDealer: '19/08/2026', source: 'Navision', jitaPartsOrdered: 'No', trayOrdered: false
  }], toyotaMatches: {}, report: {} } },
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
      if (selector === '#search') return { value: '' };
      if (selector === '#source-filter') return { value: '' };
      return null;
    },
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{add(){},remove(){},toggle(){}} })
  },
  navigator: {},
  FileReader: function(){},
  Blob: function(){},
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
  window_alerts: [],
};
context.window.alert = msg => context.window_alerts.push(msg);
context.window.confirm = () => true;
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
