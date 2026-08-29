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
  return [process.env.PDC_QC_BROWSER_PATH, process.env.CHROME_PATH, process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe')].filter(Boolean).find(fs.existsSync) || '';
}
function createServer(root) {
  return http.createServer((req, res) => {
    const relative = decodeURIComponent(String(req.url || '/').split(/[?#]/, 1)[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, relative);
    if (path.relative(root, file).startsWith('..') || path.isAbsolute(path.relative(root, file)) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'Content-Type': relative.endsWith('.css') ? 'text/css' : relative.endsWith('.js') ? 'application/javascript' : 'text/html' });
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
  const results = [];
  try {
    for (const viewport of [{ width: 360, height: 800 }, { width: 390, height: 844 }, { width: 768, height: 1024 }]) {
      const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
      const page = await context.newPage();
      const external = [];
      const errors = [];
      await page.route('**/*', async route => { const target = new URL(route.request().url()); if (target.origin !== origin) { external.push(route.request().url()); await route.abort('blockedbyclient'); } else await route.continue(); });
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(`${origin}/index.html`, { waitUntil: 'networkidle' });
      await page.evaluate(() => {
        const line = (index, completed = true) => ({ lineIdentity: `source:00000000-0000-4000-8000-${String(index).padStart(12, '0')}`, sourceKind: 'authenticated', sourceLineId: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`, operationNo: `OP${index}`, stageCode: 'FITTING', description: `QC operation ${index}`, estimatedHours: 1, completed, active: true, lineVersion: 1 });
        const eligible = { id: 'd777b071-a2b0-5367-893b-aa83a07fcfce', stock: '13000769', client: 'Ahrens Group Pty Ltd', customerName: 'Ahrens Group Pty Ltd', vehicle: 'Hilux DCC', pdcLocation: 'QC', pdcQcComplete: false, pdcSheetVisible: true, __emailVehicleServerAuthoritative: true, __emailVehicleReadOnly: true, __emailVehicleId: 'd777b071-a2b0-5367-893b-aa83a07fcfce', __emailVehicleVersion: 34, pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: Array.from({ length: 17 }, (_, i) => line(i + 1, true)) };
        const unrelated = { id: '13cf8ae5-a27c-5c98-859d-3f029ecf9726', stock: '13016925', client: 'HERMAL PTY LTD', customerName: 'HERMAL PTY LTD', vehicle: 'Hilux SCC', pdcLocation: 'QC', pdcQcComplete: false, pdcSheetVisible: true, __emailVehicleServerAuthoritative: true, __emailVehicleReadOnly: true, __emailVehicleId: '13cf8ae5-a27c-5c98-859d-3f029ecf9726', __emailVehicleVersion: 8, pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: Array.from({ length: 5 }, (_, i) => line(i + 1, false)) };
        window.__qcRejectCalls = []; window.__qcFixtureRow = eligible; window.__qcPrompt = '';
        app.data = [eligible, unrelated]; app.currentView = 'qc'; document.querySelector('#qc')?.classList.add('active'); document.body.classList.remove('auth-pending'); document.querySelector('.pdc-auth-gate')?.style.setProperty('display', 'none', 'important'); document.querySelector('.app-shell')?.style.setProperty('display', 'block', 'important');
        window.prompt = () => window.__qcPrompt; window.confirm = () => true;
        app.emailVehicleLocationService = { snapshot: async () => ({ ok: true, data: { vehicles: [] } }), rejectQcVehicleToPmb: async (vehicleId, stock, version, reason, idempotencyKey) => { window.__qcRejectCalls.push({ vehicleId, stock, version, reason, idempotencyKey }); eligible.pdcLocation = 'PMB'; eligible.pdcBlocked = true; eligible.pdcBlockReason = reason; eligible.pdcQcFixRequired = true; eligible.pdcQcFixStatus = 'Pending QC fixes'; return { ok: true, code: 'qc_vehicle_rejected_to_pmb_stoppage', data: { receipt_id: '76600000-0000-5000-8000-000000000766', vehicle_id: vehicleId, stock_number: stock, vehicle_version_after: version + 1, status: 'Pending QC fixes', current_location: 'PMB', workshop_status: 'stoppage', notification_delta: 0 } }; } };
        renderQualityControlPage();
      });
      await page.waitForTimeout(200);
      const host = page.locator('#qc-page-host');
      assert.strictEqual(await host.locator('[data-qc-open-vehicle]').count(), 1);
      assert.ok((await host.textContent()).includes('Ahrens Group Pty Ltd'));
      assert.ok(!(await host.textContent()).includes('13016925'));
      assert.ok(!(await host.textContent()).includes('QUALITY CONTROL'));
      assert.ok(!(await host.textContent()).includes('Only vehicles with all required workshop work complete'));
      assert.ok(!(await host.textContent()).includes('Vehicle Locations'));
      await host.locator('[data-qc-open-vehicle="13000769"]').dispatchEvent('click');
      assert.strictEqual(await host.locator('[data-qc-reject="13000769"]').count(), 1);
      await host.locator('[data-qc-reject="13000769"]').dispatchEvent('click');
      assert.ok((await host.textContent()).includes('Enter a concise QC rejection reason'));
      assert.strictEqual(await page.evaluate(() => window.__qcRejectCalls.length), 0);
      await page.evaluate(() => { window.__qcPrompt = 'Damage to rear bumper'; });
      await host.locator('[data-qc-reject="13000769"]').dispatchEvent('click');
      await page.waitForTimeout(50);
      const call = await page.evaluate(() => window.__qcRejectCalls[0]);
      assert.deepStrictEqual({ vehicleId: call.vehicleId, stock: call.stock, version: call.version, reason: call.reason }, { vehicleId: 'd777b071-a2b0-5367-893b-aa83a07fcfce', stock: '13000769', version: 34, reason: 'Damage to rear bumper' });
      assert.strictEqual(await host.locator('[data-qc-open-vehicle]').count(), 0);
      assert.ok((await host.textContent()).includes('Pending QC fixes'));
      assert.strictEqual(await page.evaluate(() => window.__qcRejectCalls.length), 1);
      assert.strictEqual(errors.length, 0); assert.strictEqual(external.length, 0);
      await context.close(); results.push({ viewport: `${viewport.width}x${viewport.height}`, queueOnly: true, customer: 'Ahrens Group Pty Ltd', unrelatedExcluded: true, chromeRemoved: true, reasonRequired: true, exactRejectDispatch: true, queueRemoval: true, duplicateDispatches: 1, pageErrors: errors.length, externalRequests: external.length });
    }
    console.log(JSON.stringify({ ok: true, results }));
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
