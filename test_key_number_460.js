/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r460 (F73, change request): vehicle key number editable by controllers / administrators with a full audit trail.
// Synthetic data only (no stock number, vehicle id, customer or job card in Git).
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const key = require('./pdc-key-number.js');
const MIG = 'supabase/migrations/20261021230424_r460_vehicle_key_number_audit.sql';
const MIGB = 'supabase/migrations/20261021230619_r460b_pin_signatures.sql';
const DOWN = 'supabase/rollbacks/20261021230424_r460_vehicle_key_number_audit.down.sql';
const V = '11111111-2222-4333-8444-555555555555';

test('key input: trimmed, spaces removed, upper case; letters/digits/-/_ up to 32; not all zeros; empty clears', () => {
  assert.equal(key.normaliseKey(' 12 5 '), '125');
  assert.equal(key.normaliseKey('ab-1'), 'AB-1');
  assert.equal(key.keyProblem(''), '');
  assert.equal(key.keyProblem('125'), '');
  assert.equal(key.keyProblem('K-07_b'), '');
  assert.match(key.keyProblem('12/5'), /letters and numbers/);
  assert.match(key.keyProblem('-5'), /letters and numbers/);
  assert.match(key.keyProblem('X'.repeat(33)), /up to 32/);
  assert.match(key.keyProblem('000'), /0 means no key/);
});

test('drop-down cell: read only for everyone else, Edit + History for controllers / admins, inline input when editing', () => {
  const ro = key.keyCellHtml({ vehicleId: V, key: '125', canEdit: false });
  assert.match(ro, /<b>Key No\.<\/b>/);
  assert.match(ro, /class="pdc-keyno-value">125</);
  assert.doesNotMatch(ro, /data-pdc-key-edit|<input/);
  assert.match(key.keyCellHtml({ vehicleId: V, key: '', canEdit: false }), /pdc-keyno-value">—</);
  const ed = key.keyCellHtml({ vehicleId: V, key: '125', canEdit: true });
  assert.match(ed, new RegExp(`data-pdc-key-edit="${V}"`));
  assert.match(ed, new RegExp(`data-pdc-key-history="${V}"`));
  const editing = key.keyCellHtml({ vehicleId: V, key: '125', canEdit: true, editing: true });
  assert.match(editing, new RegExp(`<input [^>]*data-pdc-key-input="${V}" value="125"`));
  assert.match(editing, /data-pdc-key-save=/);
  assert.match(editing, /data-pdc-key-cancel=/);
  assert.match(editing, /Every change is recorded/);
  // A non-editor never gets the input even if asked to edit.
  assert.doesNotMatch(key.keyCellHtml({ vehicleId: V, key: '125', canEdit: false, editing: true }), /<input/);
  // Escaping.
  assert.doesNotMatch(key.keyCellHtml({ vehicleId: V, key: '<b>x', canEdit: false }), /<b>x/);
});

test('history lists old -> new, how, who and when (AWST), newest first, at most 5', () => {
  const h = [{ at: '2026-10-21T23:07:18Z', source: 'release', old: null, new: '125', by: 'Approver (release)' },
    { at: '2026-10-20T01:00:00Z', source: 'import', old: '7', new: null, by: 'service import' }];
  const html = key.historyHtml(h);
  assert.match(html, /— → 125/);
  assert.match(html, /Set at release by Approver \(release\) · 22\/10\/2026, 07:07 AWST/);
  assert.match(html, /7 → —/);
  assert.match(html, /Service import by service import/);
  assert.equal((key.historyHtml(Array(9).fill(h[0])).match(/<li>/g) || []).length, 5);
  assert.match(key.historyHtml([]), /No key changes recorded/);
});

test('the Key No. cell goes right after Stock No. in the real drop-down markup; once only', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  const start = app.indexOf('function incomingVehicleDetailRow(');
  const body = app.slice(start, app.indexOf('\n}\n', start));
  assert.match(body, /<div class="incoming-vehicle-detail-grid">\n\s*\$\{vehicleEmailPartsEtaHost\(vehicle\)\}\n\s*<div><b>Stock No\.<\/b><span>\$\{escapeHtml\(stock\)\}<\/span><\/div>/, 'anchor present in app.js');
  const sample = '<details><div class="incoming-vehicle-detail-grid">\n        <div><b>Stock No.</b><span>SYN1</span></div>\n        <div><b>VIN / Chassis</b><span>—</span></div></div></details>';
  const out = key.decorateRow(sample, { vehicleId: V, key: '125', canEdit: true });
  assert.match(out, /<b>Stock No\.<\/b><span>SYN1<\/span><\/div><div class="pdc-keyno-cell" data-pdc-key-cell="[^"]+"><b>Key No\.<\/b>/);
  assert.equal(key.decorateRow(out, { vehicleId: V, key: '9', canEdit: true }), out);
  assert.equal(key.decorateRow('<div>no grid</div>', { vehicleId: V }), '<div>no grid</div>');
});

test('the board Key column shows the recorded key over a job-card value; blank keeps the prior value', () => {
  const cells = [{ label: 'Key', value: 'Check job cards' }, { label: 'SN', value: 'S1' }];
  assert.deepEqual(key.preferRecordedKey(cells, '125').map(c => c.value), ['125', 'S1']);
  assert.deepEqual(key.preferRecordedKey(cells, '').map(c => c.value), ['Check job cards', 'S1']);
});

test('in the page: wraps the drop-down and Key column; Edit appears only when the server says can_edit; Save sends version + idempotency', async () => {
  const calls = [];
  let canEdit = false;
  const vehicle = { id: V, keyNumber: '125', __emailVehicleVersion: 17 };
  const listeners = {};
  const ctx = {
    console, setTimeout: () => 0, setInterval: () => 0, crypto: { randomUUID: () => '99999999-9999-4999-8999-999999999999' },
    document: { head: { appendChild() {} }, createElement: () => ({}), addEventListener: (t, f) => { (listeners[t] ||= []).push(f); }, querySelectorAll: () => [], querySelector: () => null, visibilityState: 'visible' },
    fetch: async (url, opts) => { calls.push({ url, body: JSON.parse(opts.body) }); const body = /get_pdc_vehicle_key_number_460/.test(url) ? { ok: true, can_edit: canEdit } : { ok: true, data: { changed: true, key_number: '126', vehicle_version_after: 18 } }; return { ok: true, text: async () => JSON.stringify(body) }; },
    refreshAllViews: () => {},
  };
  ctx.window = ctx;
  ctx.window.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' };
  ctx.window.__pdcCachedAccessToken = 'jwt';
  vm.createContext(ctx);
  vm.runInContext(`var app={data:[]};function vehicleIdentityCells(v){return [{label:'Key',value:'0'},{label:'SN',value:'S'}]}
    function vehicleEmailPartsEtaHost(){return ''}
    function incomingVehicleDetailRow(v){return '<div class="incoming-vehicle-detail-grid">\\n<div><b>Stock No.</b><span>S</span></div></div>'}`, ctx);
  vm.runInContext('app.data.push(' + JSON.stringify(vehicle) + ')', ctx);
  vm.runInContext(fs.readFileSync('pdc-key-number.js', 'utf8'), ctx);
  await new Promise(r => setImmediate(r));
  assert.equal(vm.runInContext('vehicleIdentityCells(app.data[0])[0].value', ctx), '125');
  let row = vm.runInContext('incomingVehicleDetailRow(app.data[0])', ctx);
  assert.match(row, /Key No\./);
  assert.doesNotMatch(row, /data-pdc-key-edit/, 'read only until the server confirms the role');
  assert.deepEqual(calls[0].body, { p_vehicle_id: null });
  canEdit = true;
  for (const f of listeners.visibilitychange) f();
  await new Promise(r => setImmediate(r));
  row = vm.runInContext('incomingVehicleDetailRow(app.data[0])', ctx);
  assert.match(row, /data-pdc-key-edit=/);
  // Edit -> Save through the click handler.
  const click = attr => ({ preventDefault() {}, stopPropagation() {}, target: { closest: () => ({ dataset: attr }) } });
  ctx.document.querySelector = sel => (/data-pdc-key-input/.test(sel) ? { value: ' 126 ', focus() {}, select() {} } : null);
  for (const f of listeners.click) f(click({ pdcKeyEdit: V }));
  for (const f of listeners.click) f(click({ pdcKeySave: V }));
  await new Promise(r => setImmediate(r)); await new Promise(r => setImmediate(r));
  const set = calls.find(c => /set_pdc_vehicle_key_number_460/.test(c.url));
  assert.deepEqual(set.body, { p_vehicle_id: V, p_expected_vehicle_version: 17, p_key_number: '126', p_idempotency_key: '99999999-9999-4999-8999-999999999999' });
  assert.equal(vm.runInContext('app.data[0].keyNumber', ctx), '126');
  assert.equal(vm.runInContext('app.data[0].__emailVehicleVersion', ctx), 18);
});

test('loader: after pdc-parts-eta.js (onload and onerror), cache-busted; Pages ships it; auto-reload first; styles.css untouched', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /partsEta\.onload = loadJitaEta;\s*partsEta\.onerror = loadJitaEta;/);
  assert.match(entry, /jitaEta\.onload = loadWorkshopVehicleSearch;\s*jitaEta\.onerror = loadWorkshopVehicleSearch;/);
  assert.match(entry, /keyNumber\.src = 'pdc-key-number\.js\?key-number=2026\.10\.22\.r460(&r472=2026\.10\.22\.r472)?(&r490=2026\.10\.23\.r490)?';/); // r490 (F103) appends its own tag
  assert.equal((entry.match(/pdc-key-number\.js/g) || []).length, 1);
  const index = fs.readFileSync('index.html', 'utf8');
  assert.match(index, /canonical-entry\.js\?[^"]*parts-eta=2026\.10\.21\.r436&amp;key-number=2026\.10\.22\.r460&amp;sublet-po=/);
  assert.ok(index.indexOf('pdc-auto-reload.js') < index.indexOf('<script src="canonical-entry.js'), 'auto-reload first');
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-operation-panels\.js', 'pdc-key-number\.js'/);
  assert.doesNotMatch(fs.readFileSync('styles.css', 'utf8'), /pdc-keyno-/);
  assert.doesNotMatch(fs.readFileSync('pdc-key-number.js', 'utf8'), /[."' ]pdc-key-cell/, 'own classes never reuse the board table\'s .pdc-key-cell');
  assert.doesNotMatch(fs.readFileSync('app.js', 'utf8'), /pdc-key-number|set_pdc_vehicle_key_number_460/);
  assert.equal(key.VERSION, '2026.10.22.r460');
});

test('migration: audit table append-only and private, capture triggers on vehicles, edit/release paths, check 259 / F73, 6 pins; importers and tick untouched; undo removes it all', () => {
  const mig = fs.readFileSync(MIG, 'utf8'), migb = fs.readFileSync(MIGB, 'utf8'), down = fs.readFileSync(DOWN, 'utf8');
  for (const s of ['CREATE TABLE public.pdc_vehicle_key_number_audit_460', 'ENABLE ROW LEVEL SECURITY', 'REVOKE ALL ON public.pdc_vehicle_key_number_audit_460 FROM PUBLIC, anon, authenticated',
    'BEFORE UPDATE OR DELETE ON public.pdc_vehicle_key_number_audit_460', 'BEFORE TRUNCATE ON public.pdc_vehicle_key_number_audit_460',
    'AFTER UPDATE ON public.vehicles FOR EACH ROW\n WHEN (OLD.key_number IS DISTINCT FROM NEW.key_number)', 'AFTER INSERT ON public.vehicles FOR EACH ROW\n WHEN (NEW.key_number IS NOT NULL)',
    "GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid) TO authenticated",
    "REVOKE ALL ON FUNCTION pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid) FROM PUBLIC, anon, authenticated, service_role",
    "r.role::text IN ('operator','administrator')", "'vehicle_key_number_audit_460','F73'", "true,259,'r460')", "SET LOCAL lock_timeout = '2s'", 'NOT BETWEEN 2 AND 45',
    "source IN ('edit','release','import','system')", 'GET DIAGNOSTICS v_ctx = PG_CONTEXT']) assert.ok(mig.includes(s), s);
  assert.equal((mig.match(/'::regprocedure/g) || []).length >= 6, true);
  assert.match(mig, /release='r460'\)<>6/);
  // Never redefines the importers, the r388 form or the clock tick.
  assert.doesNotMatch(mig, /CREATE (OR REPLACE )?FUNCTION [a-z_]*\.?(workshop_clock_tick|pdc_apply_tune_key_number_v1|pdc_pilbara_service_apply_v1|upsert_vehicle_master_import|update_pdc_vehicle_detail_fields_388|apply_service_arrival)\b/);
  assert.doesNotMatch(mig, /ALTER TABLE public\.vehicles/);
  assert.equal((mig.match(/UPDATE public\.vehicles SET/g) || []).length, 1);
  assert.match(mig, /UPDATE public\.vehicles SET key_number=v_key, version=version\+1, updated_at=clock_timestamp\(\), updated_by=coalesce\(p_actor,updated_by\)\n   WHERE id=v_before\.id/);
  assert.doesNotMatch(mig, /ALTER TABLE public\.vehicles|UPDATE public\.vehicles SET (?!key_number=v_key, version=version\+1, updated_at=clock_timestamp\(\), updated_by=coalesce\(p_actor,updated_by\))/);
  assert.match(migb, /SET signature='public\.'\|\|signature/);
  for (const s of ['DROP TRIGGER zz_pdc_key_number_audit_460_upd ON public.vehicles', 'DROP TRIGGER zz_pdc_key_number_audit_460_ins ON public.vehicles',
    'DROP TABLE public.pdc_vehicle_key_number_audit_460', 'DROP TABLE public.pdc_vehicle_key_number_receipts_460', 'DROP SCHEMA pdc_key_number_private',
    "DELETE FROM pdc_ops.regression_checks WHERE check_name='vehicle_key_number_audit_460'", "DELETE FROM pdc_ops.expected_function_md5 WHERE release='r460'", 'export the audit']) assert.ok(down.includes(s), s);
});

test('no pilot stock number, vehicle id, customer or job card in Git (compared by sha256)', () => {
  const forbidden = new Set(['5df9bc7a08fcca9d87de8489fb4e605e7ba68dc3c9ad402981be30f0e39e2d6d', '7fc33702c68b11f0c89d68e9c36e3a8d673b17d60fec25eb64022c210ca703ab',
    '9138fa444c5c0c1316827101662976ef8023fd6cf4486ac65bdaad18fe9f5028', '8c53a170aadd0679474099a56331e70e8d805da55ee0cab7802bb844df718ee6',
    'c085a99c9ed747ff3f8ef18a729cd48f594f9516ac6d5f9296a549e5f9a61a83']);
  const sha = t => crypto.createHash('sha256').update(t).digest('hex');
  for (const f of [MIG, MIGB, DOWN, 'tests/vehicle_key_number_audit_460.sql', 'test_key_number_460.js', 'pdc-key-number.js', 'docs/vehicle-key-number.md']) {
    const words = fs.readFileSync(f, 'utf8').toUpperCase().match(/[A-Z0-9-]+/g) || [];
    assert.deepEqual(words.filter(w => forbidden.has(sha(w))), [], f);
  }
});
