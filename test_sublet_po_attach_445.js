/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r445 (F58, change request): attach the sublet purchase order PDF to a GP PO (pilot vehicles; controllers / administrators).
// Attach only: no supplier email. Synthetic data only (no stock number, customer or live PO in Git).
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const attach = require('./pdc-sublet-po-attach.js');
const po = require('./pdc-sublet-po.js');
const panels = require('./pdc-operation-panels.js');
const appSource = fs.readFileSync('app.js', 'utf8');
const MIG = 'supabase/migrations/20261021091634_r445_sublet_po_attach.sql';
const DOWN = 'supabase/rollbacks/20261021091634_r445_sublet_po_attach.down.sql';
const V = '11111111-2222-4333-8444-555555555555';
const S = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jc = (n, cat, desc) => ({ line_identity: `source:${S(n)}`, source_line_id: S(n), operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`,
  description: desc, source_kind: 'authenticated', department: '139', active: true, work_category: cat, stage_code: cat, estimated_hours: 0.5 });
function summary(lines) {
  const context = vm.createContext({ app: { vehicleWorkshopDetailCache: new Map([['synthetic', { status: 'ready', detail: { vehicle_version: 2, job_card_lines: lines } }]]) },
    cleanNavisionText: x => String(x ?? '').trim(), vehicleWorkshopDetailCanonicalId: () => 'synthetic', vehicleKey: () => 'synthetic',
    escapeHtml: x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    vehicleWorkshopLineIdentity: (_s, l) => `source:${l.operation_line_id}`, vehicleWorkshopStageCode: s => String(s).toUpperCase() });
  vm.runInContext(appSource.slice(appSource.indexOf('function authenticatedOperationLineValid('), appSource.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return context.authenticatedEmailOperationLinesHtml({});
}
const lines = [jc(1, 'FITTING', 'Sample fuel'), jc(2, 'FITTING', 'Sample pre-delivery'), jc(3, 'TINT', 'Sample tint')];
const doc = (state, extra = {}) => ({ doc_id: S(901), po_number: 'GP19000901', original_filename: 'Sample PO.pdf', byte_length: 52310, sha256: 'a'.repeat(64),
  storage_path: `sublet-po/${S(1)}/${V}/${S(902)}.pdf`, uploaded_by_email: 'controller@example.invalid', uploaded_at: '2026-10-21T09:30:00Z',
  covered_line_keys: ['jc:J139000001:1'], covered_labels: ['PD line 1'], board_lines: state === 'linked' ? [{ line_key: 'jc:J139000001:1', label: 'PD line 1' }] : [], state, history: [], ...extra });
const payload = (docs, can = true) => ({ ok: true, vehicle_id: V, pilot: true, can_attach: can, lines: [], documents: docs });

test('GP PO format: GP + 8 digits, spaces and case forgiven, anything else refused', () => {
  assert.equal(attach.normalisePo(' gp19000901 '), 'GP19000901');
  assert.equal(attach.normalisePo('GP 1900 0901'), 'GP19000901');
  for (const bad of ['GP1900090', 'GP190009011', 'PO19000901', 'GP1900090A', '', null, 'All']) assert.equal(attach.normalisePo(bad), '', String(bad));
});

test('file checks before upload: PDF only (name, type and %PDF- header), not empty, at most 10 MB', () => {
  const pdf = { name: 'po.pdf', type: 'application/pdf', size: 52310 };
  assert.equal(attach.fileProblem(pdf, new Uint8Array([37, 80, 68, 70, 45])), '');
  assert.equal(attach.fileProblem(pdf), '');
  assert.match(attach.fileProblem({ name: 'po.txt', type: 'text/plain', size: 10 }), /Only PDF/);
  assert.match(attach.fileProblem({ name: 'po.pdf', type: 'image/png', size: 10 }), /Only PDF/);
  assert.match(attach.fileProblem({ name: 'po.pdf', type: 'application/pdf', size: 0 }), /empty/);
  assert.match(attach.fileProblem({ name: 'po.pdf', type: 'application/pdf', size: 10 * 1024 * 1024 + 1 }), /limit is 10 MB/);
  assert.match(attach.fileProblem(pdf, new Uint8Array([80, 75, 3, 4, 0])), /not a real PDF/);
  assert.match(attach.fileProblem(null), /Choose/);
  assert.equal(attach.MAX_BYTES, 10485760);
});

test('upload path is the user\'s own folder per vehicle with a fresh uuid name (matches the storage policy)', () => {
  assert.equal(attach.uploadPath(S(1), V, S(2)), `sublet-po/${S(1)}/${V}/${S(2)}.pdf`);
  assert.equal(attach.uploadPath('x', V, S(2)), '');
  assert.equal(attach.uploadPath(S(1), V, '../../x'), '');
});

test('pending PO (attached before the w/Sublet upload): Sublet box created with the document, View, Replace and file details', () => {
  const html = panels.arrange(attach.decorate(po.decorateOperations(summary(lines), { known: true }), { vehicleId: V, payload: payload([doc('pending')]) }));
  const box = html.slice(html.indexOf('data-operation-panel="sublet"'));
  assert.ok(html.includes('data-operation-panel="sublet"'), 'Sublet box shown for a pending PO');
  assert.match(box, /<small>1 sublet<\/small>/);
  assert.match(box, /GP19000901/);
  assert.match(box, /Pending: PO not on the w\/Sublet upload yet/);
  assert.match(box, /Sample PO\.pdf · 51 KB · uploaded by controller@example\.invalid 21\/10\/2026, 17:30 AWST · covers PD line 1/);
  assert.match(box, /data-pdc-po-view="00000000-0000-4000-8000-000000000901"/);
  assert.match(box, /data-pdc-po-replace="00000000-0000-4000-8000-000000000901"/);
  assert.match(box, /data-pdc-po-attach="11111111-2222-4333-8444-555555555555"/);
  assert.equal((html.match(/data-operation-panel="sublet"/g) || []).length, 1);
  assert.equal(attach.decorate(attach.decorate(summary(lines), { vehicleId: V, payload: payload([doc('pending')]) }), { vehicleId: V, payload: payload([doc('pending')]) }),
    attach.decorate(summary(lines), { vehicleId: V, payload: payload([doc('pending')]) }), 'idempotent');
});

test('linked PO (the upload brought it): the board sublet rows for that PO get a PDF button; ticks and categories unchanged', () => {
  const linesPayload = { ok: true, can_tick: true, vehicle_id: V, lines: [{ line_key: 'jc:J139000001:1', line_identity: `source:${S(1)}`, operation_no: 'PD001-ABCDEF01', line_no: 1,
    po_numbers: ['GP19000901'], po_details: [{ po_number: 'GP19000901', description: 'Sample sublet' }], ticked: false, version: 0, tickable: true }] };
  const before = po.decorateOperations(summary(lines), { vehicleId: V, payload: linesPayload });
  const after = attach.decorate(before, { vehicleId: V, payload: payload([doc('linked')]) });
  const box = after.slice(after.indexOf('data-operation-station="SUBLET"'));
  assert.match(box, /<span class="pdc-sublet-po-chip">GP19000901<\/span><button class="pdc-po-chip-pdf" type="button" data-pdc-po-view="00000000-0000-4000-8000-000000000901"/);
  assert.match(box, /On PD line 1/);
  assert.equal((after.match(/class="pdc-sublet-po-tick"/g) || []).length, (before.match(/class="pdc-sublet-po-tick"/g) || []).length);
  assert.equal((after.match(/<li data-operation-source-id=/g) || []).length, (before.match(/<li data-operation-source-id=/g) || []).length);
  const strip = h => h.replace(/<div class="pdc-sublet-po-docs"[\s\S]*?<\/div><\/div><\/div>|<div class="pdc-sublet-po-docs"[\s\S]*$/, '').replace(/<button class="pdc-po-chip-pdf"[^>]*>PDF<\/button>/g, '');
  assert.equal(strip(after).slice(0, strip(after).indexOf('data-operation-station="SUBLET"')), before.slice(0, before.indexOf('data-operation-station="SUBLET"')), 'operation lines outside the Sublet box untouched');
});

test('not a pilot vehicle / not a controller: nothing changes; read-only viewer gets View but no Attach or Replace', () => {
  const base = summary(lines);
  assert.equal(attach.decorate(base, { vehicleId: V, payload: { ok: false, code: 'sublet_po_attach_not_in_pilot' } }), base);
  assert.equal(attach.decorate(base, { vehicleId: V, payload: null }), base);
  assert.equal(attach.decorate(base, { vehicleId: V, payload: payload([], false) }), base);
  const ro = attach.decorate(base, { vehicleId: V, payload: payload([doc('pending')], false) });
  assert.match(ro, /data-pdc-po-view=/);
  assert.doesNotMatch(ro, /data-pdc-po-replace=|data-pdc-po-attach=/);
  const empty = attach.decorate(base, { vehicleId: V, payload: payload([]) });
  assert.match(empty, /No sublet PO attached yet/);
  assert.match(attach.decorate(base, { vehicleId: V, payload: payload([doc('pending', { history: [{ doc_id: S(900) }] })]) }), /1 earlier version kept/);
});

test('text is escaped (file names and emails come from users)', () => {
  const html = attach.decorate(summary(lines), { vehicleId: V, payload: payload([doc('pending', { original_filename: '<img src=x onerror=alert(1)>.pdf', uploaded_by_email: '"x"@y' })]) });
  assert.doesNotMatch(html, /<img src=x/);
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;\.pdf/);
});

test('loader: canonical-entry loads the attach module after pdc-sublet-po.js and before pdc-operation-panels.js; panels still load if it fails', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /subletPoAttach\.src = 'pdc-sublet-po-attach\.js\?sublet-po-attach=2026\.10\.21\.r445(&r490=2026\.10\.23\.r490)?(&r616=2026\.10\.28\.r616)?';/); // r490 (F103) appends its own tag
  assert.match(entry, /subletPo\.onload = loadSubletPoAttach;\s*subletPo\.onerror = loadSubletPoAttach;/);
  assert.match(entry, /subletPoAttach\.onload = loadOperationPanels;\s*subletPoAttach\.onerror = loadOperationPanels;/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /sublet-po-attach=2026\.10\.21\.r445/);
  assert.ok(html.indexOf('pdc-auto-reload.js') < html.indexOf('<script src="canonical-entry.js'), 'auto-reload stays the first script');
  assert.ok(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8').includes("'pdc-sublet-po-attach.js'"), 'published in Pages');
  const src = fs.readFileSync('pdc-sublet-po-attach.js', 'utf8');
  assert.match(src, /'x-upsert': 'false'/);
  assert.match(src, /\/storage\/v1\/object\/sign\/\$\{BUCKET\}/);
  assert.match(src, /expiresIn: 60/);
  assert.doesNotMatch(src, /mailto:|send_email|outbox|\.eml/i, 'attach only: no email part');
});

test('migration: private PDF-only 10 MB bucket, INSERT + SELECT policies only, pilot gate, append-only history, check 244 / F58, 8 pins; undo removes it all', () => {
  const sql = fs.readFileSync(MIG, 'utf8'), down = fs.readFileSync(DOWN, 'utf8');
  assert.match(sql, /VALUES \('pdc-sublet-po-staging','pdc-sublet-po-staging',false,10485760,ARRAY\['application\/pdf'\]\)/);
  assert.match(sql, /CREATE POLICY pdc_sublet_po_upload_445 ON storage\.objects FOR INSERT TO authenticated/);
  assert.match(sql, /CREATE POLICY pdc_sublet_po_read_445 ON storage\.objects FOR SELECT TO authenticated/);
  assert.doesNotMatch(sql, /ON storage\.objects FOR (UPDATE|DELETE|ALL)/);
  assert.match(sql, /CREATE TABLE public\.pdc_sublet_po_attach_pilot_445/);
  assert.doesNotMatch(sql, /INSERT INTO public\.pdc_sublet_po_attach_pilot_445/, 'the pilot vehicle is added at apply time, outside Git');
  assert.match(sql, /CREATE UNIQUE INDEX pdc_sublet_po_documents_445_current ON public\.pdc_sublet_po_documents_445\(vehicle_id, po_number\) WHERE superseded_at IS NULL/);
  assert.match(sql, /BEFORE UPDATE OR DELETE ON public\.pdc_sublet_po_documents_445/);
  assert.match(sql, /po_number ~ '\^GP\[0-9\]\{8\}\$'/);
  assert.match(sql, /\('sublet_po_attach_445','F58',/);
  assert.match(sql, /\$chk\$,true,244,'r445'\);/);
  assert.match(sql, /release='r445'\)<>8 OR \(SELECT count\(\*\) FROM pdc_ops\.expected_function_md5\)<>165/);
  assert.doesNotMatch(sql.replace(/--[^\n]*/g, ''), /(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_sublet_line_ticks_439|pdc_service_line_po_refs_439|pdc_pilbara_service_operations)\b/);
  assert.match(down, /DROP POLICY pdc_sublet_po_upload_445 ON storage\.objects;/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r445';/);
  assert.match(down, /<>157/);
  for (const f of [MIG, DOWN, 'tests/sublet_po_attach_445.sql', 'test_sublet_po_attach_445.js', 'pdc-sublet-po-attach.js']) {
    const text = fs.readFileSync(f, 'utf8');
    // Compared by sha256 so neither the pilot's identifiers nor the live PO ever appear in Git.
    const crypto = require('node:crypto');
    const sha = t => crypto.createHash('sha256').update(t).digest('hex');
    const forbidden = new Set(['01c1c60c5ffc39e3daf521a4cc398d6b6df76a32bbd7b61c3ff9eacc91ba94b8', 'd1bd027492a2dc89afcf191f39dfc94017f8c902234add90e7d45dbeece2983d',
      'aa9e9411119544f6c3e0cf4ab59245daa3cd9aa2b19cb9657539a529a005eb6e', 'f2fc7618cf7827201158a961f315252ae8202d824b33ff459a468e1915ca80ae',
      '250b2c1c38287f6312b71495c7a66d4f7f12fac3db17dafde03b530762a42c4e']);
    const words = text.toUpperCase().match(/[A-Z0-9-]+/g) || [];
    const hits = words.flatMap((w, i) => [w, `${w} ${words[i + 1] || ''}`]).filter(t => forbidden.has(sha(t)));
    assert.deepEqual(hits, [], `${f}: no pilot stock number, vehicle id, customer, supplier or live PO in Git`);
  }
});
