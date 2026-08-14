'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { createWorkshopOperationRemovalService } = require('./workshop-data-service.js');

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

function read(name) { return fs.readFileSync(path.join(__dirname, name), 'utf8'); }

test('production and staging load browser-safe navigation before app runtime', () => {
  for (const name of ['index.html', 'staging.html']) {
    const html = read(name);
    assert(html.includes('workshop-navigation.js'));
    assert(html.indexOf('workshop-navigation.js') < html.indexOf('app.js'));
  }
});

test('actual control-board tiles carry deterministic Work and bookings context', () => {
  const source = read('app.js');
  assert(source.includes('data-open-work-bookings'));
  assert(source.includes('data-work-station'));
  assert(source.includes('data-work-bay'));
  assert(source.includes("app.vehicleDetailPage = 'work'"));
  assert(source.includes('buildWorkBookingsNavigationIntent'));
});

test('planner runtime executes exported highlight API for stale clear, replacement pulse, and reduced motion', () => {
  const source = read('workshop-navigation.js');
  const browser = { matchMedia: () => ({ matches: false }) };
  const context = { window: browser };
  require('vm').runInNewContext(source, context, { filename: 'workshop-navigation.js' });
  assert.strictEqual(typeof browser.WorkshopNavigation.replaceWorkshopHighlight, 'function');

  function element(...initial) {
    const classes = new Set(initial);
    return {
      classList: {
        add: value => classes.add(value),
        remove: value => classes.delete(value),
        contains: value => classes.has(value),
      },
    };
  }
  const stale = element('is-workshop-navigation-pulse');
  const first = element();
  const reduced = element();
  const root = {
    querySelectorAll: selector => [stale, first, reduced].filter(item =>
      selector.split(',').some(token => item.classList.contains(token.trim().slice(1)))),
  };

  const normalResult = browser.WorkshopNavigation.replaceWorkshopHighlight(root, first, {
    highlightClass: 'is-workshop-navigation-pulse',
    reducedMotionClass: 'is-workshop-navigation-pulse-reduced-motion',
    prefersReducedMotion: false,
  });
  assert.strictEqual(stale.classList.contains('is-workshop-navigation-pulse'), false, 'stale pulse must clear');
  assert.strictEqual(first.classList.contains('is-workshop-navigation-pulse'), true, 'replacement must visibly pulse');
  assert.strictEqual(normalResult.presentation.animate, true);

  const reducedResult = browser.WorkshopNavigation.replaceWorkshopHighlight(root, reduced, {
    highlightClass: 'is-workshop-navigation-pulse',
    reducedMotionClass: 'is-workshop-navigation-pulse-reduced-motion',
    prefersReducedMotion: { matches: true },
  });
  assert.strictEqual(first.classList.contains('is-workshop-navigation-pulse'), false, 'second replacement must clear prior target');
  assert.strictEqual(reduced.classList.contains('is-workshop-navigation-pulse-reduced-motion'), true, 'reduced motion keeps visible replacement');
  assert.strictEqual(reduced.classList.contains('is-workshop-navigation-pulse'), false, 'reduced motion must not pulse');
  assert.strictEqual(reducedResult.presentation.animate, false);
});

test('changed runtime assets share one cache/provenance candidate', () => {
  const candidate = '2026.08.14.57-reference-owner-fallback-proof';
  for (const name of ['index.html', 'staging.html']) {
    const html = read(name);
    assert(html.includes(`styles.css?v=${candidate}`));
    assert(html.includes(`workshop-navigation.js?v=${candidate}`));
    assert(html.includes(`app.js?v=${candidate}`));
    assert(html.includes(`Version ${candidate}`));
  }
  const appSource = read('app.js');
  assert(appSource.includes(`const APP_VERSION = '${candidate}'`));
  assert(appSource.includes('const WORKSHOP_PLANNER_SCRIPT_VERSION = APP_VERSION'));
  assert(appSource.includes('workshop-data-service.js?v=${encodeURIComponent(APP_VERSION)}'));
  assert(appSource.includes('workshop-planner.js?v=${encodeURIComponent(WORKSHOP_PLANNER_SCRIPT_VERSION)}'));
});

test('hours projection is rendered with evidence and strict precedence helper', () => {
  const source = read('app.js');
  assert(source.includes('WorkshopNavigation.projectWorkshopHours'));
  assert(source.includes('Manual override · scheduling authority'));
  assert(source.includes('Protected estimate · scheduling authority'));
  assert(source.includes('Source evidence · scheduling authority'));
  assert(source.includes('AI fallback · no source estimate'));
});

test('migration 235 removal bridge is Administrator-only and sends exact RPC contract', async () => {
  const calls = [];
  let refreshes = 0;
  const service = createWorkshopOperationRemovalService({
    client: { rpc: async (token, name, params) => { calls.push({ token, name, params }); return { ok: true, body: { ok: true, code: 'operation_removed', data: { receipt_id: 'r-1' } } }; } },
    getAccessToken: () => 'token',
    getRole: () => 'Administrator',
    refresh: async () => { refreshes += 1; },
  });
  const result = await service.removeOperation({ operationLineId: 'op-1', expectedAdjustmentVersion: 4, reason: 'Incorrect line', sourceEvidence: { source: 'ui' }, idempotencyKey: 'ui-key-123' });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(calls[0].name, 'remove_pdc_workshop_operation_line_235');
  assert.deepStrictEqual(calls[0].params, { p_operation_line_id: 'op-1', p_expected_adjustment_version: 4, p_reason: 'Incorrect line', p_source_evidence: { source: 'ui' }, p_idempotency_key: 'ui-key-123' });
  assert.strictEqual(refreshes, 1);
});

test('removal bridge requires reason/idempotency and fails closed without Administrator', async () => {
  let called = false;
  const service = createWorkshopOperationRemovalService({ client: { rpc: async () => { called = true; } }, getAccessToken: () => 'token', getRole: () => 'Operator' });
  assert.deepStrictEqual(await service.removeOperation({ operationLineId: 'op', reason: 'Valid', sourceEvidence: {}, idempotencyKey: 'valid-key' }), { ok: false, error: 'permission_denied' });
  assert.deepStrictEqual(await service.removeOperation({ operationLineId: 'op', reason: '', sourceEvidence: {}, idempotencyKey: 'short' }), { ok: false, error: 'invalid_input' });
  assert.strictEqual(called, false);
});

test('undo calls receipt RPC and authoritative refresh failure is fail closed', async () => {
  let rpcName = '';
  const service = createWorkshopOperationRemovalService({
    client: { rpc: async (_token, name) => { rpcName = name; return { ok: true, body: { ok: true, code: 'operation_removal_undone' } }; } },
    getAccessToken: () => 'token', getRole: () => 'administrator', refresh: async () => { throw new Error('offline'); },
  });
  const result = await service.undoRemoval({ receiptId: 'receipt-1', reason: 'Made in error' });
  assert.strictEqual(rpcName, 'undo_pdc_workshop_operation_removal_235');
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.error, 'authoritative_refresh_failed');
});

(async () => {
  let passed = 0;
  for (const item of tests) {
    try { await item.fn(); passed += 1; console.log(`PASS ${item.name}`); }
    catch (error) { console.error(`FAIL ${item.name}`); console.error(error); process.exitCode = 1; }
  }
  console.log(`${passed}/${tests.length} workshop runtime integration tests passed`);
})();
