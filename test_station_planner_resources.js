'use strict';

const assert = require('assert');
const { createWorkshopDataService } = require('./workshop-data-service.js');
const { createWorkshopRealtimeManager } = require('./workshop-realtime.js');

async function measure(scope) {
  const rpcCalls = [];
  let activeChannels = 0;
  let peakChannels = 0;
  const client = {
    async rpc(_token, name, params) {
      rpcCalls.push({ name, params });
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
  service.destroy();
  return { requests: rpcCalls.length, rpc: rpcCalls[0]?.name, peakChannels, channelsAfterTeardown: activeChannels };
}

(async () => {
  const before = await measure(null);
  const after = await measure({ stageCode: 'TINT', dateFrom: '2026-07-21', dateTo: '2026-07-21' });
  assert.deepStrictEqual(before, { requests: 1, rpc: 'get_workshop_snapshot', peakChannels: 1, channelsAfterTeardown: 0 });
  assert.deepStrictEqual(after, { requests: 1, rpc: 'get_station_workshop_snapshot', peakChannels: 1, channelsAfterTeardown: 0 });
  console.log(`station_planner_resources: PASS ${JSON.stringify({ before, after })}`);
})().catch(error => { console.error(error); process.exit(1); });
