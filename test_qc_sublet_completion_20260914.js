'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = process.env.PDC_QC_TEST_ROOT || process.cwd();
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const phoneSource = fs.readFileSync(path.join(root, 'pdc-qc-mobile.js'), 'utf8');
const { mapServerVehicle } = require(path.join(root, 'pdc-email-vehicle-location-service.js'));

function sourceFunction(name) {
  const start = appSource.search(new RegExp(`(?:async )?function ${name}\\(`));
  assert.ok(start >= 0, `${name} exists`);
  const next = appSource.slice(start + 1).search(/\n(?:async )?function /);
  assert.ok(next >= 0, `${name} has a following function`);
  return appSource.slice(start, start + next + 1);
}
function fixture(stages = [['FITTING', 1], ['SUBLET', null]]) {
  return mapServerVehicle({
    id: '00000000-0000-4000-8000-000000000100', stock_number: 'QC-SUBLET-TEST',
    permanent_vehicle_id: 'QC-SUBLET-TEST', current_location: 'QC', lifecycle_state: 'active',
    visible_on_board: true, version: 1, customer_name: 'Regression fixture',
    vehicle_description: 'Synthetic test vehicle',
    qc_operation_lines: stages.map(([stage, hours], i) => {
      const id = `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`;
      return { line_identity: `source:${id}`, source_line_id: id, source_kind: 'authenticated',
        operation_no: String(i + 1), description: `Synthetic ${stage} ${i + 1}`,
        job_card_number: 'TEST-JC', estimated_hours: hours, stage_code: stage,
        active: true, completed: false, line_version: 0 };
    }),
  });
}
function harness(row = fixture()) {
  let signoffs = 0;
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ctx = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' },
      PDC_AUTH_CONTEXT: { userId: 'synthetic-operator', role: 'operator' },
      matchMedia: () => ({ matches: true, addEventListener() {} }),
      addEventListener() {}, location: { hash: '#/qc' }, scrollTo() {}, setTimeout,
      history: { pushState() {}, replaceState() {} } },
    document: { documentElement: { classList: { remove() {}, toggle() {} } }, querySelector: () => null },
    navigator: { onLine: true }, sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    escapeHtml, groupBy: (items, key) => items.reduce((groups, item) => {
      (groups[key(item)] ||= []).push(item); return groups;
    }, {}),
    app: { currentView: 'dashboard', emailVehicleLocationService: {} },
    qcPageVehicles: () => [row], qcPageVehicleKey: () => 'fixture',
    displayStockNumber: v => v.stock, displayVehicle: v => v.vehicle,
    vehicleCustomerName: v => v.client, vehicleKeyNumber: () => '', pmbStageLabel: stage => stage,
    qcPageOperationPending: new Map(), qcPagePhotoUploadInFlight: new Set(),
    qcPageRejectInFlight: new Set(), qcPageSignoffInFlight: new Set(),
    qcPhotoEvidence: new Map(), qcPageFeedback: new Map(), qcPageNotice: '',
    qcPageOperationMutationChain: Promise.resolve(), qcSelectedVehicleKey: 'fixture',
    capturePdcWriteAuthority: () => ({ actor: 'synthetic-operator' }), pdcWriteAuthorityCurrent: () => true,
    renderQualityControlPage() {}, showView() {},
    qcPageSignoff: async () => { signoffs++; return true; },
    refreshEmailVehicleLocations: async () => true, qcPageAwaitOperationSnapshot: async () => true,
    crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000999' },
    Map, Set, Promise, setTimeout, clearTimeout,
  };
  vm.createContext(ctx);
  ['qcPagePendingKey', 'qcPageOperationLineIsDeferredPit', 'qcPageOperationLines',
    'qcPageAllOperationLinesComplete', 'qcPageOperationHoursLabel', 'qcPageStageLabel',
    'qcPageWorkItemsHtml', 'qcPagePhotoDisabledReason', 'qcPhotoEvidenceIsValid',
    'qcPageReceiptLineApply', 'qcPageSetOperationState'].forEach(name => vm.runInContext(sourceFunction(name), ctx));
  const exposed = phoneSource.replace(/  updateMode\(\);\r?\n\}\)\(\);\s*$/,
    '  globalThis.phone = { checklist, detail, inspected, signoff, rejectionPanel, openRejection };\n  updateMode();\n})();');
  assert.notEqual(exposed, phoneSource, 'expose actual mobile closure without replacing its behavior');
  vm.runInContext(exposed, ctx);
  return { ctx, row, signoffs: () => signoffs };
}
function checkbox(html, identity) {
  const inputs = html.match(/<input\b[^>]*>/g) || [];
  return inputs.find(tag => tag.includes('data-qc-operation-check=') && tag.includes(`data-qc-line-identity="${identity}"`));
}
function validPhoto() {
  return { status: 'accepted', photoReceiptId: '00000000-0000-4000-8000-000000000888',
    bucket_id: 'pdc-qc-evidence-staging', storage_path: 'synthetic/fixture.jpg',
    content_type: 'image/jpeg', byteLength: 100, originalByteLength: 100,
    imageWidth: 10, imageHeight: 10, sha256: 'a'.repeat(64) };
}

test('real mobile and desktop checklists allow Sublet with no hours and retain workshop review gates', () => {
  const h = harness(fixture([['SUBLET', null], ['SUBLET', ''], ['FITTING', null], ['UNALLOCATED_MAPPING_REVIEW', 1], ['FITTING', 0]]));
  const lines = h.row.pdcQcOperationLines;
  assert.equal(lines[0].estimatedHours, null, 'the server projection does not synthesize hours');
  for (const html of [h.ctx.phone.checklist(h.row), h.ctx.qcPageWorkItemsHtml(h.row)]) {
    for (const i of [0, 1, 4]) assert.doesNotMatch(checkbox(html, lines[i].lineIdentity), /\bdisabled\b/);
    for (const i of [2, 3]) assert.match(checkbox(html, lines[i].lineIdentity), /\bdisabled\b/);
  }
  assert.equal(h.ctx.qcPageOperationHoursLabel(lines[0]), 'Hours not required');
  assert.match(h.ctx.qcPageWorkItemsHtml(h.row), /Sublet · Hours not required/);
});

test('Sublet remains locked for viewers, pending saves, photos, rejection and sign-off', () => {
  const h = harness(fixture([['SUBLET', null]])), line = h.row.pdcQcOperationLines[0];
  const disabled = () => assert.match(checkbox(h.ctx.phone.checklist(h.row), line.lineIdentity), /\bdisabled\b/);
  h.ctx.window.PDC_AUTH_CONTEXT.role = 'viewer'; disabled();
  h.ctx.window.PDC_AUTH_CONTEXT.role = 'operator';
  h.ctx.qcPageOperationPending.set(h.ctx.qcPagePendingKey('fixture', line.lineIdentity), {}); disabled();
  h.ctx.qcPageOperationPending.clear();
  for (const set of [h.ctx.qcPagePhotoUploadInFlight, h.ctx.qcPageRejectInFlight, h.ctx.qcPageSignoffInFlight]) {
    set.add('fixture'); disabled(); set.clear();
  }
  h.ctx.phone.openRejection('fixture', line.lineIdentity); disabled();
  assert.match(h.ctx.phone.rejectionPanel('fixture'), /Hours not required/);
  assert.doesNotMatch(h.ctx.phone.rejectionPanel('fixture'), /Hours need review/);
});

test('mixed workshop and Sublet checklist requires every check and a valid photo before mobile sign-off', async () => {
  const h = harness();
  h.row.pdcQcOperationLines[0].completed = true;
  h.ctx.qcPhotoEvidence.set('fixture', validPhoto());
  assert.equal(h.ctx.phone.inspected(h.row), false);
  assert.equal(await h.ctx.phone.signoff('fixture'), false);
  h.row.pdcQcOperationLines[1].completed = true;
  assert.equal(h.ctx.phone.inspected(h.row), true, 'Sublet no-hours status must not block an inspected vehicle');
  h.ctx.qcPhotoEvidence.clear();
  assert.equal(await h.ctx.phone.signoff('fixture'), false, 'photo remains required');
  h.ctx.qcPhotoEvidence.set('fixture', validPhoto());
  const finish = h.ctx.phone.detail(h.row).match(/<button\b[^>]*data-qc-signoff="fixture"[^>]*>/)[0];
  assert.doesNotMatch(finish, /\bdisabled\b/);
  assert.equal(await h.ctx.phone.signoff('fixture'), true);
  assert.equal(h.signoffs(), 1, 'delegates once to existing authoritative finalization');
});

test('unknown workshop hours and unmapped lines still block mobile finalization even if marked complete', async () => {
  for (const [stage, hours] of [['FITTING', null], ['FITTING', 'invalid'], ['UNALLOCATED_MAPPING_REVIEW', 1]]) {
    const h = harness(fixture([[stage, hours], ['SUBLET', null]]));
    h.row.pdcQcOperationLines.forEach(line => { line.completed = true; });
    h.ctx.qcPhotoEvidence.set('fixture', validPhoto());
    assert.equal(h.ctx.phone.inspected(h.row), false);
    assert.equal(await h.ctx.phone.signoff('fixture'), false);
    assert.equal(h.signoffs(), 0);
  }
});

test('fresh retest photo gating still requires its complete 17-line checklist including Sublet', () => {
  const h = harness(fixture(Array.from({ length: 17 }, (_, i) => i === 16 ? ['SUBLET', null] : ['FITTING', 1])));
  h.row.pdcQcRetestCycleId = 'synthetic-cycle'; h.row.pdcQcRetestFreshCycleOpen = true;
  h.row.pdcQcOperationLines.slice(0, -1).forEach(line => { line.completed = true; });
  assert.match(h.ctx.qcPagePhotoDisabledReason(h.row, 'fixture'), /Complete all 17/);
  h.row.pdcQcOperationLines[16].completed = true;
  assert.equal(h.ctx.qcPagePhotoDisabledReason(h.row, 'fixture'), '');
  assert.equal(h.ctx.phone.inspected(h.row), true);
  h.row.pdcQcRetestFreshCycleOpen = false;
  assert.match(h.ctx.qcPagePhotoDisabledReason(h.row, 'fixture'), /cycle is closed/);
});

test('Sublet check and uncheck use validated server receipts and preserve null hours', async () => {
  const h = harness(fixture([['SUBLET', null]])), line = h.row.pdcQcOperationLines[0], calls = [];
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async (...args) => {
    calls.push(args);
    return { ok: true, data: { vehicle_version_after: args[1] + 1,
      line: { line_identity: args[2], version: args[3] + 1, completed: args[4], completed_by: 'synthetic-operator' } } };
  };
  assert.equal(await h.ctx.qcPageSetOperationState('fixture', line.lineIdentity, true), true);
  assert.equal(line.completed, true);
  assert.equal(await h.ctx.qcPageSetOperationState('fixture', line.lineIdentity, false), true);
  assert.equal(line.completed, false);
  assert.equal(line.estimatedHours, null);
  assert.equal(calls[1][1], calls[0][1] + 1, 'next write uses receipt vehicle version');
  assert.equal(calls[1][3], calls[0][3] + 1, 'next write uses receipt operation version');
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async () => ({ ok: false, code: 'version_conflict' });
  assert.equal(await h.ctx.qcPageSetOperationState('fixture', line.lineIdentity, true), false);
  assert.equal(line.completed, false, 'failed writes never fabricate a checked item');
});
