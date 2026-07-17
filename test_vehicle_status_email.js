const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  function check(condition, message) { if (!condition) throw new Error(message); }
  // Stage 2A: salespeople are now Supabase-backed via
  // workshop-reference-data-service.js, not localStorage. Stub a fake
  // reference-data service seeded with the same DEFAULT_SALESPERSONS
  // directory this test previously relied on via SALESPERSONS_KEY
  // auto-seeding, so salespersonEmail()/loadSalespersons() resolve
  // through the real production code path.
  const fakeSalespersonRows = DEFAULT_SALESPERSONS.map((record, index) => ({
    id: 'fake-salesperson-' + index, name: record.name, email: record.email, code: record.initials, active: true, version: 1, sort_order: index,
  }));
  window.__workshopReferenceDataService = {
    getCachedSalespeople: () => ({ rows: fakeSalespersonRows, state: 'connected_editable', error: null }),
  };
  const vehicle = {
    id: 'email-vehicle-1',
    stock: '12663543',
    batch: '12663543',
    order: 'PO-EMAIL-1',
    client: 'Broome Customer',
    vehicle: 'Toyota Hilux DCC SR',
    consultant: 'Craig Wilson',
    salespersonEmail: 'craig@example.com',
    source: 'Manual',
    recordLifecycle: 'manual',
    pdcSheetVisible: true,
    pdcJobcard: 'JC-1234',
    pdcLocation: 'PMB',
    pmbStage: 'ELECTRICAL',
    pmbBayStage: 'ELECTRICAL',
    pmbBayNumber: '3',
    toyotaStatus: 'Delivered - At Body Builder',
    etaAtDealer: '22/07/2026',
    pdcRequiresTint: true,
    pdcCompleteTint: true,
    pdcCompleteTintAt: '2026-07-13T03:00:00.000Z',
    pdcCompleteTintBy: 'AB',
    pdcCompleteTintMechanic: 'Alex Mechanic',
    pdcCompleteTintBay: '2',
    pdcCompleteTintHours: '1.5',
    pdcRequiresElectrical: true,
    pdcCompleteElectrical: false,
    pdcPartsOrdered: true,
    pdcPartsWorstEta: '2026-07-20',
  };
  saveAuditLog([{
    id: 'audit-1',
    at: '2026-07-13T02:00:00.000Z',
    action: 'Assigned to PMB bay',
    vehicleKey: vehicleKey(vehicle),
    stock: vehicle.stock,
    details: { stage: 'Tint', bay: 'Bay 2', mechanic: 'Alex Mechanic' },
  }]);
  const body = vehicleStatusUpdateEmailBody(vehicle);
  check(body.includes('Parts status: On Order'), 'Status email should include the current Parts state');
  check(body.includes('Parts ETA: 20/07/2026'), 'Status email should include Parts ETA when Parts is not issued');
  check(body.includes('Assigned to PMB bay') && body.includes('Bay 2'), 'Status email should include workshop/bay history');
  check(body.includes('TINT') && body.includes('Alex Mechanic'), 'Status email should include completed work and mechanic details');
  check(body.includes('ELEC') && body.includes('PARTS'), 'Status email should include outstanding work');
  check(body.includes('Current PMB area: Elec · Bay 3'), 'Status email should include the current PMB area and bay');
  check(body.includes('IMPORTANT UPDATE: PARTS ETA / DELAY UPDATE'), 'Status email should prominently identify the Parts delay reason');
  check(!body.includes('Toyota Order:'), 'Status email should not include the Toyota order number');
  check(salespersonEmail({ consultant: 'CW' }) === 'craig.watson@broometoyota.com.au', 'CW should resolve through the salesperson directory');
  check(salespersonEmail({ consultant: 'Craig Wilson', salespersonEmail: 'craig@example.com' }) === 'craig@example.com', 'An explicit vehicle salesperson email must not be replaced by a same-initials directory entry');
  console.log('Vehicle status email tests passed');
})();
`;

const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} }, location: { href: '' } },
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
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, style: {}, classList: { add(){}, remove(){}, toggle(){} } }),
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

assert.ok(true);
