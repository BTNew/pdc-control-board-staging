'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

function loadChromium() {
  for (const candidate of [
    process.env.PDC_PLAYWRIGHT_PATH,
    'playwright',
    'playwright-core',
    path.join(__dirname, '_staging_test_tools', 'node-playwright', 'node_modules', 'playwright-core'),
    path.join(os.tmpdir(), 'pdc-phase-a-playwright', 'node_modules', 'playwright'),
  ].filter(Boolean)) {
    try { return require(candidate).chromium; } catch (_) {}
  }
  throw new Error('Playwright is required. Set PDC_PLAYWRIGHT_PATH to an existing playwright or playwright-core package.');
}

function installedChromiumPath() {
  return [
    process.env.PDC_QC_BROWSER_PATH,
    process.env.CHROME_PATH,
    process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Google', 'Chrome', 'Application', 'chrome.exe'),
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe'),
  ].filter(candidate => candidate && fs.existsSync(candidate))[0] || '';
}

const root = __dirname;
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png' };
const PUBLIC_FIXTURE_ASSETS = new Set([
  'test-75.html',
  'favicon.svg',
  'styles.css',
  'desktop-operations.css',
  'workshop-planner.css',
  'assets/pmb-logo.png',
  'data-test-75.js',
  'arb-labor-catalog.js',
  'ai-board-advisor.js',
  'workshop-eligibility.js',
  'workshop-data-service.js',
  'workshop-planner.js',
  'workshop-realtime.js',
  'workshop-shared-actions.js',
  'vehicle-location-lifecycle.js',
  'app.js',
]);
const responseSecurityHeaders = {
  'Cache-Control': 'no-store',
  'Content-Security-Policy': "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
};

function sameFilesystemPath(left, right) {
  const normalize = value => process.platform === 'win32' ? value.toLowerCase() : value;
  return normalize(path.resolve(left)) === normalize(path.resolve(right));
}

function confinedRegularFile(rootPath, relativeFile) {
  const rootInfo = fs.lstatSync(rootPath);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) return '';
  const realRoot = fs.realpathSync(rootPath);
  if (!sameFilesystemPath(realRoot, rootPath)) return '';

  const candidate = path.resolve(rootPath, ...relativeFile.split('/'));
  const relative = path.relative(rootPath, candidate);
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) return '';

  let current = rootPath;
  const components = relative.split(path.sep).filter(Boolean);
  for (let index = 0; index < components.length; index += 1) {
    current = path.join(current, components[index]);
    const info = fs.lstatSync(current);
    if (info.isSymbolicLink()) return '';
    if (index < components.length - 1 && !info.isDirectory()) return '';
    if (index === components.length - 1 && !info.isFile()) return '';
  }

  const realFile = fs.realpathSync(candidate);
  const realRelative = path.relative(realRoot, realFile);
  if (realRelative === '..' || realRelative.startsWith(`..${path.sep}`) || path.isAbsolute(realRelative)) return '';
  return realFile;
}

function createFixtureServer(fixtureRoot = root, allowlist = PUBLIC_FIXTURE_ASSETS) {
  let rootPath = '';
  try { rootPath = path.resolve(String(fixtureRoot)); } catch (_) {}
  return http.createServer((request, response) => {
    const reject = () => {
      response.writeHead(404, { ...responseSecurityHeaders, 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('not found');
    };
    try {
      if (!rootPath || !['GET', 'HEAD'].includes(request.method || '') || !(allowlist instanceof Set)) return reject();
      const requestTarget = String(request.url || '');
      if (!requestTarget.startsWith('/') || requestTarget.startsWith('//')) return reject();
      new URL(requestTarget, 'http://127.0.0.1');
      const encodedPath = requestTarget.split(/[?#]/, 1)[0];
      if (/%(?:2f|5c)/i.test(encodedPath)) return reject();
      const decodedPath = decodeURIComponent(encodedPath);
      if (!decodedPath.startsWith('/') || decodedPath.startsWith('//') || decodedPath.includes('\\') || decodedPath.includes('\0')) return reject();
      const relativeFile = decodedPath === '/' ? 'test-75.html' : decodedPath.slice(1);
      const segments = relativeFile.split('/');
      if (segments.some(segment => !segment || segment === '.' || segment === '..') || !allowlist.has(relativeFile)) return reject();
      const file = confinedRegularFile(rootPath, relativeFile);
      if (!file) return reject();
      const body = fs.readFileSync(file);
      response.writeHead(200, {
        ...responseSecurityHeaders,
        'Content-Length': body.length,
        'Content-Type': `${mime[path.extname(file)] || 'application/octet-stream'}; charset=utf-8`,
      });
      response.end(request.method === 'HEAD' ? undefined : body);
    } catch (_) {
      if (!response.headersSent) reject();
      else response.destroy();
    }
  });
}

const viewports = [
  { width: 360, height: 800 },
  { width: 390, height: 844 },
  { width: 768, height: 1024 },
  { width: 820, height: 1180 },
  { width: 1024, height: 768 },
  { width: 1440, height: 900 },
];

async function blockNonLocalRequests(page, origin, externalRequests, externalWebSockets) {
  await page.route('**/*', async route => {
    let url;
    try { url = new URL(route.request().url()); } catch (_) {}
    if (!url || url.origin !== origin) {
      externalRequests.push(route.request().url());
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  });
  await page.routeWebSocket('**/*', webSocketRoute => {
    let url;
    let localOrigin;
    try {
      url = new URL(webSocketRoute.url());
      localOrigin = new URL(origin);
    } catch (_) {}
    const isLocal = url && localOrigin && url.protocol === 'ws:' && url.host === localOrigin.host;
    if (!isLocal) {
      externalWebSockets.push(webSocketRoute.url());
      webSocketRoute.close({ code: 1008, reason: 'Non-local WebSocket blocked by QC harness' });
      return;
    }
    const serverSocket = webSocketRoute.connectToServer();
    webSocketRoute.onMessage(message => serverSocket.send(message));
    serverSocket.onMessage(message => webSocketRoute.send(message));
    webSocketRoute.onClose((code, reason) => serverSocket.close({ code, reason }));
    serverSocket.onClose((code, reason) => webSocketRoute.close({ code, reason }));
  });
}

async function runBrowserHarness() {
  const chromium = loadChromium();
  const server = createFixtureServer();
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const executablePath = installedChromiumPath();
  const browser = await chromium.launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  const results = [];
  try {
    for (const viewport of viewports) {
      const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
      const page = await context.newPage();
      const consoleErrors = [];
      const pageErrors = [];
      const failedResources = [];
      const externalRequests = [];
      const externalWebSockets = [];
      page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
      page.on('pageerror', error => pageErrors.push(error.message));
      page.on('requestfailed', request => failedResources.push(`${request.method()} ${request.url()} ${request.failure()?.errorText || ''}`));
      await blockNonLocalRequests(page, origin, externalRequests, externalWebSockets);

      await page.goto(`${origin}/test-75.html`, { waitUntil: 'networkidle' });
      const renderMs = await page.evaluate(() => {
        app.data = [{
          id: 'qc-mobile-fixture',
          stock: 'QC-MOBILE-123456789',
          stockNumber: 'QC-MOBILE-123456789',
          keyNumber: 'KEY-987654321',
          jobCardNumber: 'JC-123456789012',
          customer: 'A Long Customer Name That Must Remain Visible On Touch Screens',
          vehicle: 'Toyota LandCruiser 79 Double Cab with long model description',
          vin: 'JTEBR3FJ10K123456',
          rego: '1QC234',
          pdcLocation: 'QC',
          manualLocation: 'QC',
          pdcLocationLocked: true,
          pdcQcComplete: false,
          pdcRequiresParts: true,
          pdcPartsComplete: true,
          pdcRequiresFitting: true,
          pdcFittingComplete: true,
          pdcRequiresElectrical: true,
          pdcElectricalComplete: true,
        }];
        const started = performance.now();
        renderIncomingDashboardBoard();
        return performance.now() - started;
      });

      await page.locator('.incoming-qc').evaluate(element => { element.open = true; });
      const row = page.locator('[data-incoming-row="QC-MOBILE-123456789"]');
      await row.waitFor({ state: 'visible' });
      const summary = row.locator('summary');
      await summary.focus();
      await page.keyboard.press('Enter');
      assert.strictEqual(await row.getAttribute('open'), '', `${viewport.width}px summary opens from keyboard`);

      const metrics = await page.evaluate(() => {
        const row = document.querySelector('[data-incoming-row="QC-MOBILE-123456789"]');
        const list = row.closest('.incoming-bucket-list');
        const summary = row.querySelector('summary');
        const action = row.querySelector('[data-qc-signoff-rft]');
        const work = row.querySelector('.incoming-work-checks');
        const details = row.querySelector('.incoming-vehicle-detail-grid');
        const header = list.querySelector('.incoming-production-grid-header');
        const identityValues = Array.from(row.querySelectorAll('.incoming-identity .vehicle-identity-value'));
        const labels = Array.from(row.querySelectorAll('.incoming-work-label'));
        const listRect = list.getBoundingClientRect();
        const actionRect = action.getBoundingClientRect();
        const rowRect = row.getBoundingClientRect();
        const summaryRect = summary.getBoundingClientRect();
        const workRect = work.getBoundingClientRect();
        const detailsRect = details.getBoundingClientRect();
        return {
          bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          listOverflow: list.scrollWidth - list.clientWidth,
          rowWidth: rowRect.width,
          listWidth: listRect.width,
          summaryWidth: summaryRect.width,
          workWidth: workRect.width,
          detailsWidth: detailsRect.width,
          actionHeight: actionRect.height,
          actionVisible: actionRect.left >= listRect.left - 1 && actionRect.right <= listRect.right + 1,
          actionText: action.textContent.trim(),
          workAria: work.getAttribute('aria-label'),
          labelsVisible: labels.every(label => getComputedStyle(label).display !== 'none' && label.getBoundingClientRect().height > 0),
          headerVisible: Boolean(header && getComputedStyle(header).display !== 'none' && header.getBoundingClientRect().height > 0),
          clippedIdentities: identityValues.filter(value => value.scrollWidth > value.clientWidth + 1 || value.scrollHeight > value.clientHeight + 1).map(value => value.textContent.trim()),
          detailsMinWidth: getComputedStyle(details).minWidth,
        };
      });

      assert.ok(metrics.bodyOverflow <= 1, `${viewport.width}px has no body-level horizontal overflow: ${JSON.stringify(metrics)}`);
      assert.ok(metrics.actionVisible, `${viewport.width}px QC action is reachable without scrolling the desktop row: ${JSON.stringify(metrics)}`);
      assert.strictEqual(metrics.actionText, 'Sign off & print label', `${viewport.width}px keeps the existing authorised QC action`);
      assert.ok(metrics.workAria.includes('QC-MOBILE-123456789'), `${viewport.width}px station group names its vehicle`);
      if (viewport.width <= 1100) {
        assert.deepStrictEqual(metrics.clippedIdentities, [], `${viewport.width}px rendered identity values do not collide or clip`);
        assert.ok(metrics.labelsVisible, `${viewport.width}px station names are visible without hover`);
        assert.ok(metrics.listOverflow <= 1, `${viewport.width}px QC cards do not retain desktop-grid panning: ${JSON.stringify(metrics)}`);
        assert.ok(metrics.rowWidth <= metrics.listWidth + 1 && metrics.workWidth <= metrics.summaryWidth + 1 && metrics.detailsWidth <= metrics.summaryWidth + 1, `${viewport.width}px card content stays within the list`);
        assert.ok(metrics.actionHeight >= 44, `${viewport.width}px primary QC action meets the 44px target`);
      } else {
        assert.ok(metrics.headerVisible, `${viewport.width}px desktop station headings remain visible`);
      }

      assert.deepStrictEqual(consoleErrors, [], `${viewport.width}px console errors`);
      assert.deepStrictEqual(pageErrors, [], `${viewport.width}px page errors`);
      assert.deepStrictEqual(failedResources, [], `${viewport.width}px failed resources`);
      assert.deepStrictEqual(externalRequests, [], `${viewport.width}px external/production requests`);
      assert.deepStrictEqual(externalWebSockets, [], `${viewport.width}px external WebSocket attempts`);
      results.push({ viewport: `${viewport.width}x${viewport.height}`, renderMs: Number(renderMs.toFixed(2)), ...metrics });
      await context.close();
    }

    const guardExternalRequests = [];
    const guardExternalWebSockets = [];
    const serviceWorkerRequests = [];
    const guardContext = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'block' });
    const guardPage = await guardContext.newPage();
    guardPage.on('request', request => {
      if (new URL(request.url()).pathname === '/service-worker-hostile.js') serviceWorkerRequests.push(request.url());
    });
    await blockNonLocalRequests(guardPage, origin, guardExternalRequests, guardExternalWebSockets);
    await guardPage.goto('data:text/html,<title>QC network boundary probe</title>');
    const externalHttpProbe = await guardPage.evaluate(() => fetch('https://non-local.invalid/qc-harness-probe')
      .then(() => 'opened', () => 'blocked'));
    assert.strictEqual(externalHttpProbe, 'blocked', 'external HTTP request is aborted by the browser route before connecting');
    assert.deepStrictEqual(guardExternalRequests, ['https://non-local.invalid/qc-harness-probe'], 'external HTTP attempt is recorded exactly once');
    guardExternalRequests.length = 0;
    const externalWebSocketProbe = await guardPage.evaluate(() => new Promise(resolve => {
      const socket = new WebSocket('wss://non-local.invalid/qc-harness-probe');
      socket.addEventListener('open', () => resolve('opened'), { once: true });
      socket.addEventListener('error', () => resolve('blocked'), { once: true });
      socket.addEventListener('close', () => resolve('blocked'), { once: true });
      setTimeout(() => resolve('timeout'), 1000);
    }));
    assert.strictEqual(externalWebSocketProbe, 'blocked', 'external WebSocket is closed by the browser route before connecting');
    assert.deepStrictEqual(guardExternalWebSockets, ['wss://non-local.invalid/qc-harness-probe'], 'external WebSocket attempt is recorded exactly once');
    await guardPage.goto(`${origin}/test-75.html`, { waitUntil: 'networkidle' });
    const serviceWorkerProbe = await guardPage.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return { supported: false, registrationReturned: false, registrations: 0, controlled: false };
      const registration = await navigator.serviceWorker.register('/service-worker-hostile.js');
      const registrations = await navigator.serviceWorker.getRegistrations();
      return {
        supported: true,
        registrationReturned: Boolean(registration),
        registrations: registrations.length,
        controlled: Boolean(navigator.serviceWorker.controller),
      };
    });
    assert.deepStrictEqual(serviceWorkerProbe, { supported: true, registrationReturned: false, registrations: 0, controlled: false }, 'service-worker registration is inert and creates no registration or controller');
    assert.deepStrictEqual(serviceWorkerRequests, [], 'blocked service-worker registration emits no script request');
    const rapid = await guardPage.evaluate(async () => {
      const button = document.createElement('button');
      button.dataset.qcSignoffRft = 'QC-RAPID-1';
      document.body.append(button);
      let calls = 0;
      let release;
      const pending = new Promise(resolve => { release = resolve; });
      const first = runVehicleLifecycleButtonAction(button, async () => { calls += 1; await pending; return true; });
      const busyDuring = button.disabled && button.getAttribute('aria-busy') === 'true';
      const replacement = document.createElement('button');
      replacement.dataset.qcSignoffRft = 'QC-RAPID-1';
      button.replaceWith(replacement);
      const second = runVehicleLifecycleButtonAction(replacement, async () => { calls += 1; return true; });
      release();
      const values = await Promise.all([first, second]);
      return { calls, busyDuring, replacementDisabledAfter: replacement.disabled, replacementBusyAfter: replacement.hasAttribute('aria-busy'), values };
    });
    assert.deepStrictEqual(rapid, { calls: 1, busyDuring: true, replacementDisabledAfter: false, replacementBusyAfter: false, values: [true, false] }, 'rerendered rapid QC actions dispatch once for the same vehicle and action');

    await guardPage.evaluate(() => {
      app.data = [{
        id: 'qc-dialog-fixture', stock: 'QC-DIALOG-1', stockNumber: 'QC-DIALOG-1', keyNumber: 'KEY-1',
        customer: 'Dialog Test Customer', vehicle: 'Dialog Test Vehicle', pdcLocation: 'QC', manualLocation: 'QC', pdcQcComplete: false,
      }];
      renderIncomingDashboardBoard();
      document.querySelector('.incoming-qc').open = true;
    });
    const opener = guardPage.locator('[data-incoming-row="QC-DIALOG-1"] .incoming-open-button');
    await opener.focus();
    await opener.click();
    assert.strictEqual(await guardPage.locator('#vehicle-modal').getAttribute('hidden'), null, 'vehicle dialog opens from the QC card');
    assert.strictEqual(await guardPage.locator('#modal-close').evaluate(element => document.activeElement === element), true, 'vehicle dialog receives initial focus');
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), '', 'vehicle dialog makes the application background inert');
    const lastFocusableSelector = await guardPage.evaluate(() => {
      const focusable = vehicleModalFocusableElements();
      focusable[focusable.length - 1].focus();
      return focusable[focusable.length - 1].id || focusable[focusable.length - 1].getAttribute('data-vehicle-detail-tab') || focusable[focusable.length - 1].tagName;
    });
    await guardPage.keyboard.press('Tab');
    assert.strictEqual(await guardPage.locator('#modal-close').evaluate(element => document.activeElement === element), true, `Tab wraps from the final dialog control (${lastFocusableSelector}) to Close`);
    await guardPage.keyboard.press('Shift+Tab');
    assert.strictEqual(await guardPage.evaluate(() => {
      const focusable = vehicleModalFocusableElements();
      return document.activeElement === focusable[focusable.length - 1];
    }), true, 'Shift+Tab wraps from Close to the final dialog control');
    await guardPage.locator('#vehicle-modal').evaluate(modal => {
      modal.classList.add('vehicle-workshop-drag-handoff');
      modal.dispatchEvent(new DragEvent('dragstart', { bubbles: true }));
    });
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), null, 'workshop drag handoff temporarily releases background inertness');
    await guardPage.locator('#vehicle-modal').evaluate(modal => {
      modal.classList.remove('vehicle-workshop-drag-handoff');
      modal.dispatchEvent(new DragEvent('dragend', { bubbles: true }));
    });
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), '', 'an unfinished workshop drag restores dialog background inertness');
    await guardPage.keyboard.press('Escape');
    assert.strictEqual(await guardPage.locator('#vehicle-modal').getAttribute('hidden'), '', 'Escape closes the vehicle dialog');
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), null, 'closing restores background interactivity');
    assert.strictEqual(await opener.evaluate(element => document.activeElement === element), true, 'closing returns focus to the QC card opener');
    await opener.click();
    await guardPage.locator('#app-shell').evaluate(shell => shell.setAttribute('aria-hidden', 'true'));
    await guardPage.keyboard.press('Escape');
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), '', 'closing never removes an auth-owned inert state');
    await guardPage.locator('#app-shell').evaluate(shell => {
      shell.removeAttribute('aria-hidden');
      shell.removeAttribute('inert');
    });
    await opener.focus();
    await guardPage.evaluate(() => {
      const opened = openPdcAuditorSnapshotVehicleDetail({
        stock_number: 'AUDITOR-READ-ONLY-1',
        model: 'Auditor snapshot fixture',
        location: { code: 'QC' },
        workshop: { status: 'ready' },
        lifecycle: { state: 'qc' },
        work_items: [],
        bookings: [],
      });
      if (!opened) throw new Error('Auditor read-only Vehicle Details fixture did not open');
    });
    assert.strictEqual(await guardPage.locator('#app-shell').getAttribute('inert'), '', 'shared focus lifecycle covers the direct Auditor Vehicle Details opener');
    await guardPage.keyboard.press('Escape');
    assert.strictEqual(await opener.evaluate(element => document.activeElement === element), true, 'the direct Auditor Vehicle Details opener also returns focus');
    const printFailure = await guardPage.evaluate(async () => {
      const alerts = [];
      const originalAlert = window.alert;
      const originalQz = window.qz;
      window.alert = message => alerts.push(String(message));
      window.qz = undefined;
      try {
        const result = await printRawZpl('^XA^XZ', 'QC sign-off label', 'QC was saved and the vehicle is RFT, but the windscreen label did not print.');
        return { result, alerts };
      } finally {
        window.alert = originalAlert;
        window.qz = originalQz;
      }
    });
    assert.strictEqual(printFailure.result.ok, false, 'a local printer failure returns an explicit failed result');
    assert.ok(printFailure.alerts[0]?.startsWith('QC was saved and the vehicle is RFT, but the windscreen label did not print.'), 'printer failure truthfully preserves the committed QC/RFT result');
    assert.deepStrictEqual(guardExternalRequests, [], 'guard interactions make no external/production requests');
    await guardContext.close();

    console.log(`QC mobile browser reliability passed: ${JSON.stringify({ externalHttpProbe, externalWebSocketProbe, serviceWorkerProbe, rapid, results })}`);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}

module.exports = { PUBLIC_FIXTURE_ASSETS, createFixtureServer, runBrowserHarness };

if (require.main === module) {
  runBrowserHarness().catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
