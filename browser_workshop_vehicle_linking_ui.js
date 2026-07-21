'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');
let chromium;
for (const candidate of [
  './_staging_test_tools/node-playwright/node_modules/playwright-core',
  'C:/Users/nwmgr/AppData/Local/Temp/pdc-phase-a-playwright/node_modules/playwright',
]) {
  try {
    ({ chromium } = require(candidate));
    break;
  } catch (_) {
    // Try the next approved local Playwright installation.
  }
}
if (!chromium) throw new Error('Playwright is required for the rendered vehicle-link diagnostics regression.');

const plannerPath = path.join(__dirname, 'workshop-planner.js');
const refusal = 'This vehicle is not yet linked to one shared vehicle record. No change was made.';
const sensitive = {
  key: 'navision-secret-row',
  stock: '12660174',
  vin: 'MR0REBHVX00537433',
  sourceRecord: 'restricted-source-record',
  uuid: 'be8809f4-6042-48d6-a34d-527673fe54b3',
};
let assertions = 0;
function check(value, message) {
  assertions += 1;
  assert.ok(value, message);
}

function rejectedDiagnostic(outcome, rejectedReason) {
  return {
    browserLocalIdentity: {
      vehicleKey: sensitive.key,
      stockNumber: sensitive.stock,
      vin: sensitive.vin,
      sourceSystem: 'browser_local_c4',
      sourceRecordId: sensitive.sourceRecord,
      savedSharedUuid: null,
    },
    sharedUuid: null,
    outcome,
    linkState: 'rejected',
    rejectedReason,
    exactRemediation: 'Complete controlled identity review before retrying.',
    candidateProcess: [{ identifier: 'vin', value: sensitive.vin, outcome, reason: rejectedReason }],
  };
}

(async () => {
  const plannerSource = fs.readFileSync(plannerPath);
  const server = http.createServer((request, response) => {
    if (request.url === '/workshop-planner.js') {
      response.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8' });
      response.end(plannerSource);
      return;
    }
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end('<!doctype html><html><body><button id="opener">Open diagnostics</button></body></html>');
  });
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
  const browser = await chromium.launch({ headless: true, executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  const page = await browser.newPage();
  try {
    const address = server.address();
    await page.goto(`http://127.0.0.1:${address.port}/`, { waitUntil: 'domcontentloaded' });
    await page.addScriptTag({ content: `window.escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));` });
    await page.addScriptTag({ url: `http://127.0.0.1:${address.port}/workshop-planner.js` });
    await page.evaluate(() => {
      window.PDC_AUTH_CONTEXT = { role: 'operator' };
      window.__sharedVehicleCreates = 0;
      window.__bookingCreates = 0;
      localStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', JSON.stringify({ untouched: { marker: true } }));
      localStorage.setItem('workshopCanonicalVehicleLinks:v1', JSON.stringify({ entries: {} }));
    });
    const beforeStorage = await page.evaluate(() => ({
      edits: localStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'),
      links: localStorage.getItem('workshopCanonicalVehicleLinks:v1'),
    }));

    const cases = [
      ['not_found', 'not_found:no_canonical_candidate', 'Not found'],
      ['invalid_input', 'invalid_input:vin', 'Invalid input'],
      ['ambiguous', 'ambiguous:multiple_normalized_matches', 'Ambiguous'],
      ['conflict', 'conflict:conflicting_identifiers', 'Conflict'],
      ['archived', 'archived:canonical_vehicle_archived', 'Archived'],
      ['conflict', 'stale:saved_identity_changed', 'Stale'],
      ['service_unavailable', 'service_unavailable:resolver_missing', 'Resolver unavailable'],
    ];
    for (const [outcome, rejectedReason, visibleReason] of cases) {
      const diagnostic = rejectedDiagnostic(outcome, rejectedReason);
      await page.locator('#opener').focus();
      await page.evaluate(value => { window.__diagnosticPromise = workshopVehicleLinkDiagnosticModal(value); }, diagnostic);
      const modal = page.locator('.workshop-vehicle-link-card');
      await modal.waitFor({ state: 'visible' });
      const text = await modal.innerText();
      check(text.includes(refusal), `${outcome} must show the exact refusal`);
      const sharedRow = modal.locator('.workshop-link-identity > div').filter({ hasText: 'Shared vehicle UUID' });
      check(await sharedRow.locator('span').innerText() === 'Shared vehicle UUID', `${outcome} UUID row label missing`);
      check(await sharedRow.locator('code').innerText() === 'Missing', `${outcome} UUID must visibly be Missing`);
      const reasonRow = modal.locator('.workshop-link-identity > div').filter({ hasText: 'Refusal reason' });
      check((await reasonRow.locator('code').innerText()).startsWith(visibleReason), `${outcome} visible reason mismatch`);
      check(text.includes(visibleReason), `${outcome} user-readable refusal reason not rendered`);
      check(await modal.locator('[data-workshop-link-save]').count() === 0, `${outcome} must not expose save`);
      await modal.locator('[data-workshop-link-close]').last().click();
      check(await page.evaluate(() => window.__diagnosticPromise) === 'close', `${outcome} modal did not close without change`);
    }

    const viewerDiagnostic = {
      ...rejectedDiagnostic('resolved', null),
      sharedUuid: sensitive.uuid,
      outcome: 'resolved',
      linkState: 'ready_to_save',
      rejectedReason: null,
      candidateProcess: [{ identifier: 'vin', value: sensitive.vin, outcome: 'resolved', sharedUuid: sensitive.uuid }],
    };
    await page.evaluate(value => {
      window.PDC_AUTH_CONTEXT = { role: 'viewer' };
      window.__diagnosticPromise = workshopVehicleLinkDiagnosticModal(value);
    }, viewerDiagnostic);
    const viewerModal = page.locator('.workshop-vehicle-link-card');
    await viewerModal.waitFor({ state: 'visible' });
    const viewerText = await viewerModal.innerText();
    check(viewerText.includes('Restricted'), 'viewer diagnostics must indicate sanitized values');
    for (const secret of Object.values(sensitive)) check(!viewerText.includes(secret), `viewer diagnostics leaked ${secret}`);
    check(await viewerModal.locator('[data-workshop-link-save]').count() === 0, 'viewer must not receive save control');
    await viewerModal.locator('[data-workshop-link-close]').last().click();

    const after = await page.evaluate(() => ({
      edits: localStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'),
      links: localStorage.getItem('workshopCanonicalVehicleLinks:v1'),
      sharedVehicleCreates: window.__sharedVehicleCreates,
      bookingCreates: window.__bookingCreates,
    }));
    check(after.edits === beforeStorage.edits, 'refusal UI changed browser-local edits');
    check(after.links === beforeStorage.links, 'refusal UI changed browser-local links');
    check(after.sharedVehicleCreates === 0, 'refusal UI created a shared vehicle');
    check(after.bookingCreates === 0, 'refusal UI created a booking');

    console.log(`Rendered vehicle-link refusal UI regression passed (${assertions} assertions).`);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {
  console.error(error);
  process.exit(1);
});
