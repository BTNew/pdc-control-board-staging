'use strict';

const assert = require('assert');
const { createWorkshopDataService } = require('./workshop-data-service.js');
const { createWorkshopRealtimeManager } = require('./workshop-realtime.js');

const STAGES = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE'];

async function measure(scope) {
  const rpcCalls = [];
  let activeChannels = 0;
  let peakChannels = 0;
  const client = {
    async rpc(_token, name, params) {
      rpcCalls.push({ name, params });
      if (params?.p_stage_code === 'SUBLET') return { ok: false, status: 400, body: { error: 'stage_not_planner_enabled' } };
      return { ok: true, status: 200, body: {
        revision: 1, stages: [], bays: [], technicians: [], bookings: [], vehicles: [], work_items: []
      } };
    }
  };
  const service = createWorkshopDataService({
    config: { workshop: { sharedData: true } }, client, scope,
    getAccessToken: () => 'synthetic-test-token', getRole: () => 'operator'
  });
  await service.loadSnapshot('resource_measurement');
  const realtime = createWorkshopRealtimeManager({
    dataService: { onRevisionSignal() {}, onReconnect() {} },
    subscribe() {
      activeChannels += 1;
      peakChannels = Math.max(peakChannels, activeChannels);
      return () => { activeChannels -= 1; };
    }
  });
  realtime.start();
  realtime.stop();
  const snapshotLoaded = Boolean(service.getLastSnapshot());
  service.destroy();
  return { requests: rpcCalls.length, rpc: rpcCalls[0]?.name, peakChannels, channelsAfterTeardown: activeChannels, snapshotLoaded };
}

async function cycleAllStationsThreeTimes() {
  const rpcCalls = [];
  let activeChannels = 0;
  let peakChannels = 0;
  let retainedSubscriptions = 0;
  for (let cycle = 0; cycle < 3; cycle += 1) {
    for (const stageCode of STAGES) {
      const client = {
        async rpc(_token, name, params) {
          rpcCalls.push({ name, params });
          return { ok: true, status: 200, body: {
            revision: rpcCalls.length,
            scope: { stage_code: stageCode },
            stages: [{ code: stageCode }], bays: [], technicians: [], bookings: [], vehicles: [], work_items: []
          } };
        }
      };
      const service = createWorkshopDataService({
        config: { workshop: { sharedData: true } }, client,
        scope: { stageCode, dateFrom: '2026-07-21', dateTo: '2026-07-21' },
        getAccessToken: () => 'synthetic-test-token', getRole: () => 'operator'
      });
      const realtime = createWorkshopRealtimeManager({
        dataService: service,
        subscribe() {
          activeChannels += 1;
          retainedSubscriptions += 1;
          peakChannels = Math.max(peakChannels, activeChannels);
          return () => {
            activeChannels -= 1;
            retainedSubscriptions -= 1;
          };
        }
      });
      realtime.start();
      await new Promise(resolve => setImmediate(resolve));
      realtime.stop();
      service.destroy();
      assert.strictEqual(activeChannels, 0, `inactive ${stageCode} channel must be disposed`);
      assert.strictEqual(retainedSubscriptions, 0, `inactive ${stageCode} callbacks must not remain retained`);
    }
  }
  assert.strictEqual(rpcCalls.length, STAGES.length * 3, 'each selected station entry must issue one snapshot request only');
  assert.strictEqual(rpcCalls.every(call => call.name === 'get_station_workshop_snapshot'), true, 'cycling must never request the combined planner snapshot');
  assert.strictEqual(peakChannels, 1, 'cycling must never overlap active station channels');
  assert.deepStrictEqual(rpcCalls.map(call => call.params.p_stage_code), [...STAGES, ...STAGES, ...STAGES]);
  return { cycles: 3, stations: STAGES.length, requests: rpcCalls.length, peakChannels, activeChannels, retainedSubscriptions };
}

(async () => {
  const before = await measure(null);
  const after = await measure({ stageCode: 'TINT', dateFrom: '2026-07-21', dateTo: '2026-07-21' });
  const sublet = await measure({ stageCode: 'SUBLET', dateFrom: '2026-07-21', dateTo: '2026-07-21' });
  assert.deepStrictEqual(before, { requests: 1, rpc: 'get_workshop_snapshot', peakChannels: 1, channelsAfterTeardown: 0, snapshotLoaded: true });
  assert.deepStrictEqual(after, { requests: 1, rpc: 'get_station_workshop_snapshot', peakChannels: 1, channelsAfterTeardown: 0, snapshotLoaded: true });
  assert.deepStrictEqual(sublet, { requests: 1, rpc: 'get_station_workshop_snapshot', peakChannels: 1, channelsAfterTeardown: 0, snapshotLoaded: false });
  const repeated = await cycleAllStationsThreeTimes();
  console.log(`station_planner_resources: PASS ${JSON.stringify({ before, after, repeated })}`);
})().catch(error => { console.error(error); process.exit(1); });
