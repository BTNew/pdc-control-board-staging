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
    if (!file.startsWith(path.resolve(root) + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end('not found'); return; }
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
        const lines = Array.from({ length: 17 }, (_, index) => ({ lineIdentity: `source:00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, sourceKind: 'authenticated', sourceLineId: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, operationNo: `OP${index + 1}`, stageCode: 'FITTING', description: `Mobile QC operation ${index + 1}`, estimatedHours: 1, completed: true, active: true, lineVersion: 1 }));
        const row = { id: 'd777b071-a2b0-5367-893b-aa83a07fcfce', stock: '13000769', stockNumber: '13000769', keyNumber: 'KEY-13000769', jobCardNumber: 'J139125493', vehicle: 'Toyota mobile QC recovery', customer: 'Staging QC recovery', pdcLocation: 'QC', manualLocation: 'QC', pdcLocationLocked: true, pdcQcComplete: false, pdcSheetVisible: true, __emailVehicleServerAuthoritative: true, __emailVehicleReadOnly: true, __emailVehicleId: 'd777b071-a2b0-5367-893b-aa83a07fcfce', __emailVehicleVersion: 34, pdcQcRetestCycleId: '245974d0-2e8f-5215-bd85-3e8e10fe9a0e', pdcQcRetestFreshCycleOpen: true, pdcQcRetestFreshPhotoAccepted: false, pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: lines };
        for (const def of [{ requireKey: 'pdcRequiresBus4x4', completeKey: 'pdcCompleteBus4x4' }, { requireKey: 'pdcRequiresTint', completeKey: 'pdcCompleteTint' }, { requireKey: 'pdcRequiresHoist', completeKey: 'pdcCompleteHoist' }, { requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting' }, { requireKey: 'pdcRequiresFabrication', completeKey: 'pdcCompleteFabrication' }, { requireKey: 'pdcRequiresElectrical', completeKey: 'pdcCompleteElectrical' }, { requireKey: 'pdcRequiresTyre', completeKey: 'pdcCompleteTyre' }, { requireKey: 'pdcRequiresPitInspection', completeKey: 'pdcCompletePitInspection' }, { requireKey: 'pdcRequiresSublet', completeKey: 'pdcCompleteSublet' }, { requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' }]) { row[def.requireKey] = true; row[def.completeKey] = true; }
        window.__qcFixtureRow = row; app.data = [row]; app.currentView = 'qc'; document.querySelector('#qc')?.classList.add('active'); document.body.classList.remove('auth-pending'); document.querySelector('.pdc-auth-gate')?.style.setProperty('display', 'none', 'important'); document.querySelector('.app-shell')?.style.setProperty('display', 'block', 'important');
        window.__qcStubCalls = []; window.__resolveQcUpload = null; window.__qcUploadAttempts = 0;
        app.emailVehicleLocationService = { snapshot: async () => ({ ok: true, data: { vehicles: [] } }), uploadQcPhotoEvidence: async (vehicleId, version, cycleId, file) => { window.__qcUploadAttempts += 1; window.__qcStubCalls.push({ kind: 'upload', vehicleId, version, cycleId, name: file.name, type: file.type }); if (window.__qcUploadAttempts === 1) return { ok: true, code: 'qc_retest_photo_accepted', data: { photo_receipt_id: 'c5bf1ec3-7a1e-5b4e-a6b6-0eae6a4e9876', bucket_id: 'pdc-qc-evidence-staging', storage_path: 'qc-finalization/test/uuid/IMG_1554.jpeg', content_type: 'image/jpeg', byte_length: 0, original_byte_length: 5440864, image_width: 0, image_height: 0, sha256: '' } }; return new Promise(resolve => { window.__resolveQcUpload = resolve; }); }, finalizeQcRetest: async (vehicleId, version, cycleId, receiptId) => { window.__qcStubCalls.push({ kind: 'finalize', vehicleId, version, cycleId, receiptId }); return { ok: true, code: 'qc_retest_signed_off_to_rft' }; } };
        renderQualityControlPage();
      });
      await page.waitForTimeout(250);
      await page.evaluate(() => { app.data = [window.__qcFixtureRow]; app.currentView = 'qc'; document.querySelector('#qc')?.classList.add('active'); document.body.classList.remove('auth-pending'); document.querySelector('.pdc-auth-gate')?.style.setProperty('display', 'none', 'important'); document.querySelector('.app-shell')?.style.setProperty('display', 'block', 'important'); renderQualityControlPage(); });
      await page.locator('[data-qc-open-vehicle="13000769"]').dispatchEvent('click');
      const input = page.locator('[data-qc-photo="13000769"]');
      const label = page.locator('.qc-photo-picker');
      assert.strictEqual(await input.getAttribute('type'), 'file'); assert.strictEqual(await input.getAttribute('accept'), 'image/*'); assert.strictEqual(await input.getAttribute('capture'), null); assert.strictEqual(await label.getAttribute('for'), await input.getAttribute('id')); assert.strictEqual(await input.isDisabled(), false); assert.strictEqual(await page.locator('.qc-work-item').count(), 17); assert.ok(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth <= 1));
      const file = { name: 'IMG_1554.jpeg', mimeType: 'image/jpeg', buffer: Buffer.alloc(5440864) };
      await input.setInputFiles(file);
      await page.locator('.qc-save-feedback.is-error').waitFor();
      assert.ok((await page.locator('.qc-save-feedback.is-error').textContent()).includes('verifiable QC photo receipt'));
      assert.ok((await page.locator('.qc-photo-preview').textContent()).includes('IMG_1554.jpeg'));
      assert.strictEqual(await page.locator('.qc-photo-picker').getAttribute('aria-disabled'), 'false');
      assert.strictEqual(await page.locator('[data-qc-signoff]').count(), 0);
      assert.strictEqual(await page.locator('[data-qc-photo-clear="13000769"]').count(), 1);
      await page.locator('[data-qc-photo="13000769"]').setInputFiles(file);
      await page.locator('.qc-photo-progress').waitFor({ state: 'attached' });
      assert.ok((await page.locator('.qc-save-feedback').textContent()).includes('Uploading QC photo'));
      assert.deepStrictEqual(await page.evaluate(() => window.__qcStubCalls[0]), { kind: 'upload', vehicleId: 'd777b071-a2b0-5367-893b-aa83a07fcfce', version: 34, cycleId: '245974d0-2e8f-5215-bd85-3e8e10fe9a0e', name: 'IMG_1554.jpeg', type: 'image/jpeg' });
      await page.evaluate(() => window.__resolveQcUpload({ ok: true, code: 'qc_retest_photo_accepted', data: { photo_receipt_id: 'c5bf1ec3-7a1e-5b4e-a6b6-0eae6a4e9876', bucket_id: 'pdc-qc-evidence-staging', storage_path: 'qc-finalization/test/uuid/IMG_1554.jpeg', content_type: 'image/jpeg', sha256: 'a'.repeat(64), original_filename: 'IMG_1554.jpeg', byte_length: 512000, original_byte_length: 5440864, image_width: 1600, image_height: 1200 } }));
      await page.locator('.qc-save-feedback.is-saved').waitFor(); assert.strictEqual(await page.locator('[data-qc-signoff]').isDisabled(), false); await page.locator('[data-qc-signoff]').dispatchEvent('click'); await page.waitForTimeout(20);
      const calls = await page.evaluate(() => window.__qcStubCalls); assert.strictEqual(calls[1].kind, 'upload'); assert.strictEqual(calls[2].kind, 'finalize'); assert.strictEqual(calls[2].receiptId, 'c5bf1ec3-7a1e-5b4e-a6b6-0eae6a4e9876'); assert.deepStrictEqual(errors, []); assert.strictEqual(external.length, 0);
      await context.close(); results.push({ viewport: `${viewport.width}x${viewport.height}`, operationLines: 17, chooserEnabled: true, labelAssociation: true, uploadProgress: true, receiptAccepted: true, finalizeChained: true, horizontalOverflow: false, externalRequests: external.length, pageErrors: errors.length });
    }
    console.log(JSON.stringify({ ok: true, results }));
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
