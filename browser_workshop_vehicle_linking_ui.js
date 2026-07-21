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
const lifecyclePath = path.join(__dirname, 'vehicle-lifecycle-actions.js');
const refusal = 'This vehicle is not yet linked to one shared vehicle record. No change was made.';
const sensitive = {
  key: 'navision-secret-row',
  stock: '12660174',
  vin: 'MR0REBHVX00537433',
  order: '250040006',
  sourceRecord: 'restricted-source-record',
  uuid: 'be8809f4-6042-48d6-a34d-527673fe54b3',
};
const stableVehicle = {
  id: sensitive.key,
  stock: sensitive.stock,
  vin: sensitive.vin,
  order: sensitive.order,
  sourceRecordId: sensitive.sourceRecord,
};
let assertions = 0;
function check(value, message) {
  assertions += 1;
  assert.ok(value, message);
}

(async () => {
  const scripts = {
    '/vehicle-lifecycle-actions.js': fs.readFileSync(lifecyclePath),
    '/workshop-planner.js': fs.readFileSync(plannerPath),
  };
  const server = http.createServer((request, response) => {
    if (scripts[request.url]) {
      response.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8' });
      response.end(scripts[request.url]);
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
    const origin = `http://127.0.0.1:${address.port}`;
    await page.goto(`${origin}/`, { waitUntil: 'domcontentloaded' });
    await page.addScriptTag({ content: `window.escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));` });
    await page.addScriptTag({ url: `${origin}/vehicle-lifecycle-actions.js` });
    await page.addScriptTag({ url: `${origin}/workshop-planner.js` });
    await page.evaluate(() => {
      window.PDC_AUTH_CONTEXT = { role: 'operator' };
      localStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', JSON.stringify({ untouched: { marker: true } }));
      localStorage.setItem('workshopCanonicalVehicleLinks:v1', JSON.stringify({ entries: {} }));
    });
    const beforeStorage = await page.evaluate(() => ({
      edits: localStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'),
      links: localStorage.getItem('workshopCanonicalVehicleLinks:v1'),
    }));

    const cases = [
      { name: 'not_linked', vehicle: { stock: sensitive.stock }, expectedOutcome: 'unstable_identity', visibleReason: 'Not linked', resolverKind: 'not_found' },
      { name: 'not_found', vehicle: stableVehicle, expectedOutcome: 'not_found', visibleReason: 'Not found', resolverKind: 'not_found' },
      { name: 'invalid_input', vehicle: { ...stableVehicle, stock: 'STOCK-A', stockNumber: 'STOCK-B' }, expectedOutcome: 'invalid_input', visibleReason: 'Invalid input', resolverKind: 'not_found' },
      { name: 'ambiguous', vehicle: stableVehicle, expectedOutcome: 'ambiguous', visibleReason: 'Ambiguous', resolverKind: 'ambiguous' },
      { name: 'conflict', vehicle: stableVehicle, expectedOutcome: 'conflict', visibleReason: 'Conflict', resolverKind: 'conflict' },
      { name: 'archived', vehicle: stableVehicle, expectedOutcome: 'archived', visibleReason: 'Archived', resolverKind: 'archived' },
      { name: 'stale_resolver_stopped', vehicle: stableVehicle, expectedOutcome: 'service_unavailable', visibleReason: 'Stale', resolverKind: 'stopped' },
      { name: 'resolver_unavailable', vehicle: stableVehicle, expectedOutcome: 'service_unavailable', visibleReason: 'Resolver unavailable', resolverKind: 'unavailable' },
    ];

    for (const testCase of cases) {
      await page.locator('#opener').focus();
      await page.evaluate(({ testCase, uuid }) => {
        const calls = { resolver: 0, sharedVehicleCreate: 0, scheduleOrchestration: 0, bookingDispatch: 0 };
        const resolved = {
          outcome: 'resolved', vehicleId: uuid, version: 3, resolverRevision: 42,
          isArchived: testCase.resolverKind === 'archived', matchedBy: ['vin'],
        };
        let coreResolver;
        if (testCase.resolverKind === 'stopped') {
          coreResolver = createVehicleLifecycleIdentityResolver({
            client: { rpc: async () => ({ ok: false, status: 503, body: null }) },
            getAccessToken: () => null,
          });
          coreResolver.stop();
        } else {
          coreResolver = {
            async resolve() {
              calls.resolver += 1;
              if (testCase.resolverKind === 'not_found') return { outcome: 'not_found', reason: 'no_canonical_candidate' };
              if (testCase.resolverKind === 'ambiguous') return { outcome: 'ambiguous', reason: 'multiple_normalized_matches', candidateCount: 2 };
              if (testCase.resolverKind === 'conflict') return { outcome: 'conflict', reason: 'conflicting_identifiers', candidateCount: 2 };
              if (testCase.resolverKind === 'unavailable') return { outcome: 'service_unavailable', reason: 'resolver_network_failed' };
              return resolved;
            },
          };
        }
        const resolver = new Proxy(coreResolver, {
          get(target, property, receiver) {
            if (/create|insert|upsert/i.test(String(property))) {
              return async () => { calls.sharedVehicleCreate += 1; return { ok: false }; };
            }
            return Reflect.get(target, property, receiver);
          },
        });
        const vehicle = { ...testCase.vehicle };
        window.__flowPromise = (async () => {
          const ref = await workshopVerifiedCanonicalVehicleRef(vehicle, {
            resolver,
            storage: localStorage,
            modalFn: diagnostic => {
              window.__lastControlledLinkDiagnostic = diagnostic;
              return workshopVehicleLinkDiagnosticModal(diagnostic);
            },
          });
          if (ref.ok) {
            calls.scheduleOrchestration += 1;
            await workshopScheduleSharedNewBooking({
              requestedCandidate: { startAt: new Date().toISOString(), hours: 1, assignee: '' },
              vehicleRef: ref,
              stageCode: 'HOIST', bayNumber: 1,
              scheduledStartAt: new Date().toISOString(), durationMinutes: 60,
            }, async () => { calls.bookingDispatch += 1; return { ok: true }; });
          }
          return { ref, calls, vehicle };
        })();
      }, { testCase, uuid: sensitive.uuid });

      const modal = page.locator('.workshop-vehicle-link-card');
      await modal.waitFor({ state: 'visible' });
      const text = await modal.innerText();
      check(text.includes(refusal), `${testCase.name} must show the exact refusal`);
      const sharedRow = modal.locator('.workshop-link-identity > div').filter({ hasText: 'Shared vehicle UUID' });
      check(await sharedRow.locator('span').innerText() === 'Shared vehicle UUID', `${testCase.name} UUID row label missing`);
      check(await sharedRow.locator('code').innerText() === 'Missing', `${testCase.name} UUID must visibly be Missing`);
      const reasonRow = modal.locator('.workshop-link-identity > div').filter({ hasText: 'Refusal reason' });
      const renderedReason = await reasonRow.locator('code').innerText();
      const renderedDiagnostic = await page.evaluate(() => window.__lastControlledLinkDiagnostic);
      check(renderedReason.startsWith(testCase.visibleReason), `${testCase.name} visible reason mismatch: ${renderedReason}; diagnostic=${JSON.stringify(renderedDiagnostic)}`);
      check(text.includes(testCase.visibleReason), `${testCase.name} user-readable refusal reason not rendered`);
      check(await modal.locator('[data-workshop-link-save]').count() === 0, `${testCase.name} must not expose save`);
      await modal.locator('[data-workshop-link-close]').last().click();
      const result = await page.evaluate(() => window.__flowPromise);
      check(result.ref.ok === false, `${testCase.name} must refuse the controlled-link flow`);
      check(result.ref.diagnostic.outcome === testCase.expectedOutcome, `${testCase.name} diagnostic outcome mismatch`);
      check(result.calls.sharedVehicleCreate === 0, `${testCase.name} attempted shared-vehicle creation`);
      check(result.calls.scheduleOrchestration === 0, `${testCase.name} reached scheduling orchestration`);
      check(result.calls.bookingDispatch === 0, `${testCase.name} dispatched booking creation`);
      check(!result.vehicle.sharedVehicleId, `${testCase.name} persisted a shared UUID`);
      const afterCaseStorage = await page.evaluate(() => ({
        edits: localStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'),
        links: localStorage.getItem('workshopCanonicalVehicleLinks:v1'),
      }));
      check(afterCaseStorage.edits === beforeStorage.edits, `${testCase.name} changed browser-local edits`);
      check(afterCaseStorage.links === beforeStorage.links, `${testCase.name} changed browser-local links`);
    }

    await page.evaluate(({ vehicle, uuid }) => {
      window.PDC_AUTH_CONTEXT = { role: 'viewer' };
      const resolver = {
        async resolve() {
          return { outcome: 'resolved', vehicleId: uuid, version: 3, resolverRevision: 42, isArchived: false, matchedBy: ['vin'] };
        },
      };
      window.__viewerFlowPromise = workshopVerifiedCanonicalVehicleRef({ ...vehicle }, { resolver, storage: localStorage });
    }, { vehicle: stableVehicle, uuid: sensitive.uuid });
    const viewerModal = page.locator('.workshop-vehicle-link-card');
    await viewerModal.waitFor({ state: 'visible' });
    const viewerText = await viewerModal.innerText();
    check(viewerText.includes('Restricted'), 'viewer diagnostics must indicate sanitized values');
    for (const secret of Object.values(sensitive)) check(!viewerText.includes(secret), `viewer diagnostics leaked ${secret}`);
    check(await viewerModal.locator('[data-workshop-link-save]').count() === 0, 'viewer must not receive save control');
    await viewerModal.locator('[data-workshop-link-close]').last().click();
    const viewerResult = await page.evaluate(() => window.__viewerFlowPromise);
    check(viewerResult.ok === false, 'viewer flow must remain refusal-only');

    const after = await page.evaluate(() => ({
      edits: localStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'),
      links: localStorage.getItem('workshopCanonicalVehicleLinks:v1'),
    }));
    check(after.edits === beforeStorage.edits, 'rendered refusal flows changed browser-local edits');
    check(after.links === beforeStorage.links, 'rendered refusal flows changed browser-local links');

    console.log(`Rendered controlled-link refusal orchestration regression passed (${assertions} assertions).`);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {
  console.error(error);
  process.exit(1);
});
