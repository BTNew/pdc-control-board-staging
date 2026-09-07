'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');

function loadChromium() {
  for (const candidate of [process.env.PDC_PLAYWRIGHT_PATH, 'playwright-core'].filter(Boolean)) {
    try { return require(candidate).chromium; } catch (_) {}
  }
  throw new Error('Playwright Chromium package unavailable');
}

function browserPath() {
  return [
    process.env.PDC_QC_BROWSER_PATH,
    process.env.CHROME_PATH,
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'ms-playwright', 'chromium_headless_shell-1234', 'chrome-headless-shell-win64', 'chrome-headless-shell.exe'),
  ].filter(Boolean).find(fs.existsSync) || '';
}

function createServer(root) {
  return http.createServer((req, res) => {
    const relative = decodeURIComponent(String(req.url || '/').split(/[?#]/, 1)[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, relative);
    const escaped = path.relative(root, file);
    if (escaped.startsWith('..') || path.isAbsolute(escaped) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      res.writeHead(404); res.end('not found'); return;
    }
    res.writeHead(200, { 'Content-Type': relative.endsWith('.css') ? 'text/css' : relative.endsWith('.js') ? 'application/javascript' : 'text/html' });
    res.end(fs.readFileSync(file));
  });
}

(async () => {
  const root = __dirname;
  const server = createServer(root);
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
  const origin = `http://127.0.0.1:${server.address().port}`;
  let browser = null;
  try {
    const chromium = loadChromium();
    browser = await chromium.launch({ headless: true, ...(browserPath() ? { executablePath: browserPath() } : {}) });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, serviceWorkers: 'block' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', async route => {
      const target = new URL(route.request().url());
      if (target.origin !== origin) await route.abort('blockedbyclient');
      else await route.continue();
    });
    await page.goto(`${origin}/index.html`, { waitUntil: 'networkidle' });
    await page.evaluate(() => {
      const fixture = {
        id: '11111111-1111-4111-8111-111111111111',
        __emailVehicleId: '11111111-1111-4111-8111-111111111111',
        sharedVehicleId: '11111111-1111-4111-8111-111111111111',
        __emailVehicleServerAuthoritative: true,
        __emailVehicleReadOnly: true,
        __emailVehicleVersion: 7,
        stock: '13061263',
        client: 'DAVIE',
        customerName: 'DAVIE',
        vehicle: 'RAV4 AWD',
        pdcLocation: 'PMB',
        lifecycleState: 'active',
        pdcSheetVisible: true,
        salespersonCode: 'CW',
        jobCardNumber: '',
        pdcRequiresFitting: true,
        pdcCompleteFitting: false,
        pilbaraServiceJobCard: true,
        pilbaraServiceOperations: [{ operation_no: 'PD002-AAAAAAAA', work_key: 'fitting', job_card_number: 'JC14124588', description: 'Pre-Delivery', estimatedHours: 1.5, source_uid: 'pilbara_service_open_jobcards_v1:13061263:JC14124588:2' }],
      };
      app.data = [fixture];
      app.emailVehicleLocationRows = [fixture];
      app.selectedStock = '13061263';
      app.vehicleModalIdentity = null;
      app.vehicleModalIdentityReady = true;
      app.vehicleModalLoadingIdentity = false;
      app.vehicleDetailPage = 'details';
      document.body.classList.remove('auth-pending');
      document.querySelector('.pdc-auth-gate')?.style.setProperty('display', 'none', 'important');
      document.querySelector('.app-shell')?.style.setProperty('display', 'block', 'important');
      const modal = document.querySelector('#vehicle-modal');
      modal.hidden = false;
      document.body.classList.add('modal-open');
      renderDetail();
    });

    const form = page.locator('[data-vehicle-edit-form]');
    const consultant = form.locator('[name="consultant"]');
    const jobcard = form.locator('[name="pdcJobcard"]');
    const blocked = form.locator('[name="pdcBlocked"]');
    const blockedReason = form.locator('[name="pdcBlockReason"]');
    const customer = form.locator('[name="client"]');
    const eta = form.locator('input[readonly][placeholder="No Navision ETA"]');
    const currentTile = form.getByRole('textbox', { name: /Current PMB tile/ });
    const location = form.locator('[name="pdcLocation"]');
    const fitting = form.locator('[data-pdc-work-state="fitting"]');

    assert.strictEqual(await jobcard.isEditable(), true, 'operator-maintained JC input is editable');
    assert.strictEqual(await consultant.isEnabled(), true, 'operator-maintained salesperson dropdown is enabled');
    assert.strictEqual(await form.getAttribute('data-consultant-baseline'), await consultant.inputValue(), 'salesperson baseline matches the rendered select value');
    assert.strictEqual(await blocked.isEnabled(), true, 'operator-maintained blocked check control is enabled');
    assert.strictEqual(await fitting.isEnabled(), true, 'operator-maintained work control is enabled');
    await jobcard.click();
    await jobcard.fill('UI-SAFE-DRAFT');
    await fitting.click();
    await blocked.check();
    await blockedReason.fill('UI-SAFE-DRAFT-REASON');
    assert.strictEqual(await fitting.getAttribute('data-state'), 'complete', 'work control responds before refresh');

    const backgroundRendered = await page.evaluate(() => renderVehicleDetailAfterBackgroundRefresh());

    assert.strictEqual(backgroundRendered, false, 'background refresh does not replace an open operator draft form');
    assert.strictEqual(await jobcard.inputValue(), 'UI-SAFE-DRAFT', 'late Service/detail refresh must not replace an operator draft');
    assert.strictEqual(await fitting.getAttribute('data-state'), 'complete', 'late Service/detail refresh must not undo a clicked work control');
    assert.strictEqual(await blocked.isChecked(), true, 'late Service/detail refresh must not undo an operator checkbox');
    assert.strictEqual(await blockedReason.inputValue(), 'UI-SAFE-DRAFT-REASON', 'late Service/detail refresh must not replace an operator reason draft');
    assert.strictEqual(await page.locator('[data-vehicle-edit-form]').count(), 1, 'one live editor remains mounted');
    assert.strictEqual(await customer.isEditable(), false, 'Navision-authoritative customer remains read-only');
    assert.strictEqual(await eta.isEditable(), false, 'Navision ETA remains read-only');
    assert.strictEqual(await currentTile.isEditable(), false, 'workflow-only PMB bucket remains read-only');
    assert.strictEqual(await location.isEnabled(), false, 'workflow-only location movement remains disabled in Vehicle Detail');
    const authorityTransitionRendered = await page.evaluate(() => {
      app.data[0].__emailVehicleServerAuthoritative = false;
      app.emailVehicleLocationRows[0].__emailVehicleServerAuthoritative = false;
      return renderVehicleDetailAfterBackgroundRefresh();
    });
    assert.strictEqual(authorityTransitionRendered, true, 'an authority-boundary change must replace the stale form and submit closure');
    assert.strictEqual(await page.locator('[data-vehicle-edit-form] [name="client"]').isEditable(), true, 'non-authoritative customer policy is rendered only after the authority transition');
    assert.deepStrictEqual(errors, [], `page errors: ${errors.join('; ')}`);
    await context.close();
    console.log('Vehicle Detail operator interactivity under late Service refresh: PASS');
  } finally {
    try {
      if (browser) await browser.close();
    } finally {
      await new Promise(resolve => server.close(resolve));
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
