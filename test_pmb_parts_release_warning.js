'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const service = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync('app.js', 'utf8');
function fn(name) {
  const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
  assert.ok(match, name);
  const rest = source.slice(match.index);
  const next = /\n(?:async )?function /.exec(rest);
  return next ? rest.slice(0, next.index) : rest;
}
function vehicle(extra = {}) {
  return service.mapServerVehicle({ id: '11111111-1111-4111-8111-111111111111', version: 3,
    stock_number: '13021292', customer_name: 'Test customer', current_location: 'YH', ...extra });
}
function context(row = vehicle(), accept = true) {
  const calls = [], prompts = [], alerts = [];
  const ctx = { PDC_JOB_BY_KEY: new Map([['parts', { key: 'parts', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' }]]),
    displayStockNumber: v => v.stock, selectedVehicle: () => row,
    sharedVehicleLocationMutationUnavailable: () => false, vehicleLocationActionAllowed: () => true,
    canTransferVehicleToPmb: () => true, vehicleCustomerName: v => v.client,
    vehicleLifecycleSharedModeActive: () => true,
    app: {}, renderAll() {}, refreshEmailVehicleLocations: async () => {},
    reconcileVehicleLifecycleServerResult(v, r) { Object.assign(v, r.vehicle); },
    window: { confirm(message) { prompts.push(message); return accept; }, alert: m => alerts.push(m),
      __vehicleLifecycleActions: { pmbTransferVehicle: async payload => {
        calls.push(JSON.parse(JSON.stringify(payload))); return { ok: true, vehicle: { pdcLocation: 'PMB' } };
      } } },
  };
  vm.createContext(ctx);
  vm.runInContext(['isBlankStock', 'vehicleHasBatchNumber', 'partsJobDef', 'pdcJobRequired', 'pdcJobComplete',
    'pmbPartsReleaseWarning', 'transferYhVehicleToPmb', 'transferSelectedYhVehiclesToPmb'].map(fn).join('\n'), ctx);
  return { ctx, row, calls, prompts, alerts };
}

test('mapped explicit Parts not required does not warn, while absent projection still does', () => {
  const { ctx } = context();
  for (const extra of [{ parts_update: { parts_required: false } }, { parts_required: false }]) {
    assert.equal(ctx.pmbPartsReleaseWarning([vehicle(extra)]), '');
  }
  assert.match(ctx.pmbPartsReleaseWarning([vehicle()]), /WARNING — CAUTION/);
});
test('current nested receipt overrides stale root completion aliases', () => {
  const row = vehicle({ parts_received: true, parts_completed: true, parts_update: { parts_required: true, parts_received: false } });
  assert.equal(row.pdcCompleteParts, false);
  row.pdcPartsReceived = true;
  row.parts_received = true;
  row.parts_completed = true;
  assert.match(context().ctx.pmbPartsReleaseWarning([row]), /without Parts complete/);
});
test('refresh replaces an old not-required projection when the new snapshot omits it', () => {
  const { ctx } = context();
  const old = vehicle({ parts_update: { parts_required: false } });
  old.partsUpdate = { parts_required: false };
  old.__emailPartsUpdate = { parts_required: false };
  for (const extra of [{}, { parts_update: { parts_required: null } }]) {
    const fresh = { id: old.__emailVehicleId, version: 4, stock_number: old.stock, current_location: 'YH', ...extra };
    const { rows } = service.reconcileVehicleRows([old], [fresh]);
    assert.equal(rows.length, 1);
    assert.match(ctx.pmbPartsReleaseWarning(rows), /WARNING — CAUTION/);
  }
});
test('Parts received suppresses the warning for nested and legacy root receipts', () => {
  const { ctx } = context();
  for (const extra of [{ parts_update: { parts_received: true } }, { parts_received: true }, { parts_completed: true }]) {
    assert.equal(ctx.pmbPartsReleaseWarning([vehicle(extra)]), '');
  }
});
test('import colours, ordering and ETA do not claim Parts have been received', () => {
  const { ctx } = context();
  for (const colour of ['green', 'grey', 'orange', 'red', 'review']) {
    const row = vehicle({ parts_flags: { colour }, parts_update: { parts_required: true, parts_received: false, parts_ordered: true, worst_eta: '2026-09-16' } });
    assert.match(ctx.pmbPartsReleaseWarning([row]), /13021292/);
  }
});
test('cancelling the incomplete-Parts release sends no mutation and keeps incoming location', async () => {
  const { ctx, row, calls, prompts } = context(vehicle(), false);
  await ctx.transferYhVehicleToPmb(row.stock);
  assert.equal(calls.length, 0);
  assert.equal(row.pdcLocation, 'YH');
  assert.match(prompts[0], /^WARNING — CAUTION/);
  assert.match(prompts[0], /released to PMB without Parts complete/);
});
test('acknowledged release retains canonical ID/version and does not mark Parts complete', async () => {
  const { ctx, row, calls, prompts } = context();
  await ctx.transferYhVehicleToPmb(row.stock);
  assert.equal(prompts.length, 1);
  assert.deepEqual(calls, [{ vehicleId: row.__emailVehicleId, expectedVersion: 3 }]);
  assert.equal(row.pdcLocation, 'PMB');
  assert.equal(row.pdcCompleteParts, false);
});
test('complete Parts gets the normal transfer confirmation without a caution', async () => {
  const { ctx, row, prompts } = context(vehicle({ parts_received: true }));
  await ctx.transferYhVehicleToPmb(row.stock);
  assert.doesNotMatch(prompts[0], /CAUTION/);
  assert.match(prompts[0], /Transfer 13021292/);
});
test('unavailable transfer is rejected before confirmation or mutation', async () => {
  const { ctx, row, calls, prompts } = context();
  ctx.sharedVehicleLocationMutationUnavailable = () => true;
  await ctx.transferYhVehicleToPmb(row.stock);
  assert.equal(prompts.length, 0);
  assert.equal(calls.length, 0);
});
test('bulk warning lists only incomplete vehicles and cancellation does not write', async () => {
  const { ctx, prompts } = context(vehicle(), false);
  const rows = [vehicle(), vehicle({ stock_number: '13000001', parts_received: true }), vehicle({ stock_number: '13000002', parts_required: false })];
  ctx.selectedVehiclesForBulkEmail = () => rows;
  ctx.vehicleIdentityTitle = v => v.stock;
  ctx.loadVehicleEdits = () => assert.fail('cancel must not read mutable local state');
  ctx.nowIsoString = () => assert.fail('cancel must not start transfer');
  await ctx.transferSelectedYhVehiclesToPmb();
  const caution = prompts[0].split('Transfer 3')[0];
  assert.match(caution, /13021292/);
  assert.doesNotMatch(caution, /13000001|13000002/);
});
test('manual override checks PMB arrival caution before beginning a save', () => {
  const override = fs.readFileSync('pdc-location-override.js', 'utf8');
  const begin = override.indexOf('const request=begin();let timeout;');
  assert.ok(override.indexOf("destination==='PMB'") < begin);
  assert.ok(override.indexOf('if(partsWarning&&!window.confirm(partsWarning))return;') < begin);
  assert.match(override, /clear\?\(selected\.pdcAutomaticLocation\|\|selected\.pdcLocation\):location/);
});
