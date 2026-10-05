'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { createNavisionBackendService, NAVISION_STAGING_PROJECT_REF } = require('./navision-backend-service.js');

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function node(value = '') {
  return { value, disabled: false, innerHTML: '', textContent: '', attrs: {},
    classList: { toggle() {} }, setAttribute(key, val) { this.attrs[key] = val; } };
}
function runtime(outcome, count = 2) {
  const f = createFixture({ vehicleCount: 0 }), c = f.context;
  f.loadHelper('navision-vin.js');
  const raw = 'Order\tBatch\tCOSI\tDealer\tSalesperson\tModel Description\tETA At Kewdale Yard\tSub Location Description\n'
    + Array.from({ length: count }, (_, i) => `${String(i + 1).padStart(6, '0')}\t${13000000 + i}\tYes\t014450\tEXAMPLE\tFictional Hilux\t15/11/2026\tProduction Planned`).join('\n');
  const controls = Object.fromEntries(['navision-upload', 'import-navision', 'apply-navision-shared', 'navision-clear', 'navision-status-list', 'navision-preview-status'].map(id => ['#' + id, node()]));
  controls['#navision-paste'] = node(raw);
  controls['#navision-dealer-code'] = node('pilbara');
  c.document.querySelector = selector => controls[selector] || null;
  c.document.querySelectorAll = () => [];
  c.PDC_AUTH_CONTEXT = { userId: 'fixture-account', email: 'example@example.invalid', role: 'importer' };
  c.navisionSharedImportRoleAllowed = () => ['importer', 'administrator'].includes(c.PDC_AUTH_CONTEXT?.role);
  c.navisionWaitForBusyPaint = async () => {};
  c.navisionBrowserAuthoritySha256 = () => 'unchanged-operational-authority';
  c.updateNavisionControlStats = () => {};
  c.enrichSharedNavisionPreviewChanges = async () => {};
  const alerts = [], calls = [], rendered = [];
  c.alert = text => alerts.push(text);
  c.confirm = () => { throw new Error('No approval or Apply confirmation is expected in Preview'); };
  c.renderSharedNavisionPreview = pending => rendered.push(pending);
  c.app.navisionFileName = 'fictional-1168-row-export.tsv';
  const oldPending = { dealerCode: 'pilbara', sourceTextSha256: c.sha256Hex(raw.trim()), previewData: { old: true } };
  c.app.pendingSharedNavisionImport = oldPending;
  const service = createNavisionBackendService({
    projectRef: NAVISION_STAGING_PROJECT_REF, getAccessToken: () => 'inert-local-fixture',
    client: { rpc: async (_token, name, params) => {
      calls.push({ name, params });
      if (outcome instanceof Error) throw outcome;
      if (typeof outcome === 'function') return await outcome();
      return outcome;
    } },
  });
  c.navisionSharedBackendService = () => service;
  return { c, controls, raw, oldPending, alerts, calls, rendered, run: () => c.importNavisionVehicles() };
}
const failure = code => ({ ok: false, status: 500, body: { code, message: 'Server detail is not user-facing' } });
const success = () => ({ ok: true, status: 200, body: { ok: true, source_hash: 'exact-source', preview_hash: 'exact-preview', base_revision: 9,
  counts: { total: 2, invalid: 0, conflict: 0 }, blocking: false, dealer_groups: [] } });
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };

test('1,168-row Pilbara Preview explains 57014, retains every input and disables Apply', async () => {
  const r = runtime(failure('57014'), 1168);
  await r.run();
  assert.equal(r.calls.length, 1);
  assert.equal(r.calls[0].name, 'preview_navision_upload_profile');
  const payload = r.calls[0].params;
  assert.deepEqual(Object.keys(payload).sort(), ['p_profile', 'p_rows', 'p_source_name', 'p_source_timestamp']);
  assert.equal(payload.p_profile, 'pilbara');
  assert.equal(payload.p_rows.length, 1168);
  assert.equal(payload.p_rows[0].order, '000001');
  assert.ok(payload.p_rows.every(row => row.dealer_code === '014450' && row.navisionRawEvidence.columns.length === 8));
  assert.equal(payload.p_source_name, 'fictional-1168-row-export.tsv');
  assert.equal(payload.p_source_timestamp, null);
  assert.equal(r.controls['#navision-paste'].value, r.raw);
  assert.equal(r.controls['#navision-dealer-code'].value, 'pilbara');
  assert.equal(r.c.app.navisionFileName, payload.p_source_name);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  assert.equal(r.controls['#import-navision'].disabled, false);
  assert.equal(r.c.app.navisionPreviewInFlight, false);
  assert.equal(r.controls['#navision-paste'].disabled, false);
  assert.equal(r.controls['#navision-preview-status'].textContent, '');
  assert.match(r.alerts[0], /took too long/);
  assert.match(r.alerts[0], /pasted data is still here/);
  assert.doesNotMatch(r.alerts[0], /try Apply|Server detail/);
  assert.match(r.controls['#navision-status-list'].innerHTML, /role="alert"/);
  assert.equal(r.rendered.length, 0);
});

test('rejected connection is handled, cannot retain an older Apply preview and never retries', async () => {
  const r = runtime(new TypeError('Failed to fetch'));
  await assert.doesNotReject(r.run());
  assert.equal(r.calls.length, 1);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  assert.equal(r.controls['#navision-paste'].value, r.raw);
  assert.equal(r.controls['#navision-dealer-code'].value, 'pilbara');
  assert.match(r.alerts[0], /connection ended/);
  assert.doesNotMatch(r.alerts[0], /Failed to fetch|took too long|try Apply/);
  assert.equal(r.c.app.navisionPreviewInFlight, false);
});

test('unavailable service cannot leave an older Apply preview enabled', async () => {
  const r = runtime(success()); r.c.navisionSharedBackendService = () => null;
  await r.run();
  assert.equal(r.calls.length, 0);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  assert.equal(r.controls['#navision-paste'].value, r.raw);
  assert.equal(r.controls['#navision-dealer-code'].value, 'pilbara');
  assert.match(r.alerts[0], /service is unavailable/);
  assert.equal(r.c.app.navisionPreviewInFlight, false);
});

test('pending Apply is removed during the request and double-click cannot dispatch another Preview', async () => {
  const d = deferred(), r = runtime(() => d.promise);
  const first = r.run(); await flush();
  assert.equal(r.calls.length, 1);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  await r.run(); assert.equal(r.calls.length, 1);
  d.resolve(failure('57014')); await first;
  assert.equal(r.calls.length, 1);
});

for (const [label, change] of [
  ['account replacement', r => { r.c.PDC_AUTH_CONTEXT.userId = 'replacement-account'; }],
  ['loss of role', r => { r.c.PDC_AUTH_CONTEXT.role = 'viewer'; }],
  ['selected profile replacement', r => { r.controls['#navision-dealer-code'].value = 'broome'; }],
  ['pasted source replacement', r => { r.controls['#navision-paste'].value = 'replacement source'; }],
]) {
  for (const mode of ['server failure', 'connection failure', 'success']) {
    test(`${label} discards delayed ${mode} without clearing another request or showing old feedback`, async () => {
      const d = deferred(), r = runtime(() => d.promise), first = r.run(); await flush();
      change(r);
      const replacement = { dealerCode: r.controls['#navision-dealer-code'].value,
        sourceTextSha256: r.c.sha256Hex(r.controls['#navision-paste'].value.trim()), marker: 'replacement' };
      r.c.app.pendingSharedNavisionImport = replacement;
      if (mode === 'connection failure') d.reject(new TypeError('Failed to fetch'));
      else d.resolve(mode === 'server failure' ? failure('57014') : success());
      await first;
      assert.equal(r.c.app.pendingSharedNavisionImport, replacement);
      assert.equal(r.alerts.length, 0);
      assert.equal(r.controls['#navision-status-list'].innerHTML, '');
      assert.equal(r.rendered.length, 0);
      assert.equal(r.c.app.navisionPreviewInFlight, false);
      assert.equal(r.calls.length, 1);
    });
  }
}

test('successful Preview still adopts exact hashes/revision and never approves or applies', async () => {
  const r = runtime(success()); await r.run();
  const pending = r.c.app.pendingSharedNavisionImport;
  assert.equal(pending.rows, r.calls[0].params.p_rows);
  assert.equal(pending.previewData.source_hash, 'exact-source');
  assert.equal(pending.previewData.preview_hash, 'exact-preview');
  assert.equal(pending.previewData.base_revision, 9);
  assert.equal(pending.dealerCode, 'pilbara');
  assert.equal(pending.sourceTextSha256, r.c.sha256Hex(r.raw.trim()));
  assert.equal(r.calls.length, 1);
  assert.equal(r.controls['#apply-navision-shared'].disabled, false);
  assert.equal(r.alerts.length, 0);
});

test('errors show bounded guidance rather than arbitrary server messages or markup', async () => {
  const r = runtime({ ok: false, status: 500, body: { code: '<script>bad()</script>', message: 'Private SQL detail', details: 'Private rows' } });
  await r.run();
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.doesNotMatch(r.controls['#navision-status-list'].innerHTML, /<script>|Private SQL|Private rows/);
  assert.match(r.alerts[0], /could not be checked/);
  assert.match(r.c.sharedNavisionPreviewErrorMessage({ code: '42501' }), /import access/);
  assert.match(r.c.sharedNavisionPreviewErrorMessage({ code: 'unknown_preview_error' }), /Reference: unknown_preview_error/);
});

test('failed local parsing leaves the source intact and does not dispatch or leave Apply enabled', async () => {
  const r = runtime(success()); r.c.parseNavisionInput = () => { throw new Error('Fictional parser interruption'); };
  await assert.doesNotReject(r.run());
  assert.equal(r.calls.length, 0);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  assert.equal(r.controls['#navision-paste'].value, r.raw);
  assert.match(r.alerts[0], /could not be checked/);
  assert.doesNotMatch(r.alerts[0], /connection ended|Fictional parser/);
  assert.equal(r.c.app.navisionPreviewInFlight, false);
});
