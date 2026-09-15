'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = process.env.PDC_QC_TEST_ROOT || process.cwd();
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const phoneSource = fs.readFileSync(path.join(root, 'pdc-qc-mobile.js'), 'utf8');
const { mapServerVehicle, reconcileVehicleRows } = require(path.join(root, 'pdc-email-vehicle-location-service.js'));

function sourceFunction(name) {
  const start = appSource.search(new RegExp(`(?:async )?function ${name}\\(`));
  assert.ok(start >= 0, `${name} exists`);
  const next = appSource.slice(start + 1).search(/\n(?:async )?function /);
  assert.ok(next >= 0, `${name} has a following function`);
  return appSource.slice(start, start + next + 1);
}
function snapshot(patch = {}) {
  const stages = [['FITTING', 'fitting', 1.5], ['SUBLET', 'sublet', null]];
  return {
    id: '00000000-0000-4000-8000-000000000100', permanent_vehicle_id: 'STATUS99-QC-FIXTURE',
    stock_number: 'STATUS99-QC-FIXTURE', job_card_number: 'STATUS99-JC', version: 8,
    current_location: 'QC', lifecycle_state: 'active', visible_on_board: true,
    customer_name: 'Synthetic test customer', vehicle_description: 'Synthetic test vehicle',
    qc_completed_at: null, qc_completed_by: null, rft_transferred_at: null,
    tune_checkout: { confirmed: true, source: 'Tune Sub Status 99',
      receipt_id: '00000000-0000-4000-8000-000000000999',
      job_cards: [{ ro: 'STATUS99-JC', sub_status: '99' }] },
    operation_lines: stages.map(([stage, work, hours], i) => ({
      operation_line_id: `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
      operation_no: `OP${i + 1}`, work_key: work, description: `Retained ${stage} operation`,
      job_card_number: 'STATUS99-JC', estimated_hours: hours,
      source_uid: `pilbara_service_open_jobcards_v1:STATUS99-JC:${i + 1}`,
    })),
    qc_operation_lines: stages.map(([stage, work, hours], i) => {
      const id = `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`;
      return { line_identity: `source:${id}`, source_line_id: id, source_kind: 'authenticated',
        operation_no: `OP${i + 1}`, description: `Retained ${stage} operation`,
        job_card_number: 'STATUS99-JC', estimated_hours: hours, stage_code: stage,
        active: true, completed: false, line_version: 0 };
    }),
    ...patch,
  };
}
function harness(raw = snapshot()) {
  const row = mapServerVehicle(raw), rows = [row];
  let signoffs = 0;
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ctx = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' },
      PDC_AUTH_CONTEXT: { userId: 'synthetic-operator', role: 'operator' },
      matchMedia: () => ({ matches: true, addEventListener() {} }), addEventListener() {},
      location: { hash: '#/qc' }, scrollTo() {}, setTimeout,
      history: { pushState() {}, replaceState() {} } },
    document: { documentElement: { classList: { remove() {}, toggle() {} } }, querySelector: () => null },
    navigator: { onLine: true }, sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    escapeHtml, groupBy: (items, key) => items.reduce((groups, item) => {
      (groups[key(item)] ||= []).push(item); return groups;
    }, {}),
    app: { currentView: 'dashboard', emailVehicleLocationService: {} },
    pdcSheetVehicles: () => rows,
    displayStockNumber: v => v.stock, displayVehicle: v => v.vehicle,
    vehicleCustomerName: v => v.client, vehicleKeyNumber: () => '', pmbStageLabel: stage => stage,
    qcPageOperationPending: new Map(), qcPagePhotoUploadInFlight: new Set(),
    qcPageRejectInFlight: new Set(), qcPageSignoffInFlight: new Set(),
    qcPhotoEvidence: new Map(), qcPageFeedback: new Map(), qcPageNotice: '',
    qcPageOperationMutationChain: Promise.resolve(), qcSelectedVehicleKey: row.stock,
    capturePdcWriteAuthority: () => ({ actor: 'synthetic-operator' }), pdcWriteAuthorityCurrent: () => true,
    renderQualityControlPage() {}, showView() {},
    qcPageSignoff: async () => { signoffs++; return true; },
    refreshEmailVehicleLocations: async () => true, qcPageAwaitOperationSnapshot: async () => true,
    crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000888' },
    Map, Set, Promise, setTimeout, clearTimeout,
  };
  vm.createContext(ctx);
  ['normalizePdcLocation', 'vehiclePdcLocation', 'vehicleInQualityControlGate',
    'isBlankStock', 'vehicleKey', 'qcPageVehicleKey', 'qcPageVehicleIsEligible', 'qcPageVehicles',
    'qcPagePendingKey', 'qcPageOperationLineIsDeferredPit', 'qcPageOperationLines',
    'qcPageAllOperationLinesComplete', 'qcPageOperationHoursLabel', 'qcPageStageLabel',
    'qcPageWorkItemsHtml', 'qcPagePhotoDisabledReason', 'qcPhotoEvidenceIsValid',
    'qcPageReceiptLineApply', 'qcPageSetOperationState'].forEach(name => vm.runInContext(sourceFunction(name), ctx));
  const exposed = phoneSource.replace(/  updateMode\(\);\r?\n\}\)\(\);\s*$/,
    '  globalThis.phone = { checklist, detail, inspected, signoff };\n  updateMode();\n})();');
  assert.notEqual(exposed, phoneSource, 'expose the actual mobile presentation closure');
  vm.runInContext(exposed, ctx);
  return { ctx, row, rows, signoffs: () => signoffs };
}
function checkbox(html, identity) {
  return (html.match(/<input\b[^>]*>/g) || []).find(tag => tag.includes('data-qc-operation-check=')
    && tag.includes(`data-qc-line-identity="${identity}"`));
}
function validPhoto() {
  return { status: 'accepted', photoReceiptId: '00000000-0000-4000-8000-000000000777',
    bucket_id: 'pdc-qc-evidence-staging', storage_path: 'synthetic/status99.jpg',
    content_type: 'image/jpeg', byteLength: 100, originalByteLength: 100,
    imageWidth: 10, imageHeight: 10, sha256: 'a'.repeat(64) };
}

test('status99 canonical QC snapshot keeps source jobs and enters the shared phone queue unchecked', () => {
  const h = harness();
  assert.equal(h.row.tuneCheckout.confirmed, true);
  assert.equal(h.row.pdcEmailOperationLines.length, 2, 'checkout retains the authenticated job descriptions');
  assert.equal(h.row.pdcQcComplete, false, 'checkout does not invent an inspection');
  assert.equal(h.ctx.qcPageVehicles().length, 1);
  assert.equal(h.ctx.qcPageVehicles()[0], h.row);
  assert.equal(h.ctx.phone.inspected(h.row), false);
  assert.match(h.ctx.phone.detail(h.row), /0 of 2 checked/);
  for (const line of h.ctx.qcPageOperationLines(h.row)) {
    assert.equal(line.completed, false);
    const tag = checkbox(h.ctx.phone.checklist(h.row), line.lineIdentity);
    assert.ok(tag, `phone shows ${line.description}`);
    assert.doesNotMatch(tag, /\bdisabled\b|\schecked(?:\s|>)/);
  }
});

test('unsigned RFT reproduces the old phone failure; signed-off RFT remains excluded', () => {
  for (const completedAt of [null, '2026-09-15T06:00:00Z']) {
    const h = harness(snapshot({ current_location: 'RFT', lifecycle_state: 'rft', qc_completed_at: completedAt }));
    assert.equal(h.ctx.qcPageVehicles().length, 0, 'never bypass canonical QC location authority');
  }
});

test('repair snapshot replaces stale RFT state and restores phone eligibility without changing identities', () => {
  const stale = mapServerVehicle(snapshot({ current_location: 'RFT', lifecycle_state: 'rft', version: 7,
    qc_operation_lines: [], operation_lines: [] }));
  const h = harness();
  const repaired = reconcileVehicleRows([stale], [snapshot()], { authoritative: true }).rows;
  assert.equal(repaired.length, 1);
  h.rows.splice(0, 1, repaired[0]);
  assert.equal(h.ctx.qcPageVehicles().length, 1);
  assert.equal(repaired[0].__emailVehicleId, stale.__emailVehicleId);
  assert.equal(repaired[0].__emailVehicleVersion, 8);
  assert.equal(repaired[0].pdcEmailOperationLines.length, 2);
  assert.equal(h.ctx.qcPageOperationLines(repaired[0]).length, 2);
});

test('missing, empty and invalid QC projections cannot expose an editable phone vehicle', () => {
  for (const projection of [undefined, [], [{ line_identity: 'untrusted', active: true, description: 'Invalid' }]]) {
    const h = harness(snapshot({ qc_operation_lines: projection }));
    assert.equal(h.row.pdcEmailOperationLines.length, 2, 'source descriptions alone are not completion authority');
    assert.equal(h.ctx.qcPageVehicles().length, 0);
  }
});

test('checkout operations save using the existing receipt and version contract, with no fabricated completion', async () => {
  const h = harness(), key = h.row.stock, line = h.row.pdcQcOperationLines[0], calls = [];
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async (...args) => {
    calls.push(args);
    return { ok: true, data: { vehicle_version_after: args[1] + 1,
      line: { line_identity: args[2], version: args[3] + 1, completed: args[4], completed_by: 'synthetic-operator' } } };
  };
  assert.equal(await h.ctx.qcPageSetOperationState(key, line.lineIdentity, true), true);
  assert.equal(line.completed, true);
  assert.equal(calls[0][0], h.row.__emailVehicleId);
  assert.equal(calls[0][1], 8);
  assert.equal(h.row.__emailVehicleVersion, 9);
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async () => ({ ok: false, code: 'version_conflict' });
  assert.equal(await h.ctx.qcPageSetOperationState(key, line.lineIdentity, false), false);
  assert.equal(line.completed, true, 'a rejected uncheck preserves the last authoritative receipt');
});

test('status99 phone sign-off still requires every inspection item and a valid photo', async () => {
  const h = harness(), key = h.row.stock;
  h.ctx.qcPhotoEvidence.set(key, validPhoto());
  assert.equal(await h.ctx.phone.signoff(key), false);
  h.row.pdcQcOperationLines[0].completed = true;
  assert.equal(await h.ctx.phone.signoff(key), false, 'Sublet must also be inspected');
  h.row.pdcQcOperationLines[1].completed = true;
  h.ctx.qcPhotoEvidence.clear();
  assert.equal(await h.ctx.phone.signoff(key), false, 'Tune checkout is not a photo receipt');
  h.ctx.qcPhotoEvidence.set(key, validPhoto());
  assert.equal(await h.ctx.phone.signoff(key), true);
  assert.equal(h.signoffs(), 1, 'existing protected finalization is called only once inspection and photo are ready');
});

test('unknown workshop hours and viewer access retain the mobile inspection restrictions after checkout', () => {
  const h = harness(), line = h.row.pdcQcOperationLines[0];
  line.estimatedHours = null;
  assert.match(checkbox(h.ctx.phone.checklist(h.row), line.lineIdentity), /\bdisabled\b/);
  line.estimatedHours = 1.5;
  h.ctx.window.PDC_AUTH_CONTEXT.role = 'viewer';
  assert.match(checkbox(h.ctx.phone.checklist(h.row), line.lineIdentity), /\bdisabled\b/);
});

test('retained staff inspection evidence is preserved while remaining checkout items stay unchecked', () => {
  const raw = snapshot();
  raw.qc_operation_lines[0] = { ...raw.qc_operation_lines[0], completed: true,
    completed_by: '00000000-0000-4000-8000-000000000555', completed_at: '2026-09-15T06:15:00Z', line_version: 3 };
  const h = harness(raw), [checked, pending] = h.row.pdcQcOperationLines;
  assert.equal(checked.completed, true);
  assert.equal(checked.completedBy, raw.qc_operation_lines[0].completed_by);
  assert.equal(checked.completedAt, raw.qc_operation_lines[0].completed_at);
  assert.equal(checked.lineVersion, 3);
  assert.equal(pending.completed, false);
  assert.match(h.ctx.phone.detail(h.row), /1 of 2 checked/);
  assert.equal(h.ctx.phone.inspected(h.row), false);
});

test('a checkout vehicle that leaves the canonical QC queue cannot write another phone inspection', async () => {
  const h = harness(), key = h.row.stock, line = h.row.pdcQcOperationLines[0];
  let writes = 0;
  h.ctx.app.emailVehicleLocationService.setQcOperationCompletion = async () => { writes++; return { ok: true }; };
  h.row.pdcLocation = 'RFT';
  h.row.pdcQcComplete = true;
  assert.equal(await h.ctx.qcPageSetOperationState(key, line.lineIdentity, true), false);
  assert.equal(writes, 0);
  assert.equal(line.completed, false);
});

