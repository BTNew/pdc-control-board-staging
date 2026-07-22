'use strict';
const { chromium } = require(process.env.PDC_PLAYWRIGHT_PATH || 'playwright-core');

const URL = process.env.PDC_FIXTURE_PERF_URL || 'http://127.0.0.1:8106/test-75.html';
const TARGET_MS = 2000;
const STATIONS = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'SUBLET'];

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.PDC_CHROME_PATH || undefined,
    headless: true,
    args: ['--js-flags=--expose-gc', '--enable-precise-memory-info']
  });
  const context = await browser.newContext({ serviceWorkers: 'block', viewport: { width: 1600, height: 1000 } });
  const page = await context.newPage();
  const pageErrors = [];
  const consoleErrors = [];
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  page.on('dialog', dialog => dialog.dismiss());
  try {
    await page.addInitScript(() => {
      window.__plannerLongTasks = [];
      try {
        new PerformanceObserver(list => {
          for (const entry of list.getEntries()) window.__plannerLongTasks.push(entry.duration);
        }).observe({ type: 'longtask', buffered: true });
      } catch (_) { /* optional browser metric */ }
    });
    await page.goto(`${URL}?fixturePerf=${Date.now()}#/workflow`, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForFunction(() => document.body.dataset.currentView === 'workflow' && Array.isArray(window.app?.data));
    const initial = await page.evaluate(() => {
      const buttons = document.querySelectorAll('[data-open-workshop-stage]');
      const result = {
        vehicles: app.data.length,
        vehicleState: JSON.stringify(app.data),
        actions: buttons.length,
        startedAt: Date.now()
      };
      buttons[0]?.click();
      return result;
    });
    if (initial.vehicles !== 75) throw new Error(`expected 75-vehicle fixture, got ${initial.vehicles}`);
    if (initial.actions !== STATIONS.length) throw new Error(`expected ${STATIONS.length} station actions, got ${initial.actions}`);

    const durations = [];
    async function switchStation(stage, source, trigger = true, startedAt = Date.now()) {
      if (trigger) await page.locator(`[data-workshop-open-stage="${stage}"]`).evaluate(button => button.click());
      await page.waitForFunction(expected => {
        const shell = document.querySelector('.workshop-planner-dedicated');
        const board = document.querySelector('[data-workshop-station-content] .workshop-station-board');
        return shell?.dataset?.plannerStage === expected
          && board?.dataset?.plannerStage === expected
          && document.querySelector('[data-workshop-open-stage][aria-current="page"]')?.dataset?.workshopOpenStage === expected
          && Boolean(document.querySelector('[data-workshop-date]'));
      }, stage, { timeout: TARGET_MS });
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(resolve)));
      const durationMs = Date.now() - startedAt;
      durations.push({ source, stage, durationMs });
      if (durationMs > TARGET_MS) throw new Error(`${stage} fixture transition ${durationMs}ms exceeds ${TARGET_MS}ms`);
      const activeBoards = await page.locator('[data-workshop-station-content] .workshop-station-board').count();
      if (activeBoards !== 1) throw new Error(`${stage} rendered ${activeBoards} active station boards`);
    }

    await switchStation(STATIONS[0], 'control-board', false, initial.startedAt);
    await page.evaluate(() => { window.__fixtureStationShell = document.querySelector('.workshop-planner-dedicated'); });
    const cycleOrder = [...STATIONS.slice(1), STATIONS[0]];
    const memorySamples = [];
    const domSamples = [];
    for (let cycle = 0; cycle < 3; cycle += 1) {
      for (const stage of cycleOrder) {
        await switchStation(stage, `cycle-${cycle + 1}`);
        const shellPreserved = await page.evaluate(() => window.__fixtureStationShell === document.querySelector('.workshop-planner-dedicated'));
        if (!shellPreserved) throw new Error(`station shell rebuilt for ${stage}`);
      }
      const sample = await page.evaluate(() => {
        if (typeof window.gc === 'function') window.gc();
        return { heap: Number(performance.memory?.usedJSHeapSize || 0), nodes: document.querySelectorAll('*').length };
      });
      memorySamples.push(sample.heap);
      domSamples.push(sample.nodes);
    }

    const warmHeap = memorySamples[0];
    const allowedHeap = Math.max(warmHeap * 1.25, warmHeap + 20 * 1024 * 1024);
    const memoryStable = !warmHeap || memorySamples.at(-1) <= allowedHeap;
    const domStable = domSamples.at(-1) <= domSamples[0] + 100;
    const final = await page.evaluate(() => ({
      vehicleState: JSON.stringify(app.data),
      longTasks: window.__plannerLongTasks,
      channels: (window.PDC_SUPABASE?.getChannels?.() || []).filter(channel => String(channel.topic || '').includes('workshop-station-revision')).length
    }));
    const maxLongTaskMs = Math.max(0, ...final.longTasks);
    const report = {
      schema: 'pdc.station-first-75-fixture-performance/v1',
      targetMs: TARGET_MS,
      vehicles: initial.vehicles,
      controlBoardActions: initial.actions,
      transitions: durations.length,
      maxTransitionMs: Math.max(...durations.map(item => item.durationMs)),
      averageTransitionMs: Math.round(durations.reduce((sum, item) => sum + item.durationMs, 0) / durations.length),
      persistentShell: true,
      memorySamples,
      domSamples,
      memoryStable,
      domStable,
      maxLongTaskMs,
      pageUnresponsive: maxLongTaskMs >= TARGET_MS,
      vehicleStateUnchanged: final.vehicleState === initial.vehicleState,
      stationChannels: final.channels,
      pageErrors,
      consoleErrors,
      passed: durations.every(item => item.durationMs <= TARGET_MS)
        && memoryStable && domStable && maxLongTaskMs < TARGET_MS
        && final.vehicleState === initial.vehicleState
        && final.channels === 0 && pageErrors.length === 0 && consoleErrors.length === 0
    };
    console.log(JSON.stringify(report, null, 2));
    if (!report.passed) process.exitCode = 1;
  } finally {
    await context.close().catch(() => {});
    await browser.close();
  }
})().catch(error => {
  console.error(`STATION_FIRST_FIXTURE_PERFORMANCE_FAIL ${error.stack || error}`);
  process.exit(1);
});
