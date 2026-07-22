const fs = require('fs');
const path = require('path');
const vm = require('vm');

const styles = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');
const operationalPartsCss = styles.slice(styles.indexOf('/* Operational readiness — Parts'));
if (!/max-height:\s*none(?:\s*!important)?;/.test(operationalPartsCss) || !/overflow:\s*visible(?:\s*!important)?;/.test(operationalPartsCss)) {
  throw new Error('Parts must use page scrolling rather than a nested table scrollbar');
}
if (!operationalPartsCss.includes('border: 0 !important;') || !operationalPartsCss.includes('box-shadow: none !important;')) {
  throw new Error('Parts must use the continuous unboxed Vehicle Locations presentation');
}

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  function assert(condition, message) { if (!condition) throw new Error(message); }

  const elements = new Map();
  function elementFor(selector) {
    if (!elements.has(selector)) {
      elements.set(selector, {
        value: '',
        innerHTML: '',
        hidden: false,
        textContent: '',
        disabled: false,
        addEventListener(){},
        querySelector(){ return null; },
        querySelectorAll(){ return []; },
        classList: { add(){}, remove(){}, toggle(){} },
      });
    }
    return elements.get(selector);
  }
  document.querySelector = selector => elementFor(selector);
  document.querySelectorAll = () => [];
  document.createElement = () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{add(){},remove(){},toggle(){}} });

  const basePartsVehicle = { id: 'parts-1', stock: '12345678', batch: '12345678', order: 'ORD1', client: 'Customer One', consultant: 'Sales Person', vehicle: 'Hilux', toyotaStatus: 'Vehicle Yard Hold' };
  assert(partsDepartmentStatus(basePartsVehicle) === 'notordered', 'Parts with no order should show Not Ordered');
  assert(partsDepartmentStatus({ ...basePartsVehicle, pdcPartsOrdered: true }) === 'onorder', 'Ordered parts should show On Order');
  assert(partsDepartmentStatus({ ...basePartsVehicle, pdcCompleteParts: true }) === 'issued', 'Signed-off parts should show Issued');
  assert(partsDepartmentStatus({ ...basePartsVehicle, pdcPartsReceived: true }) === 'issued', 'Received parts should be treated as Issued and removed from the Parts queue');
  assert(partsDepartmentStatus({ ...basePartsVehicle, pdcCompleteParts: true, pdcPartsMiscAcc: true }) === 'miscacc', 'Misc Acc must override other Parts statuses');
  assert(matchesQuickFilter('partsstoppage')({ ...basePartsVehicle, pdcPartsStoppage: true }), 'Parts stoppage dashboard bucket should include vehicles with a parts stoppage flag');
  assert(matchesQuickFilter('partsstoppage')({ ...basePartsVehicle, pdcPartsStoppageReason: 'Waiting on bullbar' }), 'Parts stoppage dashboard bucket should include vehicles with a parts stoppage reason');
  assert(!matchesQuickFilter('partsstoppage')({ ...basePartsVehicle, pdcPartsStoppage: true, pdcCompleteParts: true }), 'Completed Parts should not stay in the active stoppage bucket');
  app.quickFilter = 'partsstoppage';
  assert(quickFilterLabel() === 'Parts Stoppage vehicles', 'Parts stoppage quick filter should have a dashboard table heading');
  app.quickFilter = 'batchmatched';

  const partsDef = PDC_JOB_BY_KEY.get('parts');
  const subletDef = PDC_JOB_BY_KEY.get('sublet');
  assert(subletDef && subletDef.requireKey === 'pdcRequiresSublet' && subletDef.completeKey === 'pdcCompleteSublet', 'Sublet must be restored as a required/completed row work control');
  assert(pdcJobTriState({ pdcRequiresSublet: true }, subletDef) === 'required', 'A required incomplete Sublet must show the red required state');
  assert(pdcJobTriState({ pdcRequiresSublet: true, pdcCompleteSublet: true }, subletDef) === 'complete', 'A completed Sublet must show the green complete state');
  assert(JSON.stringify(pdcJobDefsPartsFirst().map(def => def.key)) === JSON.stringify(['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'pitInspection']), 'Vehicle rows must use the requested Parts/Tint/Bus 4x4/Hoist/Fitting/Fab/Elec/Tyre/Sublet/Pit order');
  assert(pdcJobTableCell(basePartsVehicle, partsDef).includes('parts-visual-notordered'), 'Dashboard Parts tick should be greyed when parts are required but not ordered');
  assert(pdcJobTableCell({ ...basePartsVehicle, pdcPartsOrdered: true }, partsDef).includes('parts-visual-onorder'), 'Dashboard Parts tick should show ordered/confirmed state');
  const issuedPartsCell = pdcJobTableCell({ ...basePartsVehicle, pdcCompleteParts: true }, partsDef);
  assert(issuedPartsCell.includes('parts-visual-issued'), 'Dashboard Parts tick should show received/issued state');
  assert(issuedPartsCell.includes('checked'), 'Received/issued Parts tick should remain checked');
  assert(!pdcJobTableCell(basePartsVehicle, PDC_JOB_BY_KEY.get('build')).includes('parts-visual-'), 'Parts visual classes must not leak onto other job ticks');

  const fittingBayVehicle = {
    ...basePartsVehicle,
    pdcLocation: 'PMB',
    pmbStage: 'FITTING',
    pmbBayStage: 'FITTING',
    pmbBayNumber: 3,
    pmbBayEnteredAt: '2026-07-15T01:30:00.000Z',
    pdcPartsOrderedAt: '2026-07-15T02:30:00.000Z',
  };
  assert(partsCurrentLocationLabel(fittingBayVehicle) === 'Fitting · Bay 03', 'Parts must show the current PMB station and numbered bay');
  assert(partsCurrentLocationLabel({ ...basePartsVehicle, pdcLocation: 'PMB', pmbStage: '' }) === 'PMB · Unallocated', 'Parts must identify PMB vehicles that are not allocated to a station');
  assert(partsCurrentLocationLabel({ ...basePartsVehicle, pdcLocation: 'YH' }) === 'Yard Hold', 'Parts must show Yard Hold as the current location');
  const expectedLocationUpdate = new Date('2026-07-15T01:30:00.000Z').toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' });
  assert(partsCurrentLocationUpdateLabel(fittingBayVehicle) === expectedLocationUpdate, 'Stage / update must use the station/location movement timestamp');
  assert(partsCurrentLocationUpdateLabel(fittingBayVehicle) !== partsLastUpdateLabel(fittingBayVehicle), 'A later Parts action must not replace the location movement timestamp');

  const stalePmbVehicle = { ...basePartsVehicle, pdcLocation: 'PMB', pmbStage: 'SUBLET', pmbStageEnteredAt: '2000-01-01T00:00:00.000Z', pdcRequiresSublet: true, pdcBlockReason: 'Waiting on contractor' };
  const visibility = operationalVisibilityMetrics([basePartsVehicle, stalePmbVehicle]);
  assert(visibility.openThirdParty === 1, 'Operational visibility should count open third-party work');
  assert(visibility.stagnant === 1, 'Operational visibility should count stagnant or blocked workflow');
  assert(visibility.rftGateIssues === 1, 'Operational visibility should count manual RFT gate issues');

  app.data = [basePartsVehicle, { ...basePartsVehicle, id: 'parts-issued', stock: '87654321', batch: '87654321', pdcCompleteParts: true }, { ...basePartsVehicle, id: 'parts-received', stock: '11223344', batch: '11223344', pdcPartsReceived: true }];
  elementFor('#parts-search').value = 'Sales Person';
  elementFor('#parts-status-filter').value = 'all';
  assert(partsDepartmentRows().length === 0, 'Parts search must not match salesperson/staff fields');

  elementFor('#parts-search').value = '';
  assert(partsDepartmentRows().length === 1, 'Issued/received Parts vehicles must be removed from the Parts screen active/all filters');
  elementFor('#parts-status-filter').value = 'issued';
  assert(partsDepartmentRows().length === 1, 'Legacy Issued filter must not reveal issued Parts vehicles on the Parts screen');
  elementFor('#parts-status-filter').value = 'open';
  renderPartsHome();
  const partsHtml = elementFor('#parts-home-content').innerHTML;
  const partsSummaryHtml = elementFor('#parts-summary-grid').innerHTML;
  assert(!partsSummaryHtml.includes('Issued'), 'Parts page summary must not show an Issued shortcut/card');
  assert(!/<th>Sales<\/th>/.test(partsHtml), 'Parts page must not render a Sales column');
  assert(!partsHtml.includes('Sales Person'), 'Parts page must not render salesperson names');
  app.data = [fittingBayVehicle];
  renderPartsHome();
  assert(elementFor('#parts-home-content').innerHTML.includes('Fitting · Bay 03'), 'The Parts Stage / Update cell must render the current station and bay');

  const etaVehicle = { ...basePartsVehicle, pdcPartsWorstEta: '2099-01-01' };
  assert(partsWorstEtaCountdownLabel(etaVehicle).includes('to Parts ETA'), 'Parts worst ETA should show a countdown label');
  assert(partsWorstEtaCountdownClass(etaVehicle) === 'later', 'Future Parts ETA countdown should be classed as later');
  app.data = [{ ...basePartsVehicle, pdcPartsWorstEta: '2099-01-01' }];
  elementFor('#parts-status-filter').value = 'open';
  renderPartsHome();
  assert(elementFor('#parts-home-content').innerHTML.includes('Email sales'), 'Parts ETA rows with a worst ETA should show an Email sales action');
  let mailtoHref = '';
  window.prompt = () => 'Parts';
  Object.defineProperty(window.location, 'href', { set(value) { mailtoHref = String(value); }, get() { return mailtoHref; }, configurable: true });
  app.data = [{ ...basePartsVehicle, pdcPartsWorstEta: '2099-01-01', pdcPartsPreviousWorstEta: '2098-12-20' }];
  draftPartsEtaSalesEmail('12345678');
  const decodedMail = decodeURIComponent(mailtoHref);
  assert(decodedMail.includes('Previous Parts ETA:'), 'Parts ETA sales email must include previous ETA');
  assert(decodedMail.includes('New Parts ETA:'), 'Parts ETA sales email must include new ETA');
  assert(decodedMail.includes('Revised countdown:'), 'Parts ETA sales email must include revised countdown');
  assert(decodedMail.includes('Stock number: 12345678'), 'Parts ETA sales email must include vehicle details');

  const confirms = [];
  window.confirm = message => { confirms.push(String(message)); return true; };
  window.prompt = () => 'Parts';
  window.setInterval = () => 0;
  window.clearInterval = () => {};
  renderAll = () => {};
  populateFilters = () => {};
  window.alert = message => { throw new Error('Unexpected alert: ' + message); };
  const qcPendingVehicle = { ...basePartsVehicle, pdcLocation: 'PMB', manualLocation: 'PMB', pmbStage: '', pdcCompleteParts: true };
  const qcPendingIssues = vehicleRftGateIssues(qcPendingVehicle);
  assert(qcPendingIssues.includes('QC sign-off required'), 'Unallocated vehicles must wait for final QC before RFT');
  assert(!qcPendingIssues.includes('No PMB bucket assigned'), 'PMB Unallocated must not itself block RFT');
  const rftVehicle = { ...qcPendingVehicle, pdcQcComplete: true };
  assert(vehicleRftGateIssues(rftVehicle).length === 0, 'A QC-complete PMB Unallocated vehicle with all required work complete must be RFT eligible');
  transferVehiclesToRft([rftVehicle], { clearSelection: false });
  assert(confirms.length === 1, 'RFT transfer should only ask for transfer confirmation');
  assert(!confirms.some(message => /sales\s*person|salesperson/i.test(message)), 'RFT transfer must not prompt for salesperson notification');

  console.log('Parts/production principle tests passed');
})();
`;

const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} }, location: {} },
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
};
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });

