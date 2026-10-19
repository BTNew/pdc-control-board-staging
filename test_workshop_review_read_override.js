'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const review = require('./pdc-review-stations.js');
const app = fs.readFileSync('app.js', 'utf8');
const context = { cleanNavisionText: v => String(v || '').trim() };
vm.runInNewContext(app.slice(app.indexOf('function vehicleWorkshopDetailRequestDealerCode('), app.indexOf('\nfunction vehicleWorkshopDetailResponse(')), context);
const original = context.vehicleWorkshopDetailRequestDealerCode;
const config = { projectRef: 'cdsmnqxtyyoeoznmbidd', dealerCode: '14450' };
const vehicle = { __emailVehicleServerAuthoritative: true, __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  stock: 'TEST-READ', source: 'tune_pmg', pdcDepartmentCodes: ['139'], pdcHasUnknownDepartment: false, pdcSheetVisible: true };
test('the installed Review read wrapper retains the commissioned accepted PMG request scope', () => {
  for (const source of ['tune_pmg', 'microsoft_navision']) for (const dealer_code of ['', 'CUSTOMER_ACCOUNT']) {
    const v = { ...vehicle, source, dealer_code };
    assert.equal(review.resolveDealerScope(v, []), '', 'Old resolver reproduces the browser failure');
    assert.equal(review.resolveReadDealerScope(v, [], null, config, original), '14450');
  }
  assert.match(fs.readFileSync('pdc-review-stations.js', 'utf8'), /return resolveReadDealerScope\(vehicle, app\.sharedNavisionVisibleRows, app\.vehicleModalIdentity, config, oldDealerScope\)/);
});
test('read fallback retains source, project, department and exact vehicle/dealer denials', () => {
  for (const patch of [{source:'untrusted'}, {pdcDepartmentCodes:['135']}, {pdcDepartmentCodes:[]},
    {pdcHasUnknownDepartment:true}, {pdcSheetVisible:false}, {__emailVehicleId:'not-a-uuid'}, {stock:''}]) {
    assert.equal(review.resolveReadDealerScope({...vehicle,...patch}, [], null, config, original), '');
  }
  for (const cfg of [{...config, projectRef:'other'}, {...config, dealerCode:'37047'}])
    assert.equal(review.resolveReadDealerScope(vehicle, [], null, cfg, original), '');
  const row = { canonical_vehicle_id:vehicle.__emailVehicleId, stock_number:vehicle.stock, is_current:true, record_status:'current', dealer_code:'37047' };
  assert.equal(review.resolveReadDealerScope({...vehicle,dealerCode:'14450'}, [row], null, config, original), '');
  assert.equal(review.resolveReadDealerScope(vehicle, [{...row,dealer_code:'CUSTOMER_ACCOUNT',stock_number:'OTHER'}], null, config, original), '');
  assert.equal(review.resolveReadDealerScope(vehicle, [], {canonicalId:vehicle.__emailVehicleId,stockBaseline:'OTHER',dealerCode:'14450'}, config, original), '');
});

test('loading the actual Review module after the main page does not undo its accepted PMG read support', () => {
  const runtime = vm.createContext({
    cleanNavisionText: v => String(v || '').trim(),
    window: { PDC_SUPABASE_CONFIG: config, addEventListener() {} },
    document: { querySelector: () => null, querySelectorAll: () => [], addEventListener() {} },
    app: { sharedNavisionVisibleRows: [], vehicleModalIdentity: null },
    renderQualityControlPage() {}, authenticatedEmailOperationLinesHtml: () => '', renderVehicleWorkshopWorkPage: () => '',
  });
  vm.runInContext(app.slice(app.indexOf('function vehicleWorkshopDetailRequestDealerCode('), app.indexOf('\nfunction vehicleWorkshopDetailResponse(')), runtime);
  const before = runtime.vehicleWorkshopDetailRequestDealerCode;
  vm.runInContext(fs.readFileSync('pdc-review-stations.js', 'utf8'), runtime);
  assert.notEqual(runtime.vehicleWorkshopDetailRequestDealerCode, before, 'Exercise the installed override, not only its exported helper');
  for (const source of ['tune_pmg', 'microsoft_navision']) {
    assert.equal(runtime.vehicleWorkshopDetailRequestDealerCode({...vehicle, source}, config), '14450');
    assert.equal(runtime.vehicleWorkshopDetailRequestDealerCode({...vehicle, source, dealer_code:'CUSTOMER_ACCOUNT'}, config), '14450');
  }
  runtime.app.sharedNavisionVisibleRows = [{canonical_vehicle_id:vehicle.__emailVehicleId, stock_number:'OTHER', is_current:true, record_status:'current',dealer_code:'14450'}];
  assert.equal(runtime.vehicleWorkshopDetailRequestDealerCode(vehicle, config), '');
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-review-stations\.js\?[^']*pmg-read=2026\.10\.19\.01/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"\n]*pmg-read=2026\.10\.19\.01/);
});
