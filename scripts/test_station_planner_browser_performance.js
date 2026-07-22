'use strict';
const { chromium } = require(process.env.PDC_PLAYWRIGHT_PATH || 'playwright-core');

const URL = process.env.PDC_PERF_URL || 'http://127.0.0.1:8106/staging.html';
const STAGING_REF = 'cdsmnqxtyyoeoznmbidd';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const TARGET_MS = 2000;
const STATIONS = [
  ['BUS_4X4', 'bus-4x4'], ['TINT', 'tint'], ['HOIST', 'hoist'],
  ['FITTING', 'fitting'], ['FABRICATION', 'fab'], ['ELECTRICAL', 'elec'],
  ['TYRE', 'tyre'], ['PIT_INSPECTION', 'pit']
];
const creds = { email: process.env.PDC_STAGING_ADMIN_EMAIL, password: process.env.PDC_STAGING_ADMIN_PASSWORD };
if (!creds.email || !creds.password) throw new Error('missing PDC_STAGING_ADMIN_EMAIL/PDC_STAGING_ADMIN_PASSWORD');

function stationChannels() {
  return (window.PDC_SUPABASE?.getChannels?.() || [])
    .filter(channel => String(channel.topic || '').includes('workshop-station-revision'))
    .map(channel => ({ topic: String(channel.topic || ''), state: channel.state }));
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.PDC_CHROME_PATH || undefined,
    headless: true,
    args: ['--js-flags=--expose-gc', '--enable-precise-memory-info']
  });
  const context = await browser.newContext({ serviceWorkers: 'block', viewport: { width: 1600, height: 1000 } });
  const page = await context.newPage();
  const scopedRequests = [];
  const globalRequests = [];
  const productionRequests = [];
  const pageErrors = [];
  const consoleErrors = [];
  const failedResponses = [];
  context.on('request', request => {
    const url = request.url();
    if (url.includes(PROD_REF)) productionRequests.push(url);
    if (request.method() === 'POST' && url.includes('/rest/v1/rpc/get_station_workshop_snapshot')) {
      let body = {};
      try { body = request.postDataJSON() || {}; } catch (_) { body = {}; }
      scopedRequests.push({ at: Date.now(), stage: body.p_stage_code || '', url });
    }
    if (request.method() === 'POST' && url.includes('/rest/v1/rpc/get_workshop_snapshot')) globalRequests.push(url);
  });
  context.on('response', response => {
    if (response.status() >= 400) failedResponses.push({ status: response.status(), url: response.url() });
  });
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  page.on('dialog', dialog => dialog.dismiss());

  try {
    await page.addInitScript(() => {
      window.__plannerLongTasks = [];
      window.__plannerLoadingSeen = 0;
      try {
        new PerformanceObserver(list => {
          for (const entry of list.getEntries()) window.__plannerLongTasks.push({ start: entry.startTime, duration: entry.duration });
        }).observe({ type: 'longtask', buffered: true });
      } catch (_) { /* longtask observer is optional in older browsers */ }
      const observeLoading = () => {
        const target = document.documentElement;
        if (!target) return;
        new MutationObserver(() => {
          if (document.querySelector('.workshop-station-loading')) window.__plannerLoadingSeen += 1;
        }).observe(target, { childList: true, subtree: true });
      };
      if (document.documentElement) observeLoading();
      else document.addEventListener('DOMContentLoaded', observeLoading, { once: true });
    });
    await page.goto(`${URL}?stationFirst=${Date.now()}#/workflow`, { waitUntil: 'networkidle', timeout: 60000 });
    await page.locator('#pdc-login-email').fill(creds.email);
    await page.locator('#pdc-login-password').fill(creds.password);
    await page.locator('#pdc-password-login').click();
    await page.waitForFunction(() => {
      const shell = document.getElementById('app-shell');
      return shell && !shell.hasAttribute('inert') && window.PDC_AUTH_CONTEXT?.role;
    }, null, { timeout: 30000 });
    const projectRef = await page.evaluate(() => window.PDC_SUPABASE_CONFIG?.projectRef || '');
    if (projectRef !== STAGING_REF) throw new Error(`wrong project ${projectRef}`);
    await page.waitForFunction(() => document.body.dataset.currentView === 'workflow');
    const controlBoardActions = await page.locator('[data-open-workshop-stage]').count();
    if (controlBoardActions !== STATIONS.length) throw new Error(`expected ${STATIONS.length} Control Board planner actions, got ${controlBoardActions}`);

    const transitionResults = [];
    async function waitReady(stage, requestStart, startedAt, source) {
      const loadingSeenImmediately = await page.locator('.workshop-station-loading').count() > 0;
      await page.waitForFunction(expected => {
        const snapshot = window.__workshopDataService?.getLastSnapshot?.();
        const channels = (window.PDC_SUPABASE?.getChannels?.() || []).filter(channel => String(channel.topic || '').includes('workshop-station-revision'));
        const board = document.querySelector('[data-workshop-station-content] .workshop-station-board');
        return snapshot?.scope?.stage_code === expected
          && window.__workshopRealtimeManager?.isSubscribed?.() === true
          && channels.length === 1
          && channels[0].state === 'joined'
          && String(channels[0].topic || '').endsWith(expected.toLowerCase())
          && board?.dataset?.plannerStage === expected;
      }, stage, { timeout: TARGET_MS });
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const durationMs = Date.now() - startedAt;
      const calls = scopedRequests.slice(requestStart);
      const channels = await page.evaluate(stationChannels);
      const dom = await page.evaluate(expected => ({
        shellStage: document.querySelector(':scope body .workshop-planner-dedicated')?.dataset?.plannerStage || '',
        activeBoards: document.querySelectorAll('[data-workshop-station-content] .workshop-station-board').length,
        activeTab: document.querySelector('[data-workshop-open-stage][aria-current="page"]')?.dataset?.workshopOpenStage || '',
        selectedUsable: Boolean(document.querySelector('[data-workshop-date]') && document.querySelector('.workshop-timeline')),
        stationContentChildren: document.querySelector('[data-workshop-station-content]')?.childElementCount || 0,
        expected
      }), stage);
      transitionResults.push({ source, stage, durationMs, calls, channels, dom, loadingSeenImmediately });
      if (durationMs > TARGET_MS) throw new Error(`${stage} usable in ${durationMs}ms, target ${TARGET_MS}ms`);
      if (calls.length !== 1 || calls[0].stage !== stage) throw new Error(`${stage} snapshot calls ${JSON.stringify(calls)}`);
      if (channels.length !== 1 || !channels[0].topic.endsWith(stage.toLowerCase())) throw new Error(`${stage} channels ${JSON.stringify(channels)}`);
      if (!dom.selectedUsable || dom.activeBoards !== 1 || dom.activeTab !== stage || dom.shellStage !== stage) throw new Error(`${stage} DOM ${JSON.stringify(dom)}`);
    }

    let requestStart = scopedRequests.length;
    let startedAt = Date.now();
    await page.locator(`[data-open-workshop-stage="${STATIONS[0][0]}"]`).evaluate(button => button.click());
    await waitReady(STATIONS[0][0], requestStart, startedAt, 'control-board');
    await page.evaluate(() => { window.__stationShellIdentity = document.querySelector('.workshop-planner-dedicated'); });

    const memorySamples = [];
    const domSamples = [];
    const stationCycleOrder = [...STATIONS.slice(1), STATIONS[0]];
    for (let cycle = 0; cycle < 3; cycle += 1) {
      for (const [stage] of stationCycleOrder) {
        requestStart = scopedRequests.length;
        startedAt = Date.now();
        await page.locator(`[data-workshop-open-stage="${stage}"]`).evaluate(button => button.click());
        await waitReady(stage, requestStart, startedAt, `cycle-${cycle + 1}`);
        const shellPreserved = await page.evaluate(() => window.__stationShellIdentity === document.querySelector('.workshop-planner-dedicated'));
        if (!shellPreserved) throw new Error(`planner shell rebuilt while switching to ${stage}`);
      }
      const sample = await page.evaluate(() => {
        if (typeof window.gc === 'function') window.gc();
        return {
          heap: Number(performance.memory?.usedJSHeapSize || 0),
          nodes: document.querySelectorAll('*').length,
          listenersCleanupInstalled: typeof window.__workshopRecoveryListenerCleanup === 'function',
          stationChannels: (window.PDC_SUPABASE?.getChannels?.() || []).filter(channel => String(channel.topic || '').includes('workshop-station-revision')).length
        };
      });
      memorySamples.push(sample.heap);
      domSamples.push(sample.nodes);
      if (!sample.listenersCleanupInstalled || sample.stationChannels !== 1) throw new Error(`resource sample failed ${JSON.stringify(sample)}`);
    }

    const warmHeap = memorySamples[0];
    const finalHeap = memorySamples.at(-1);
    const allowedHeap = Math.max(warmHeap * 1.25, warmHeap + 20 * 1024 * 1024);
    const memoryStable = !warmHeap || finalHeap <= allowedHeap;
    const domStable = domSamples.at(-1) <= domSamples[0] + 100;
    if (!memoryStable || !domStable) throw new Error(`memory/DOM growth ${JSON.stringify({ memorySamples, allowedHeap, domSamples })}`);

    const beforeBackRequests = scopedRequests.length;
    await page.locator('[data-workshop-back-control]').evaluate(button => button.click());
    await page.waitForFunction(() => document.body.dataset.currentView === 'workflow' && !(window.PDC_SUPABASE?.getChannels?.() || []).some(channel => String(channel.topic || '').includes('workshop-station-revision')), null, { timeout: TARGET_MS });
    await page.waitForTimeout(100);
    if (scopedRequests.length !== beforeBackRequests) throw new Error('Back to Control Board issued a station snapshot');

    const browserMetrics = await page.evaluate(() => ({
      loadingSeen: window.__plannerLoadingSeen,
      longTasks: window.__plannerLongTasks,
      currentView: document.body.dataset.currentView,
      activeStationChannels: (window.PDC_SUPABASE?.getChannels?.() || []).filter(channel => String(channel.topic || '').includes('workshop-station-revision')).length,
      recoveryListenerActive: typeof window.__workshopRecoveryListenerCleanup === 'function'
    }));
    const maxLongTaskMs = Math.max(0, ...browserMetrics.longTasks.map(item => item.duration));
    const report = {
      schema: 'pdc.station-first-performance/v1',
      targetMs: TARGET_MS,
      projectRef,
      controlBoardActions,
      transitions: transitionResults.length,
      maxTransitionMs: Math.max(...transitionResults.map(item => item.durationMs)),
      averageTransitionMs: Math.round(transitionResults.reduce((sum, item) => sum + item.durationMs, 0) / transitionResults.length),
      stationSnapshotRequests: scopedRequests.length,
      globalSnapshotRequests: globalRequests.length,
      allTransitionsOneSelectedRequest: transitionResults.every(item => item.calls.length === 1 && item.calls[0].stage === item.stage),
      peakStationChannels: Math.max(...transitionResults.map(item => item.channels.length)),
      persistentShell: true,
      loadingStateSeen: browserMetrics.loadingSeen > 0,
      memorySamples,
      domSamples,
      memoryStable,
      domStable,
      maxLongTaskMs,
      pageUnresponsive: maxLongTaskMs >= TARGET_MS,
      finalControlBoard: browserMetrics.currentView === 'workflow',
      finalStationChannels: browserMetrics.activeStationChannels,
      finalRecoveryListenerActive: browserMetrics.recoveryListenerActive,
      productionRequests,
      pageErrors,
      consoleErrors,
      failedResponses,
      passed: transitionResults.every(item => item.durationMs <= TARGET_MS)
        && transitionResults.every(item => item.calls.length === 1 && item.calls[0].stage === item.stage)
        && globalRequests.length === 0
        && browserMetrics.loadingSeen > 0
        && memoryStable && domStable && maxLongTaskMs < TARGET_MS
        && browserMetrics.currentView === 'workflow'
        && browserMetrics.activeStationChannels === 0
        && browserMetrics.recoveryListenerActive === false
        && productionRequests.length === 0 && pageErrors.length === 0 && consoleErrors.length === 0 && failedResponses.length === 0
    };
    console.log(JSON.stringify(report, null, 2));
    if (!report.passed) process.exitCode = 1;
  } finally {
    await context.close().catch(() => {});
    await browser.close();
  }
})().catch(error => {
  console.error(`STATION_FIRST_PERFORMANCE_FAIL ${error.stack || error}`);
  process.exit(1);
});
