'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const service = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync('app.js', 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let depth = 0;
  let open = -1;
  let parens = 0;
  for (let i = source.indexOf('(', start); i < source.length; i += 1) {
    if (source[i] === '(') parens += 1;
    else if (source[i] === ')' && --parens === 0) { open = source.indexOf('{', i); break; }
  }
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const defs = [
  ['bus4x4', 'pdcRequiresBus4x4', 'pdcCompleteBus4x4'],
  ['tint', 'pdcRequiresTint', 'pdcCompleteTint'],
  ['hoist', 'pdcRequiresHoist', 'pdcCompleteHoist'],
  ['fitting', 'pdcRequiresFitting', 'pdcCompleteFitting'],
  ['fabrication', 'pdcRequiresFabrication', 'pdcCompleteFabrication'],
  ['electrical', 'pdcRequiresElectrical', 'pdcCompleteElectrical'],
  ['tyre', 'pdcRequiresTyre', 'pdcCompleteTyre'],
  ['pitInspection', 'pdcRequiresPitInspection', 'pdcCompletePitInspection'],
  ['sublet', 'pdcRequiresSublet', 'pdcCompleteSublet'],
  ['parts', 'pdcRequiresParts', 'pdcCompleteParts'],
].map(([key, requireKey, completeKey]) => ({ key, requireKey, completeKey }));
const context = { app: { pendingSharedWorkStates: new Map() }, PDC_JOB_DEFS: defs, Date, Map };
vm.runInNewContext([extractFunction('pendingSharedWorkStateMap'), extractFunction('sharedWorkStatesMatchVehicle'), extractFunction('applyPendingSharedWorkStateOverlays')].join('\n'), context);

const vehicleId = 'e98e5299-95a5-52b9-9473-4d53a03d53b2';
const local = [{ stock: '12185553', __emailVehicleId: vehicleId, __emailVehicleServerAuthoritative: true }];
const staleRawSnapshot = [{ id: vehicleId, permanent_vehicle_id: '12185553', stock_number: '12185553', version: 25, work_items: [] }];
const mapped = service.reconcileVehicleRows(local, staleRawSnapshot).rows;
assert.strictEqual(mapped[0].pdcRequiresHoist, false, 'stale DTO mapper reproduces the original lost state');
context.app.pendingSharedWorkStates.set(vehicleId, {
  stock: '12185553',
  workStates: Object.fromEntries(defs.map(def => [def.key, ['hoist','fitting'].includes(def.key) ? 'required' : 'none'])),
  vehicleVersion: 25,
  savedAt: Date.now(),
});
const repaired = context.applyPendingSharedWorkStateOverlays(mapped);
assert.strictEqual(repaired[0].pdcRequiresHoist, true);
assert.strictEqual(repaired[0].pdcRequiresFitting, true);
assert.ok(source.includes('function sharedWorkStateCache()'), 'shared work-state cache exists for the current authenticated page');
assert.ok(source.includes('function applySharedWorkStateCache(rows = [])'), 'final board rows apply canonical shared cache');
assert.ok(source.includes('cacheSharedWorkState(vehicle, ref.vehicleId, workStates, body.vehicle_version);'), 'successful work-state RPC populates the canonical cache');
assert.ok(source.includes('localRows = applySharedWorkStateCache(localRows);'), 'selectedVehicle source applies cache after all projection mapping');
console.log('Raw snapshot to DTO mapper stale-state regression passed.');
