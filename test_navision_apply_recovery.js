'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
function slice(name) {
  const start = source.indexOf(name);
  const end = source.slice(start + 1).search(/\n(?:async )?function /);
  return source.slice(start, start + end + 1);
}
function runtime(outcomes, onWait) {
  const calls = [], waits = [], alerts = [];
  const pending = { rows: [{ stock: '13000000' }], previewResult: { data: {} },
    previewData: { counts: { changed: 1 }, source_hash: 'exact-source' },
    metadata: { dealerCode: '37047' }, dealerCode: '37047', browserLocalSha256: 'original', parsed: { vehicles: [] } };
  let current = true, confirmations = 0, renders = 0;
  const context = {
    app: { pendingSharedNavisionImport: pending },
    window: { alert: message => alerts.push(message), confirm: () => { confirmations++; return true; } },
    navisionSharedPreviewBlockingState: () => ({ blocking: false }),
    navisionSharedBackendService: () => ({ apply: async (...args) => {
      calls.push(args); const result = outcomes.shift(); if (result instanceof Error) throw result; return result;
    } }),
    navisionSharedPendingStillCurrent: () => current,
    navisionBrowserAuthoritySha256: () => 'original', sha256Hex: () => 'hash',
    updateNavisionImportButton() {}, updateNavisionControlStats() {}, loadSharedNavisionVisibleRows() {},
    renderSharedNavisionPreview: () => { renders++; },
    navisionSafetyIssueMessage: reason => `Safety: ${reason}.`,
    navisionPreviewItemLabel: () => 'Row 1', navisionPreviewIssueMessage: reason => reason,
    setTimeout: (done, ms) => { waits.push(ms); onWait?.(() => { current = false; }); done(); },
  };
  vm.createContext(context);
  vm.runInContext(slice('function sharedNavisionApplyErrorMessage(') + '\n' + slice('async function applySharedNavisionImportPending('), context);
  return { calls, waits, alerts, context, pending, run: () => context.applySharedNavisionImportPending(pending, 'same-user'),
    counts: () => ({ confirmations, renders }) };
}

test('Navision retries explicit rolled-back lock failures using the identical approved preview/key', async () => {
  const r = runtime([{ ok: false, code: '55P03' }, { ok: false, code: '40P01' }, { ok: true }]);
  await r.run();
  assert.equal(r.calls.length, 3);
  assert.deepEqual(r.waits, [1000, 2000]);
  for (const call of r.calls) {
    assert.equal(call[0], r.pending.rows); assert.equal(call[1], r.pending.previewResult);
    assert.equal(call[2], r.calls[0][2]); assert.equal(call[2].idempotencyKey, 'normal-upload:37047:exact-source');
  }
  assert.deepEqual(r.counts(), { confirmations: 1, renders: 1 });
  assert.equal(r.context.app.pendingSharedNavisionImport, null);
});

test('Navision stops after two retries and keeps the preview on continued contention', async () => {
  const r = runtime(Array.from({ length: 3 }, () => ({ ok: false, code: '40001' })));
  await r.run();
  assert.equal(r.calls.length, 3); assert.equal(r.context.app.pendingSharedNavisionImport, r.pending);
  assert.match(r.alerts[0], /workshop was updating/);
});

test('Navision does not retry stale, unsafe, timed-out or unconfirmed requests', async () => {
  for (const code of ['stale_revision', 'preview_changed', 'navision_preflight_blocked', '57014', '23514', 'unauthorized']) {
    const r = runtime([{ ok: false, code }]); await r.run();
    assert.equal(r.calls.length, 1, code); assert.equal(r.context.app.pendingSharedNavisionImport, r.pending, code);
  }
  const r = runtime([new Error('lost connection')]); await r.run();
  assert.equal(r.calls.length, 1); assert.match(r.alerts[0], /result could be confirmed/);
  assert.doesNotMatch(r.alerts[0], /Nothing was imported/);
  assert.equal(r.context.app.pendingSharedNavisionImport, r.pending);
});

test('Navision stops before retry if the importer or preview changes', async () => {
  const r = runtime([{ ok: false, code: '55P03' }], cancel => cancel()); await r.run();
  assert.equal(r.calls.length, 1); assert.equal(r.context.app.pendingSharedNavisionImport, r.pending);
  assert.deepEqual(r.counts(), { confirmations: 1, renders: 0 });
});

test('Navision reports safe diagnostic codes and safety blockers without hiding them', () => {
  const r = runtime([]), message = r.context.sharedNavisionApplyErrorMessage;
  assert.match(message({ code: '57014' }), /took too long/);
  assert.match(message({ code: 'unknown_import_failure' }), /Reference: unknown_import_failure/);
  assert.match(message({ code: 'suspicious_import_blocked', data: { data: { safety: { reason: 'wrong_dealer' } } } }), /wrong_dealer/);
  assert.doesNotMatch(message({ code: '<script>alert(1)</script>' }), /<script>/);
});
