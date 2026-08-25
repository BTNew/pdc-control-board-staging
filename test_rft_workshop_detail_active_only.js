'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function vehicleWorkshopDetailSupportsVehicle');
const end = source.indexOf('\nfunction selectVehicleDetailPage', start);
assert.ok(start > 0 && end > start, 'Workshop detail lifecycle guard must be extractable');
const rftId = '00000000-0000-4000-8000-000000000451';
const activeId = '00000000-0000-4000-8000-000000000452';
let fetchCalls = 0;
const context = {
  app: { vehicleWorkshopDetailCache: new Map(), vehicleWorkshopDetailRequestGeneration: 0, vehicleDetailPage: 'details' },
  window: { PDC_SUPABASE_CONFIG: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public-test-key' } },
  getPdcSupabaseAccessToken: () => 'test-token',
  vehicleWorkshopDetailCanonicalId: vehicle => String(vehicle.__emailVehicleId || ''),
  vehicleKey: vehicle => String(vehicle.__emailVehicleId || ''),
  selectedVehicle: () => null,
  renderDetail: () => {},
  fetch: async (_url, options) => {
    fetchCalls += 1;
    const requested = JSON.parse(options.body).p_vehicle_id;
    return { ok: true, status: 200, json: async () => ({ vehicle_id: requested, requirements: [], bookings: [] }) };
  },
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
(async () => {
  const rft = { __emailVehicleId: rftId, lifecycleState: 'rft', pdcLocation: 'RFT' };
  assert.equal(context.vehicleWorkshopDetailSupportsVehicle(rft), false);
  assert.equal(await context.loadVehicleWorkshopDetail(rft, { force: true }), null);
  assert.equal(fetchCalls, 0, 'RFT modal must not issue an RPC that the active-only contract rejects');
  assert.equal(context.app.vehicleWorkshopDetailCache.get(rftId).status, 'error');
  assert.match(context.app.vehicleWorkshopDetailCache.get(rftId).message, /unavailable after this vehicle leaves the active PMB lifecycle/);
  const active = { __emailVehicleId: activeId, lifecycleState: 'active', pdcLocation: 'PMB' };
  assert.equal(context.vehicleWorkshopDetailSupportsVehicle(active), true);
  const detail = await context.loadVehicleWorkshopDetail(active, { force: true });
  assert.equal(fetchCalls, 1, 'active vehicle keeps the established Workshop detail request');
  assert.equal(detail.vehicle_id, activeId, 'email projection UUID remains the canonical RPC identity');
  assert.equal(context.app.vehicleWorkshopDetailCache.get(activeId).status, 'ready');
  assert.match(source, /\[vehicle\.__emailVehicleId, vehicle\.sharedVehicleId, vehicle\.__sharedNavisionCanonicalVehicleId/, 'identity precedence remains unchanged');
  console.log('RFT Workshop detail active-only suppression contract: PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
