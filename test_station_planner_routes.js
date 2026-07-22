'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { createWorkshopDataService, normalizeWorkshopSnapshotScope } = require('./workshop-data-service.js');
const { workshopVehicle, workshopSnapshotVehicleToPlannerRow, workshopPlannerVehiclesForStage } = require('./workshop-planner.js');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const ROUTES = [
  ['planner-bus-4x4', 'workshop/bus-4x4', 'BUS_4X4'],
  ['planner-tint', 'workshop/tint', 'TINT'],
  ['planner-hoist', 'workshop/hoist', 'HOIST'],
  ['planner-fitting', 'workshop/fitting', 'FITTING'],
  ['planner-fab', 'workshop/fab', 'FABRICATION'],
  ['planner-elec', 'workshop/elec', 'ELECTRICAL'],
  ['planner-tyre', 'workshop/tyre', 'TYRE'],
  ['planner-pit', 'workshop/pit', 'PIT_INSPECTION'],
  ['planner-sublet', 'workshop/sublet', 'SUBLET'],
];

async function testScopedDataService() {
  assert.deepStrictEqual(normalizeWorkshopSnapshotScope({ stageCode: 'tint', dateFrom: '2026-07-21' }), {
    stageCode: 'TINT', dateFrom: '2026-07-21', dateTo: '2026-07-21'
  });
  assert.strictEqual(normalizeWorkshopSnapshotScope({ stageCode: 'TINT', dateFrom: 'bad' }), null);

  const calls = [];
  const client = {
    async rpc(_token, name, params) {
      calls.push({ name, params });
      return { ok: true, status: 200, body: {
        revision: calls.length,
        scope: { stage_code: params.p_stage_code },
        stages: [{ code: params.p_stage_code }],
        bays: [], bookings: [], vehicles: [], work_items: []
      } };
    }
  };
  const service = createWorkshopDataService({
    config: { workshop: { sharedData: true } },
    client,
    scope: { stageCode: 'TINT', dateFrom: '2026-07-21', dateTo: '2026-07-21' },
    getAccessToken: () => 'synthetic-test-token',
    getRole: () => 'operator'
  });
  await service.loadSnapshot('initial');
  assert.deepStrictEqual(calls[0], {
    name: 'get_station_workshop_snapshot',
    params: { p_stage_code: 'TINT', p_date_from: '2026-07-21', p_date_to: '2026-07-21' }
  });
  assert.strictEqual(calls.some(call => call.name === 'get_workshop_snapshot'), false, 'dedicated route must not load combined snapshot');
  assert.strictEqual(calls.filter(call => call.name === 'get_station_workshop_snapshot').length, 1, 'initial route entry must issue exactly one scoped snapshot RPC');
  await service.setScope({ stageCode: 'TINT', dateFrom: '2026-07-22', dateTo: '2026-07-22' });
  assert.strictEqual(calls.at(-1).params.p_date_from, '2026-07-22');
  assert.deepStrictEqual(service.getScope(), { stageCode: 'TINT', dateFrom: '2026-07-22', dateTo: '2026-07-22' });
  service.destroy();
}

async function testScopeChangeDiscardsInFlightSnapshot() {
  let releaseFirst;
  let callCount = 0;
  const snapshots = [];
  const client = {
    async rpc(_token, _name, params) {
      callCount += 1;
      if (callCount === 1) {
        await new Promise(resolve => { releaseFirst = resolve; });
      }
      return { ok: true, status: 200, body: {
        revision: callCount,
        scope: { stage_code: params.p_stage_code },
        stages: [{ code: params.p_stage_code }], bays: [], bookings: [], vehicles: [], work_items: []
      } };
    }
  };
  const service = createWorkshopDataService({
    config: { workshop: { sharedData: true } }, client,
    scope: { stageCode: 'TINT', dateFrom: '2026-07-21', dateTo: '2026-07-21' },
    getAccessToken: () => 'synthetic-test-token', getRole: () => 'operator',
    onSnapshot: snapshot => snapshots.push(snapshot.scope.stage_code)
  });
  const first = service.loadSnapshot('initial');
  await Promise.resolve();
  await service.setScope({ stageCode: 'HOIST', dateFrom: '2026-07-21', dateTo: '2026-07-21' });
  releaseFirst();
  await first;
  assert.deepStrictEqual(snapshots, ['HOIST'], 'stale station response must never render after a route/scope change');
  assert.strictEqual(service.getLastSnapshot().scope.stage_code, 'HOIST');
  service.destroy();
}

function testRoutesAndIsolationContracts() {
  const app = read('app.js');
  const planner = read('workshop-planner.js');
  const migration = read('supabase/migrations/039_station_scoped_workshop_snapshot.sql');
  const index = read('index.html');
  const staging = read('staging.html');
  const stagingConfig = read('pdc-supabase-config.staging.js');

  for (const [view, route, stage] of ROUTES) {
    assert(app.includes(`view: '${view}', path: '${route}', stage: '${stage}'`), `missing ${stage} route`);
  }
  assert(app.includes("const WORKSHOP_CONTROL_BOARD_STATIONS = Object.freeze([...PMB_BAY_STATION_SEQUENCE, 'SUBLET'])"));
  assert(app.includes('WORKSHOP_PLANNER_ROUTE_BY_STAGE[normalizedStage]'));
  assert(app.includes("window.addEventListener('popstate', restoreRoute)"));
  assert(app.includes("window.addEventListener('hashchange', restoreRoute)"));
  assert(app.includes("historyMode: 'none'"));
  assert(app.includes('teardownWorkshopPlannerScope();'));
  assert(app.includes('window.__workshopRealtimeManager?.stop?.()'));
  assert(app.includes("scope: app.activeWorkshopPlannerStage ?"));
  assert(index.includes('id="nav-workshop-rollback"'));
  assert(staging.includes('id="nav-workshop-rollback"'));
  for (const shell of ['no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html']) {
    assert(read(shell).includes('id="nav-workshop-rollback"'), `${shell} must honor the explicit rollback flag`);
  }
  assert(app.includes('combinedPlannerRollback'));
  assert(app.includes('return configured === true'), 'combined planner rollback must fail closed unless explicitly enabled');
  assert(stagingConfig.includes('stationRoutes: { combinedPlannerRollback: true }'), 'staging must retain the combined planner behind an explicit rollback flag');
  assert(app.includes("table = stageCode ? 'workshop_station_revision' : 'workshop_revision'"), 'dedicated routes must use station-scoped realtime');
  assert(app.includes('stage_code=eq.${stageCode}'), 'station realtime subscription must filter the active stage');
  assert(app.includes('window.__workshopRealtimeManager?.forceReconnect?.()'), 'recovery listener must become inert after teardown');
  assert(app.includes("if (app.currentView === 'workshop' && typeof initWorkshopSharedServicesIfEnabled"), 'auth refresh must not create a background planner service');
  assert(/catch \(_error\) \{\s*return 'dashboard';/.test(app), 'malformed hashes must fail safely');

  assert(planner.includes('data-workshop-back-control'));
  assert(planner.includes("showView('workflow')"));
  assert(planner.includes("const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '')"));
  assert(/dedicatedStage\s*\?\s*new Map\(\[\[stage, stageVehicleList\.length\]\]\)/.test(planner), 'dedicated render must not count other stations');
  assert(planner.includes('workshopPlannerVehiclesForStage(stage)'));
  assert(planner.includes('let plans = dedicatedStage ? workshopLoadPlans() : workshopCascadeAndSave(workshopSyncCompletedPlans())'), 'opening a dedicated route must not cascade or persist bookings');
  assert(planner.includes('service.setScope({ stageCode: stage, dateFrom: dateKey, dateTo: dateKey })'));

  assert(migration.includes('where b.stage_id = v_stage_id'));
  assert(migration.includes('where stage_id = v_stage_id and is_active = true'));
  assert(migration.includes("upper(replace(wi.work_key, '_', '')) = v_work_key"));
  assert(migration.includes("or (b.status = 'completed' and b.actual_end_at >= v_from and b.actual_end_at < v_to)"));
  assert(migration.includes("b.status not in ('completed', 'stoppage') and b.scheduled_start_at"), 'completed rows must only use actual completion date');
  assert(migration.includes("v.lifecycle_state = 'active'"));
  assert(migration.includes('v.deleted_at is null'));
  assert(migration.includes("'eta_to_kewdale', v.eta_to_kewdale"));
  assert(/create table(?: if not exists)? public\.workshop_station_revision/.test(migration));
  assert(migration.includes("'revision', public.workshop_current_station_revision(v_stage_code)"));
  assert(migration.slice(migration.indexOf("'parts_overrides'")).includes("b.status not in ('completed', 'stoppage')"), 'parts overrides must use scoped booking date/status');
  assert(migration.includes("perform public.require_pdc_role('operator')"));
  assert(!migration.includes('create or replace function public.get_workshop_snapshot'), 'combined snapshot must remain unchanged');

  const opener = app.slice(app.indexOf('function openWorkshopPlannerForStage'), app.indexOf('function renderWorkflowBoard'));
  assert(!/saveVehicle|saveJson|mutate\(|rpc\(|recordVehicleAudit/.test(opener), 'opening a station route must be non-mutating');
}

function testScopedSnapshotCandidateMapping() {
  const row = workshopSnapshotVehicleToPlannerRow({
    id: '11111111-1111-1111-1111-111111111111',
    permanent_vehicle_id: 'MOCK-PERM-1',
    stock_number: 'MOCK-STOCK-1',
    customer_name: 'Mock Customer',
    current_location: 'PMB',
    pmb_stage: 'TINT',
    eta_to_kewdale: '2026-07-20',
    version: 7
  }, [{
    vehicle_id: '11111111-1111-1111-1111-111111111111',
    work_key: 'tint', required: true, completed: false
  }], 'TINT');
  assert.strictEqual(row.sharedVehicleId, '11111111-1111-1111-1111-111111111111');
  assert.strictEqual(row.stockNumber, 'MOCK-STOCK-1');
  assert.strictEqual(row.pdcLocation, 'PMB');
  assert.strictEqual(row.navisionKewdaleEta, '20/07/2026');
  assert.deepStrictEqual(row.pmbJobs.tint, { required: true, completed: false, completedAt: null, notes: '' });
}

function testServerOnlyVehicleActionLookup() {
  const previousWindow = global.window;
  const previousSelectedVehicle = global.selectedVehicle;
  global.selectedVehicle = () => null;
  global.window = {
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    workshopSharedModeEnabled: config => config?.workshop?.sharedData === true,
    __activeWorkshopPlannerStage: 'TINT',
    __workshopDataService: {
      isEnabled: () => true,
      getLastSnapshot: () => ({
        work_items: [],
        vehicles: [{ id: 'server-id', stock_number: 'SERVER-1', pmb_stage: 'TINT', eta_to_kewdale: '2026-07-20', version: 9 }]
      })
    }
  };
  try {
    const row = workshopVehicle('SERVER-1');
    assert(row, 'authoritative scoped vehicle must remain actionable when absent from browser-local data');
    assert.strictEqual(row.sharedVehicleId, 'server-id');
    assert.strictEqual(row.version, 9);
  } finally {
    global.window = previousWindow;
    global.selectedVehicle = previousSelectedVehicle;
  }
}

function testDedicatedRendererRejectsUnrelatedSnapshotVehicles() {
  const previousWindow = global.window;
  const previousApp = global.app;
  const previousNormalizeStage = global.normalizePmbStage;
  const previousStageJobDef = global.pmbStageJobDef;
  const previousNeedingWork = global.pmbVehiclesNeedingStationWork;
  global.app = { data: [] };
  global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
  global.pmbStageJobDef = () => null;
  global.pmbVehiclesNeedingStationWork = () => [];
  global.window = {
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    workshopSharedModeEnabled: config => config?.workshop?.sharedData === true,
    __activeWorkshopPlannerStage: 'TINT',
    __workshopDataService: {
      isEnabled: () => true,
      getLastSnapshot: () => ({
        revision: 1, bookings: [], work_items: [],
        vehicles: [
          { id: 'tint-id', stock_number: 'TINT-1', pmb_stage: 'TINT' },
          { id: 'hoist-id', stock_number: 'HOIST-1', pmb_stage: 'HOIST' }
        ]
      })
    }
  };
  try {
    const rows = workshopPlannerVehiclesForStage('TINT');
    assert.deepStrictEqual(rows.map(row => row.id), ['tint-id'], 'unrelated station vehicles must not render even if a malformed response includes them');
  } finally {
    global.window = previousWindow;
    global.app = previousApp;
    global.normalizePmbStage = previousNormalizeStage;
    global.pmbStageJobDef = previousStageJobDef;
    global.pmbVehiclesNeedingStationWork = previousNeedingWork;
  }
}

(async () => {
  await testScopedDataService();
  await testScopeChangeDiscardsInFlightSnapshot();
  testRoutesAndIsolationContracts();
  testScopedSnapshotCandidateMapping();
  testServerOnlyVehicleActionLookup();
  testDedicatedRendererRejectsUnrelatedSnapshotVehicles();
  console.log('station_planner_routes: PASS');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
