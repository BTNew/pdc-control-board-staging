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

test('planner runtime clears stale highlight and replaces it through navigation helper', () => {
  const source = read('workshop-planner.js');
  assert(source.includes("querySelectorAll('.is-workshop-navigation-pulse')"));
  assert(source.includes('WorkshopNavigation.replaceWorkshopHighlight'));
  assert(source.includes("'(prefers-reduced-motion: reduce)'"));
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
