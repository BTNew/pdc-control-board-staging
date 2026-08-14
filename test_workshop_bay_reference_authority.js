'use strict';

const assert = require('assert');

global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.cleanNavisionText = value => String(value || '').trim();
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.nowIsoString = () => '2026-08-14T00:00:00.000Z';
global.pmbStageLabel = value => String(value || '');
global.pmbStageBayCount = () => 5;

const planner = require('./workshop-planner.js');

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

(async () => {
  const write = deferred();
  let actionsACalls = 0;
  let actionsBCalls = 0;
  let currentOwner = null;
  let authorityGeneration = 1;

  const actionsA = {
    assignBookingTechnician: async () => {
      actionsACalls += 1;
      return { ok: true };
    },
  };
  const actionsB = {
    assignBookingTechnician: async () => {
      actionsBCalls += 1;
      return { ok: true };
    },
  };
  const serviceA = {
    getCachedWorkshopBays: () => ({ rows: [{ id: 'bay-1', code: 'FITTING-BAY-01', version: 3 }] }),
    getCachedTechnicians: () => ({ rows: [{ id: 'tech-a', name: 'Alex', active: true }] }),
    setBayDefaultTechnician: async () => write.promise,
  };
  const serviceB = {
    getCachedWorkshopBays: () => ({ rows: [{ id: 'bay-1', code: 'FITTING-BAY-01', version: 4 }] }),
    getCachedTechnicians: () => ({ rows: [{ id: 'tech-b', name: 'Blake', active: true }] }),
    setBayDefaultTechnician: async () => ({ ok: true }),
  };
  const snapshot = {
    vehicles: [{ id: 'vehicle-1', stock_number: 'STK-1' }],
    bookings: [{
      booking_id: 'booking-1',
      version: 7,
      vehicle_id: 'vehicle-1',
      vehicle: { id: 'vehicle-1', stock_number: 'STK-1' },
      stage: { code: 'FITTING' },
      bay: { id: 'bay-1', bay_number: 1 },
      status: 'planned',
      scheduled_start_at: '2026-08-17T00:00:00.000Z',
      default_duration_minutes: 60,
      assignment: null,
    }],
  };

  global.window = {
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    PDC_AUTH_CONTEXT: { userId: 'principal-a', role: 'administrator' },
    workshopSharedModeEnabled: config => config?.workshop?.sharedData === true,
    __workshopDataService: {
      isEnabled: () => true,
      getTrustedSnapshot: () => snapshot,
    },
    __workshopReferenceDataService: serviceA,
    __workshopSharedActions: actionsA,
    alert: () => {},
    captureWorkshopReferenceMutation: (service, operationKey, options = {}) => {
      currentOwner = {
        service,
        actionService: global.window.__workshopSharedActions,
        operationKey,
        authorityGeneration,
        requireAdministrator: options.requireAdministrator === true,
      };
      return currentOwner;
    },
    workshopReferenceMutationCurrent: owner => Boolean(
      owner
      && owner === currentOwner
      && owner.authorityGeneration === authorityGeneration
      && owner.service === global.window.__workshopReferenceDataService
      && (!owner.requireAdministrator || global.window.PDC_AUTH_CONTEXT.role === 'administrator')
    ),
    finishWorkshopReferenceMutation: owner => {
      if (owner === currentOwner) currentOwner = null;
    },
  };

  const operation = planner.saveWorkshopBayMechanic('FITTING', 1, 'Alex');
  await Promise.resolve();
  global.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
  global.window.__workshopReferenceDataService = serviceB;
  global.window.__workshopSharedActions = actionsB;
  authorityGeneration += 1;
  write.resolve({ ok: true });
  await operation.catch(() => {});

  assert.strictEqual(actionsACalls, 0, 'superseded A-owned operation must not backfill through old actions A');
  assert.strictEqual(actionsBCalls, 0, 'superseded A-owned operation must not backfill through replacement actions B');
  console.log('PASS workshop bay default authority ownership');
})().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
