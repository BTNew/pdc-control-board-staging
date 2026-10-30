/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r768 (F430): Navision Uploads on the Broome and Karratha Sales sites.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const builder = require('./tools/build-navision-profile-parser.js');

global.PDC_NAVISION_VIN = require('./navision-vin.js');
const parser = require('./navision-profile-parser.js');
const app = fs.readFileSync('./app.js', 'utf8');
const mig = fs.readFileSync('./supabase/migrations/20261031070000_r768_sales_navision_uploads.sql', 'utf8');
const salesJs = fs.readFileSync('./sales/sales.js', 'utf8');
const salesHtml = fs.readFileSync('./sales/index.html', 'utf8');
const { create } = require('./sales/navision-upload.js');

const HEAD = 'Order\tBatch\tCOSI\tDealer\tSalesperson\tCustomer Surname\tModel Description\tSub Location Description\tWMI\tVDS Number\tFrame';
const file = dealer => HEAD + '\n' + Array.from({ length: 6 }, (_, i) =>
  ['ORD' + i, i < 2 ? '' : '1300000' + i, 'Yes', i === 5 ? '001234' : dealer, 'BG 19751217', 'Example', 'HILUX SR5', 'Planned', '', '', ''].join('\t')).join('\n');

test('the shared parser is the exact PMB Navision Uploads code (rebuild tools/build-navision-profile-parser.js if app.js changed)', () => {
  assert.equal(fs.readFileSync('./navision-profile-parser.js', 'utf8'), builder.build(app));
});

test('the shared parser gives the same rows as app.js for Broome and Pilbara files', () => {
  const ctx = { window: { PDC_NAVISION_VIN: global.PDC_NAVISION_VIN } };
  vm.createContext(ctx);
  vm.runInContext(builder.STUBS.map(n => `function ${n}(){throw new Error('stub')}`).join('\n') + '\n' + builder.sliceAll(app).join('\n') +
    '\nthis.parseNavisionInput=parseNavisionInput;', ctx);
  for (const [dealer, profile] of [['037047', 'broome'], ['014450', 'pilbara']]) {
    const strip = r => JSON.parse(JSON.stringify(r.vehicles.map(v => ({ ...v, importedAt: '' }))));
    assert.deepEqual(strip(parser.parseNavisionInput(file(dealer), { pmbOnly: false, uploadProfile: profile })),
      strip(ctx.parseNavisionInput(file(dealer), { pmbOnly: false, uploadProfile: profile })));
  }
});

test('migration: branch decides the upload, existing PMB functions run unchanged, anon blocked, real person logged', () => {
  assert.match(mig, /ctx := pdc_sales_private\.context\(\);/);
  assert.match(mig, /CASE v_dealer WHEN '37047' THEN 'broome' WHEN '14450' THEN 'pilbara' END/);
  assert.doesNotMatch(mig, /p_profile text/, 'the Sales caller must not choose the profile');
  assert.match(mig, /public\.apply_navision_upload_profile\(v_profile,/);
  assert.match(mig, /public\.preview_navision_upload_profile\(v_profile,/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.sales_navision_upload_768\([^)]*\) FROM PUBLIC, anon;/);
  assert.match(mig, /PERFORM set_config\('request\.jwt\.claims', coalesce\(v_claims, ''\), true\);/, 'claims are restored');
  assert.match(mig, /INSERT INTO pdc_sales_private\.navision_uploads_768/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION (public|pdc_navision_upload_private)\.(apply|preview)_/);
});

test('Sales page has the Navision Uploads tab wired in', () => {
  assert.match(salesHtml, /data-sales-view="navision"[^>]*>Navision Uploads</);
  assert.match(salesHtml, /id="sales-navision-view"/);
  assert.ok(salesHtml.indexOf('navision-vin.js') < salesHtml.indexOf('navision-profile-parser.js'));
  assert.ok(salesHtml.indexOf('navision-upload.js') < salesHtml.indexOf('sales.js?'));
  assert.match(salesJs, /'customeremails','navision'\]/);
  assert.match(salesJs, /root\.SALES_NAVISION_UPLOAD\?\.init\(moduleOptions\(\)\)/);
});

function page(dealer, rpcImpl) {
  const els = new Map();
  const el = id => { if (!els.has(id)) els.set(id, { id, value: '', disabled: false, textContent: '', listeners: {}, files: null, addEventListener(t, f) { this.listeners[t] = f; }, click() { this.clicked = (this.clicked || 0) + 1; } }); return els.get(id); };
  const box = el('sales-navision');
  let html = '';
  Object.defineProperty(box, 'innerHTML', { get: () => html, set(v) { html = v; for (const m of String(v).matchAll(/id="([^"]+)"/g)) el(m[1]); } });
  el('sales-refresh');
  const calls = [];
  const host = {
    document: { getElementById: id => (id === 'sales-navision' || id === 'sales-refresh' || html.includes('id="' + id + '"')) ? el(id) : null },
    PDC_AUTH_CONTEXT: { userId: 'u1' }, PDC_NAVISION_PROFILE_PARSER: parser, confirm: () => true, addEventListener() {},
    PDC_SUPABASE: { rpc: async (name, args) => { calls.push({ name, args }); return rpcImpl(name, args); } },
  };
  const mod = create(host);
  mod.init({ getContext: () => ({ role: 'salesperson', dealer_code: dealer }), getView: () => 'navision' });
  mod.render();
  return { mod, el, calls, box: () => html };
}
const okPreview = profile => ({ data: { profile, result: { ok: true, code: 'preview', data: { blocking: false, source_hash: 'S', preview_hash: 'P', base_revision: 9, counts: { new: 1, changed: 2, unchanged: 3, missing: 0 } } } }, error: null });
const flush = () => new Promise(r => setImmediate(r));

test('Broome Sales previews and uploads the Broome file with the exact preview hashes', async () => {
  const p = page('37047', (name, args) => name === 'sales_navision_upload_768'
    ? (args.p_apply ? { data: { profile: 'broome', result: { ok: true, code: 'applied', data: {} } }, error: null } : okPreview('broome'))
    : { data: { applied_at: null }, error: null });
  assert.match(p.box(), /Navision Uploads · Broome Upload/);
  p.el('sales-navision-paste').listeners.input({ target: { value: file('037047') } });
  await p.el('sales-navision-preview').listeners.click(); await flush();
  const prev = p.calls.find(c => c.name === 'sales_navision_upload_768');
  assert.equal(prev.args.p_apply, false);
  assert.equal(prev.args.p_rows.length, 6);
  assert.equal(p.el('sales-navision-apply').disabled, false);
  await p.el('sales-navision-apply').listeners.click(); await flush();
  const apply = p.calls.filter(c => c.name === 'sales_navision_upload_768')[1];
  assert.equal(apply.args.p_apply, true);
  assert.equal(apply.args.p_source_hash, 'S'); assert.equal(apply.args.p_preview_hash, 'P'); assert.equal(apply.args.p_expected_revision, 9);
  assert.equal(apply.args.p_idempotency_key, 'sales-upload:broome:S');
  assert.equal(p.el('sales-refresh').clicked, 1, 'the sales board refreshes after the upload');
  assert.match(p.el('sales-navision-status').innerHTML, /Broome Upload loaded/);
});

test('Karratha Sales shows Pilbara Upload and refuses a Broome file before calling the server', async () => {
  const p = page('14450', () => okPreview('pilbara'));
  assert.match(p.box(), /Pilbara Upload/);
  p.el('sales-navision-paste').listeners.input({ target: { value: file('037047') } });
  await p.el('sales-navision-preview').listeners.click(); await flush();
  assert.equal(p.calls.filter(c => c.name === 'sales_navision_upload_768').length, 0);
  assert.match(p.el('sales-navision-status').innerHTML, /This is the Broome file\. Upload it on Broome Sales/);
  assert.equal(p.el('sales-navision-apply').disabled, true);
});

test('a blocked preview (part export) cannot be uploaded from Sales', async () => {
  const p = page('14450', name => name === 'sales_navision_upload_768'
    ? { data: { profile: 'pilbara', result: { ok: true, code: 'preview', data: { blocking: true, safety: { reason: 'suspicious_partial_snapshot' }, counts: {} } } }, error: null }
    : { data: {}, error: null });
  p.el('sales-navision-paste').listeners.input({ target: { value: file('014450') } });
  await p.el('sales-navision-preview').listeners.click(); await flush();
  assert.equal(p.el('sales-navision-apply').disabled, true);
  assert.match(p.el('sales-navision-status').innerHTML, /part export.*administrator/);
});
