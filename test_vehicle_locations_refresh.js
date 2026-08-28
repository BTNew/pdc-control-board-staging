'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  createVehicleLocationsRefreshCoordinator,
} = require('./vehicle-locations-refresh.js');

const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const stylesSource = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

async function testCompleteRefreshFansInAuthoritativeServices() {
  const calls = [];
  const finishes = [];
  const coordinator = createVehicleLocationsRefreshCoordinator({
    loaders: {
      sharedNavision: ({ generation }) => { calls.push(['sharedNavision', generation]); return { ok: true, revision: 12, count: 4 }; },
      operationalVehicleSnapshot: ({ generation }) => { calls.push(['operationalVehicleSnapshot', generation]); return { ok: true, revision: 8, count: 4 }; },
      workOperationStates: ({ generation }) => { calls.push(['workOperationStates', generation]); return { ok: true }; },
      receiptOverlays: ({ generation }) => { calls.push(['receiptOverlays', generation]); return { ok: true }; },
    },
    onFinish: result => finishes.push(result),
  });

  const result = await coordinator.refresh();
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.generation, 1);
  assert.deepStrictEqual(calls.map(call => call[0]), [
    'sharedNavision',
    'operationalVehicleSnapshot',
    'workOperationStates',
    'receiptOverlays',
  ]);
  assert(calls.every(call => call[1] === 1), 'all fan-in calls share one refresh generation');
  assert.strictEqual(finishes.length, 1);
  assert.strictEqual(finishes[0].ok, true);
}

async function testDoubleClickCollapsesToOneGeneration() {
  const pending = deferred();
  let calls = 0;
  const coordinator = createVehicleLocationsRefreshCoordinator({
    loaders: {
      sharedNavision: () => { calls += 1; return pending.promise; },
    },
  });

  const first = coordinator.refresh();
  const second = coordinator.refresh();
  assert.strictEqual(first, second, 'repeated button clicks reuse the in-flight refresh');
  assert.strictEqual(calls, 1);
  pending.resolve({ ok: true });
  await first;
}

async function testStaleOutOfOrderRefreshCannotFinishAsNewer() {
  const firstPending = deferred();
  const secondPending = deferred();
  const finishes = [];
  let invocation = 0;
  const coordinator = createVehicleLocationsRefreshCoordinator({
    loaders: {
      sharedNavision: ({ generation }) => {
        invocation += 1;
        return invocation === 1 ? firstPending.promise : secondPending.promise;
      },
    },
    onFinish: result => finishes.push(result),
  });

  const first = coordinator.refresh();
  const second = coordinator.refresh({ supersede: true });
  secondPending.resolve({ ok: true, revision: 22 });
  const secondResult = await second;
  firstPending.resolve({ ok: true, revision: 21 });
  const firstResult = await first;

  assert.strictEqual(secondResult.ok, true);
  assert.strictEqual(secondResult.generation, 2);
  assert.strictEqual(firstResult.stale, true);
  assert.deepStrictEqual(finishes.map(result => result.generation), [2]);
  assert.strictEqual(coordinator.isCurrent(1), false);
  assert.strictEqual(coordinator.isCurrent(2), true);
}

async function testErrorRecoveryKeepsRetryAvailable() {
  const finishes = [];
  let attempt = 0;
  const coordinator = createVehicleLocationsRefreshCoordinator({
    loaders: {
      sharedNavision: () => {
        attempt += 1;
        return attempt === 1 ? Promise.reject(new Error('temporary outage')) : { ok: true, revision: 23 };
      },
    },
    onFinish: result => finishes.push(result),
  });

  const failed = await coordinator.refresh();
  const recovered = await coordinator.refresh();
  assert.strictEqual(failed.ok, false);
  assert.strictEqual(failed.partial, false);
  assert.strictEqual(recovered.ok, true);
  assert.strictEqual(finishes.length, 2);
  assert.strictEqual(coordinator.isRefreshing(), false);
}

function testVehicleLocationsIntegrationContracts() {
  assert(appSource.includes('createVehicleLocationsRefreshCoordinator'), 'app uses the coordinated refresh service');
  assert(appSource.includes("loadSharedNavisionVisibleRows({ force: true, refreshGeneration: generation })"), 'refresh uses the existing Navision refresh API');
  assert(appSource.includes("refreshEmailVehicleLocations({ refreshGeneration: generation })"), 'refresh uses the existing operational snapshot API');
  assert(appSource.includes("loadSnapshot('vehicle_locations_refresh')"), 'refresh uses the existing workshop snapshot API');
  assert(appSource.includes("loadWorkshopEligibilitySnapshot('vehicle_locations_refresh')"), 'refresh uses the existing eligibility snapshot API');
  assert(appSource.includes('refreshWorkshopReferenceData()'), 'refresh includes shared workshop reference data');
  assert(appSource.includes('captureIncomingBoardDisclosureState'), 'refresh captures expanded Vehicle Locations sections');
  assert(appSource.includes('restoreIncomingBoardDisclosureState'), 'refresh restores expanded Vehicle Locations sections');
  assert(appSource.includes('data-vehicle-locations-refresh'), 'status box owns the refresh control');
  assert(appSource.includes('Refreshing…'), 'refresh state uses the requested busy label');
  assert(appSource.includes('Previous authoritative Vehicle Locations data is stale'), 'failed refresh visibly preserves stale data');
  assert(appSource.includes('aria-live="polite"'), 'refresh status is announced accessibly');
  assert(!/\b(?:window\.)?location\.reload\s*\(/.test(appSource), 'refresh never performs a full website reload');
  assert(!indexSource.includes('vjdtsswhroyguxyfjdkt.supabase.co'), 'staging entry has no production Supabase host');
  assert(indexSource.includes('cdsmnqxtyyoeoznmbidd.supabase.co'), 'staging entry remains bound to the staging Supabase host');
  assert(indexSource.includes('vehicle-locations-refresh=2026.08.29.738'), 'changed assets carry the refresh cache marker');
  assert(stylesSource.includes('.vehicle-locations-refresh'), 'refresh control has dedicated responsive styling');
  assert(stylesSource.includes('@media (max-width: 720px)'), 'mobile breakpoint remains covered');
}

(async () => {
  await testCompleteRefreshFansInAuthoritativeServices();
  await testDoubleClickCollapsesToOneGeneration();
  await testStaleOutOfOrderRefreshCannotFinishAsNewer();
  await testErrorRecoveryKeepsRetryAvailable();
  testVehicleLocationsIntegrationContracts();
  console.log('Vehicle Locations refresh regression passed.');
})().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
