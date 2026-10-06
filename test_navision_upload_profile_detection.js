'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { createNavisionBackendService, NAVISION_STAGING_PROJECT_REF } = require('./navision-backend-service.js');

const headings = 'Order\tBatch\tCOSI\tDealer\tSwap From Dealer\tModel Description\tNotes';
const source = codes => headings + '\n' + codes.map((code, i) =>
  `${250026000 + i}\t${i % 2 ? '' : 13000000 + i}\tYes\t${code}\t${code === '037047' ? '014450' : '037047'}\tFictional Hilux\tBroome Pilbara 014450 037047`).join('\n');
function node(value = '') {
  return { value, disabled: false, hidden: true, innerHTML: '', textContent: '', attrs: {}, dataset: {},
    classList: { toggle(key, val) { this[key] = val; } }, setAttribute(key, val) { this.attrs[key] = val; } };
}
function runtime(raw = source(['037047']), profile = 'pilbara', outcome) {
  const f = createFixture({ vehicleCount: 0 }), c = f.context;
  f.loadHelper('navision-vin.js');
  const controls = Object.fromEntries(['navision-upload', 'import-navision', 'apply-navision-shared', 'navision-clear',
    'navision-status-list', 'navision-preview-status', 'navision-profile-help', 'navision-profile-detection'].map(id => ['#' + id, node()]));
  controls['#navision-paste'] = node(raw);
  controls['#navision-dealer-code'] = node(profile);
  controls['#navision-upload'].value = 'preserved-file';
  const tabs = ['broome', 'pilbara'].map(profile => ({ ...node(), dataset: { navisionProfile: profile } }));
  c.document.querySelector = selector => controls[selector] || null;
  c.document.querySelectorAll = selector => selector === '[data-navision-profile]' ? tabs : [];
  c.PDC_AUTH_CONTEXT = { userId: 'fixture-account', email: 'example@example.invalid', role: 'importer' };
  c.navisionSharedImportRoleAllowed = () => ['importer', 'administrator'].includes(c.PDC_AUTH_CONTEXT?.role);
  c.navisionWaitForBusyPaint = async () => {};
  c.navisionBrowserAuthoritySha256 = () => 'inert-operational-authority';
  c.updateNavisionControlStats = () => {};
  c.enrichSharedNavisionPreviewChanges = async () => {};
  const calls = [], alerts = [], rendered = [];
  c.alert = text => alerts.push(text);
  c.confirm = () => { throw new Error('Preview must not approve or import a snapshot'); };
  c.renderSharedNavisionPreview = pending => rendered.push(pending);
  c.app.navisionFileName = 'misleading-Pilbara-Broome-filename.tsv';
  c.app.pendingSharedNavisionImport = { dealerCode: profile, old: true };
  const service = createNavisionBackendService({ projectRef: NAVISION_STAGING_PROJECT_REF,
    getAccessToken: () => 'inert-fixture', client: { rpc: async (_token, name, params) => {
      calls.push({ name, params });
      if (outcome) return typeof outcome === 'function' ? await outcome() : outcome;
      return { ok: true, status: 200, body: { ok: true, source_hash: 'exact-source', preview_hash: 'exact-preview',
        base_revision: 17, counts: { total: params.p_rows.length, invalid: 0, conflict: 0 }, blocking: false, dealer_groups: [] } };
    } } });
  c.navisionSharedBackendService = () => service;
  return { c, raw, controls, tabs, calls, alerts, rendered, run: () => c.importNavisionVehicles() };
}

for (const [code, initial, expected] of [['037047', 'pilbara', 'broome'], ['014450', 'broome', 'pilbara']]) {
  test(`${code} export selects ${expected} before its single server preview, retaining stockless COSI orders`, async () => {
    const r = runtime(source(Array(257).fill(code).concat('090000')), initial);
    await r.run();
    assert.equal(r.calls.length, 1);
    assert.equal(r.calls[0].name, 'preview_navision_upload_profile');
    const params = r.calls[0].params;
    assert.equal(params.p_profile, expected);
    assert.equal(params.p_rows.length, 258);
    assert.equal(params.p_rows[1].stock, '');
    assert.equal(params.p_rows[1].order, '250026001');
    assert.equal(params.p_rows[257].dealer_code, '090000');
    assert.ok(params.p_rows.every(row => row.navisionRawEvidence.columns.length === 7));
    assert.equal(r.controls['#navision-paste'].value, r.raw);
    assert.equal(r.controls['#navision-upload'].value, 'preserved-file');
    assert.equal(r.controls['#navision-dealer-code'].value, expected);
    assert.equal(r.tabs.find(tab => tab.dataset.navisionProfile === expected).attrs['aria-selected'], 'true');
    const pending = r.c.app.pendingSharedNavisionImport;
    assert.equal(pending.dealerCode, expected);
    assert.equal(pending.metadata.dealerCode, expected);
    assert.equal(pending.parsed.options.uploadProfile, expected);
    assert.equal(pending.sourceTextSha256, r.c.sha256Hex(r.raw.trim()));
    assert.equal(pending.previewData.base_revision, 17);
    assert.equal(pending.previewData.source_hash, 'exact-source');
    assert.equal(pending.previewData.preview_hash, 'exact-preview');
    assert.equal(pending.clientPreflight.blocking, false);
    assert.match(r.controls['#navision-profile-detection'].textContent, /257 dealer rows/);
    assert.match(r.controls['#navision-profile-detection'].textContent, /1 rows are outside/);
    assert.equal(r.alerts.length, 0);
    assert.equal(r.c.app.navisionPreviewInFlight, false);
    assert.equal(r.controls['#apply-navision-shared'].disabled, false);
  });
}

test('mixed-dealer and head-office-only files retain the explicit profile and exclusions', async () => {
  for (const profile of ['broome', 'pilbara']) {
    const r = runtime(source(['037047', '014450', '001234', '002345', '090000']), profile);
    const assessment = r.c.assessNavisionUploadProfile(r.c.parseNavisionInput(r.raw, { uploadProfile: profile }).vehicles, profile);
    assert.equal(assessment.detectedProfile, '');
    assert.equal(assessment.eligible, 3);
    assert.equal(assessment.excluded, 2);
    assert.equal(assessment.blockedMessage, '');
    await r.run();
    assert.equal(r.calls[0].params.p_profile, profile);
    assert.equal(r.c.app.pendingSharedNavisionImport.clientPreflight.blocking, false);
    const shared = runtime(source(['001234', '002345']), profile);
    await shared.run();
    assert.equal(shared.calls[0].params.p_profile, profile);
  }
});

test('missing, conflicting or unsupported original Dealer values block before RPC and retain the source', async () => {
  for (const [raw, guidance] of [
    [source(['']), /Row 1 needs one unambiguous original Dealer column/],
    ['Order\tBatch\tCOSI\tSwap From Dealer\tModel Description\n250026000\t13000000\tYes\t037047\tFictional Hilux', /original Dealer column/],
    ['Order\tBatch\tCOSI\tDealer\tDealer Code\tModel Description\n250026000\t13000000\tYes\t037047\t014450\tFictional Hilux', /original Dealer column/],
    [source(['090000']), /no vehicles for Broome/],
  ]) {
    const r = runtime(raw);
    await r.run();
    assert.equal(r.calls.length, 0);
    assert.equal(r.c.app.pendingSharedNavisionImport, null);
    assert.equal(r.controls['#apply-navision-shared'].disabled, true);
    assert.equal(r.controls['#navision-paste'].value, raw);
    assert.match(r.alerts[0], guidance);
    assert.match(r.alerts[0], /nothing was imported/i);
    assert.equal(r.c.app.navisionPreviewInFlight, false);
    assert.equal(r.controls['#import-navision'].disabled, false);
  }
});

test('tab changes preserve source and selected file while invalidating all previous preview authority', () => {
  const r = runtime();
  r.c.app.navisionImport = { old: true };
  r.c.app.pendingNavisionImport = { old: true };
  assert.equal(r.c.setNavisionUploadProfile('broome'), true);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.equal(r.c.app.pendingNavisionImport, null);
  assert.equal(r.c.app.navisionImport, null);
  assert.equal(r.controls['#navision-paste'].value, r.raw);
  assert.equal(r.controls['#navision-upload'].value, 'preserved-file');
  assert.match(r.controls['#navision-status-list'].innerHTML, /source data is still here/);
  assert.match(r.controls['#navision-profile-help'].textContent, /037047/);
  assert.equal(r.c.setNavisionUploadProfile('combined'), false);
  const binding = fs.readFileSync('app.js', 'utf8').split("document.querySelectorAll('[data-navision-profile]').forEach(button")[1].split('\n  });')[0];
  assert.match(binding, /setNavisionUploadProfile/);
  assert.doesNotMatch(binding, /clearNavisionImport/);
  assert.match(binding, /navisionPreviewInFlight\|\|app.navisionSharedApplyInFlight/);
});

test('text and Excel file selection share profile detection without applying or dispatching a preview', async () => {
  for (const [name, code, expected] of [['misleading-pilbara.tsv', '037047', 'broome'], ['misleading-broome.xlsx', '014450', 'pilbara']]) {
    const r = runtime('', expected === 'broome' ? 'pilbara' : 'broome'), text = source([code]);
    r.c.readXlsxVehicleSpreadsheet = async () => ({ text, sheetName: 'Synthetic export', headerRowIndex: 0, rows: [{}] });
    await r.c.handleNavisionFileSelect({ target: { files: [{ name, text: async () => text }] } });
    assert.equal(r.controls['#navision-dealer-code'].value, expected);
    assert.equal(r.controls['#navision-paste'].value, text);
    assert.equal(r.calls.length, 0);
    assert.equal(r.c.app.pendingSharedNavisionImport, null);
    assert.equal(r.controls['#apply-navision-shared'].disabled, true);
  }
});

test('automatic profile correction still rejects delayed previews if the source or account changes', async () => {
  for (const change of [r => { r.controls['#navision-paste'].value = 'replacement'; }, r => { r.c.PDC_AUTH_CONTEXT.userId = 'replacement'; }]) {
    let finish;
    const delayed = new Promise(resolve => { finish = resolve; });
    const r = runtime(source(['037047']), 'pilbara', () => delayed), running = r.run();
    await new Promise(setImmediate);
    assert.equal(r.calls.length, 1);
    await r.run();
    assert.equal(r.calls.length, 1);
    change(r);
    finish({ ok: true, status: 200, body: { ok: true, counts: { total: 1 }, blocking: false } });
    await running;
    assert.equal(r.c.app.pendingSharedNavisionImport, null);
    assert.equal(r.rendered.length, 0);
    assert.equal(r.controls['#apply-navision-shared'].disabled, true);
    assert.equal(r.c.app.navisionPreviewInFlight, false);
  }
});

test('22023 errors explain dealer and source issues without exposing private SQL details', async () => {
  const r = runtime(source(['014450']), 'pilbara', { ok: false, status: 400,
    body: { code: '22023', message: 'No eligible rows for the selected upload' } });
  await r.run();
  assert.match(r.alerts[0], /Use Broome Upload for Dealer 037047 or Pilbara Upload for Dealer 014450/);
  assert.equal(r.c.app.pendingSharedNavisionImport, null);
  assert.match(r.c.sharedNavisionPreviewErrorMessage({ code: '22023', data: { message: 'Row 2 without Batch needs a Toyota Order number' } }), /Row 2 without Batch/);
  assert.doesNotMatch(r.c.sharedNavisionPreviewErrorMessage({ code: '22023', data: { message: 'Private SQL <script>secret</script>' } }), /Private SQL|script|secret/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /id="navision-profile-detection"[^>]+aria-live="polite"/);
  assert.match(html, /navision-profile-detection=2026\.10\.07\.01/);
});
