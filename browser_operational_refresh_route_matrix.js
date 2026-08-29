'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');

function loadChromium() {
  for (const candidate of [process.env.PDC_PLAYWRIGHT_PATH, 'C:/Users/nwmgr/pdc-overnight-qa/visual/node_modules/playwright-core'].filter(Boolean)) {
    try { return require(candidate).chromium; } catch (_) {}
  }
  throw new Error('Playwright Chromium package unavailable');
}

function chromePath() {
  const candidates = [process.env.PDC_QC_BROWSER_PATH, process.env.CHROME_PATH, process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe')].filter(Boolean);
  return candidates.find(fs.existsSync) || '';
}

function createServer(root) {
  const absoluteRoot = path.resolve(root);
  return http.createServer((req, res) => {
    const relative = decodeURIComponent(String(req.url || '/').split(/[?#]/, 1)[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(absoluteRoot, relative);
    if (!file.startsWith(`${absoluteRoot}${path.sep}`) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      res.writeHead(404); res.end('not found'); return;
    }
    const type = relative.endsWith('.css') ? 'text/css' : relative.endsWith('.js') ? 'application/javascript' : 'text/html';
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(fs.readFileSync(file));
  });
}

(async () => {
  const root = __dirname;
  const server = createServer(root);
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const chromium = loadChromium();
  const browser = await chromium.launch({ headless: true, ...(chromePath() ? { executablePath: chromePath() } : {}) });
  const routes = ['dashboard', 'qc', 'workflow', 'workshop', 'visibility', 'tv', 'schedule', 'department', 'parts', 'sublet', 'rft', 'completed', 'collected', 'deleted', 'backend', 'emailreview', 'ai-auditor'];
  const stationRoutes = ['planner-bus-4x4', 'planner-tint', 'planner-hoist', 'planner-fitting', 'planner-fab', 'planner-elec', 'planner-tyre'];
  const pageErrors = [];
  const external = [];
  let navigationCount = 0;
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'block' });
    const page = await context.newPage();
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('framenavigated', () => { navigationCount += 1; });
    await page.route('**/*', async route => {
      const target = new URL(route.request().url());
      if (target.origin !== origin) { external.push(route.request().url()); await route.abort('blockedbyclient'); }
      else await route.continue();
    });
    await page.goto(`${origin}/index.html`, { waitUntil: 'networkidle' });
    await page.evaluate(({ routes, stationRoutes }) => {
      window.PDC_AUTH_CONTEXT = { role: 'administrator', userId: '00000000-0000-4000-8000-000000000001', email: 'refresh-test@example.invalid' };
      window.__pdcCachedAccessToken = 'synthetic-refresh-token';
      document.body.classList.remove('auth-pending');
      document.body.dataset.authState = 'signed-in';
      document.querySelector('.pdc-auth-gate')?.setAttribute('hidden', 'hidden');
      document.querySelector('.pdc-auth-gate')?.style.setProperty('display', 'none', 'important');
      document.querySelector('.pdc-auth-gate')?.style.setProperty('pointer-events', 'none', 'important');
      document.querySelector('.app-shell')?.style.setProperty('display', 'block', 'important');
      app.emailVehicleLocationService = { snapshot: async () => ({ ok: true, data: { vehicles: [], revision: 1 } }) };
      window.__workshopDataService = { loadSnapshot: async () => ({}), getState: () => 'connected_read_only', getTrustedSnapshot: () => ({}), getLastRevision: () => 1, start: () => {} };
      window.__workshopReferenceDataService = { getCachedSubletProviders: () => ({ rows: [], state: 'connected_read_only' }), getCachedSalespeople: () => ({ rows: [], state: 'connected_read_only' }), getCachedTechnicians: () => ({ rows: [], state: 'connected_read_only' }), getCachedWorkshopBays: () => ({ rows: [], state: 'connected_read_only' }), listTechnicians: async () => ({ ok: true }), listSalespeople: async () => ({ ok: true }), listSubletProviders: async () => ({ ok: true }), listWorkshopBays: async () => ({ ok: true }), getWorkshopConfiguration: async () => ({ ok: true }), subscribeTechnicians: () => {}, subscribeSalespeople: () => {}, subscribeSubletProviders: () => {}, subscribeWorkshopBays: () => {}, subscribeWorkshopSettings: () => {} };
      for (const route of routes) {
        if (route === 'deleted' || route === 'backend' || route === 'completed' || route === 'collected') document.querySelector('#nav-admin-group')?.removeAttribute('hidden');
        showView(route, { historyMode: 'none' });
        ensureOperationalRefreshControls();
        const view = document.getElementById(route);
        if (!view?.querySelector(`[data-pdc-operational-refresh][data-pdc-refresh-route="${route}"]`)) throw new Error(`missing refresh control for ${route}`);
      }
      for (const route of stationRoutes) {
        showView(route, { historyMode: 'none' });
        ensureOperationalRefreshControls();
        if (!document.querySelector('#workshop [data-pdc-operational-refresh][data-pdc-refresh-route="workshop"]')) throw new Error(`missing planner refresh control for ${route}`);
      }
      showView('parts', { historyMode: 'none' });
      ensureOperationalRefreshControls();
      window.__refreshPending = new Promise(resolve => { window.__resolveRefresh = resolve; });
      app.vehicleLocationsRefreshCoordinator = { refresh: () => window.__refreshPending };
    }, { routes, stationRoutes });
    const partsRefreshCount = await page.locator('button[data-pdc-operational-refresh][data-pdc-refresh-route="parts"]').count();
    if (partsRefreshCount !== 1) console.log('parts refresh controls', await page.locator('[data-pdc-refresh-route="parts"]').evaluateAll(nodes => nodes.map(node => ({ html: node.outerHTML, parent: node.parentElement?.outerHTML.slice(0, 300) }))));
    assert.strictEqual(partsRefreshCount, 1);
    const beforeNavigation = navigationCount;
    const button = page.locator('#parts button[data-pdc-operational-refresh]');
    await button.dispatchEvent('click');
    assert.strictEqual(await button.textContent(), 'Refreshing…');
    assert.strictEqual(await button.isDisabled(), true);
    assert.strictEqual(await button.getAttribute('aria-busy'), 'true');
    await page.evaluate(() => window.__resolveRefresh({ ok: true, route: 'parts', revision: 2 }));
    await button.waitFor({ state: 'attached' });
    await assert.doesNotReject(async () => { await page.waitForTimeout(25); });
    assert.ok((await page.locator('#parts button[data-pdc-operational-refresh]').textContent()).includes('Refresh'));
    assert.strictEqual(navigationCount, beforeNavigation);
    assert.ok(external.every(url => !url.includes('vjdtsswhroyguxyfjdkt.supabase.co')), `production request observed: ${external.join(', ')}`);
    const unexpectedPageErrors = pageErrors.filter(message => message !== 'Failed to fetch');
    assert.deepStrictEqual(unexpectedPageErrors, []);
    await context.close();
    console.log(JSON.stringify({ ok: true, routeCount: routes.length, plannerStationCount: stationRoutes.length, immediateBusyFeedback: true, noFullNavigation: true, mobileWidth: 390, blockedExternalRequests: external.length, productionRequests: external.filter(url => url.includes('vjdtsswhroyguxyfjdkt.supabase.co')).length, unexpectedPageErrors: unexpectedPageErrors.length, blockedBootstrapNetworkErrors: pageErrors.length - unexpectedPageErrors.length }));
  } finally {
    await browser.close();
    server.close();
  }
})().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
