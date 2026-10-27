/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const vm = require('node:vm');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');
const { createDocument } = require('./qa/mini-dom-496.cjs');
const stop = require('./pdc-parts-stoppage.js');

const VID = '11111111-1111-4111-8111-111111111111';
const EMPTY = '22222222-2222-4222-8222-222222222222';
const upPath = 'supabase/migrations/20261028073000_r589_parts_eta_panel.sql';
const downPath = 'supabase/rollbacks/20261028073000_r589_parts_eta_panel.down.sql';
const md5 = text => crypto.createHash('md5').update(text).digest('hex');
const up = fs.readFileSync(upPath, 'utf8');
const down = fs.readFileSync(downPath, 'utf8');

test('the table date is read-only and the side panel is the only editor', () => {
  const state = {
    vehicleId: VID, canEdit: true, today: '2026-10-28', placed: false, emailEta: '2026-11-02',
    manual: null
  };
  const cell = stop.slotHtml({ ...state, emailEta: '' });
  assert.match(cell, /<span class="pdc-parts-stoppage-open/);
  assert.match(cell, /—/);
  assert.doesNotMatch(cell, /<button|type="date"|data-pdc-stoppage-edit=|Set ETA|Place as STOPPAGE/);
  const fromEmail = stop.slotHtml(state);
  assert.match(fromEmail, /02\/11/);
  assert.doesNotMatch(fromEmail, /<button|Set ETA/);
  assert.equal((cell.match(/<div/g) || []).length, 1);
  const dated = stop.slotHtml({ ...state, manual: { eta_date: '2026-11-02', note: 'Bull bar' }, placed: true });
  assert.match(dated, /02\/11/);
  assert.match(dated, /data-parts-eta="2026-11-02"/);
  assert.match(dated, /STOPPAGE/);
  assert.doesNotMatch(dated, /<button|data-pdc-stoppage-edit=/);
  const panel = stop.detailHtml({ ...state, emailEta: '' });
  assert.match(panel, /No date/);
  assert.match(panel, />Set date</);
  assert.match(panel, /data-pdc-stoppage-place-now=/);
  assert.match(panel, /Place as STOPPAGE/);
  const withEmail = stop.detailHtml(state);
  assert.match(withEmail, />Change</);
  assert.match(withEmail, /Place as STOPPAGE/);
  assert.match(panel, /#1d4ed8|pdc-parts-stoppage-place/);
  const editing = stop.editorHtml({ ...state, editing: true, placed: true, manual: { eta_date: '2026-11-02', note: 'Bull bar' } });
  assert.match(editing, /Place as STOPPAGE/);
  assert.match(editing, /data-pdc-stoppage-place=/);
  assert.doesNotMatch(editing, /data-pdc-stoppage-slot=|<div/);
  assert.doesNotMatch(stop.slotHtml.toString() + panel + editing, /#f97316|#f59e0b|orange/i);
  assert.doesNotMatch(fs.readFileSync('pdc-parts-stoppage.js', 'utf8'), /refreshAllViews/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /function rearmOperations/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /const redraw = key => \{ if \(state\.key === key\) render\(key, state\.bucket, \{ keepScroll: true \}\); \};/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-parts-stoppage\.js\?r567=2026\.10\.27\.r567&r573=2026\.10\.27\.r573&r589=2026\.10\.28\.r589/);
  assert.equal(fs.readFileSync('karratha/canonical-entry.js', 'utf8').includes('r589=2026.10.28.r589'), false);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('r589=2026.10.28.r589'), false);
});

test('r589 check watches the live bodies and does not replace them', () => {
  assert.match(up, /Craig approved go-live of #571/);
  assert.doesNotMatch(up, /PREVIEW|Do not apply/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt/);
  assert.match(up, /parts_eta_panel_only_589/);
  assert.match(up, /'F203'/);
  assert.match(up, /sort_order=361/);
  assert.match(up, /true, 361, 'r589'/);
  assert.match(up, /station_sublet_cache_585/);
  assert.match(up, /board_qc_nesting_587/);
  assert.doesNotMatch(up, /named_external_sublet_584|sort_order=356/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /fa275b45be296e9021f9f4dc570f5751/);
  assert.match(up, /c22076cba374291befa2ea23fc59f276/);
  assert.match(up, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.doesNotMatch(up, /CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i);
  assert.doesNotMatch(up, /INSERT\s+INTO\s+pdc_ops\.expected_function_md5/i);
  const checkSql = up.slice(up.indexOf('$chk589$') + 8, up.lastIndexOf('$chk589$'));
  assert.doesNotMatch(checkSql, /expected_function_md5\s*\)\s*(=|<>|!=)/i);
  assert.doesNotMatch(checkSql, /[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5/i);
  assert.match(up, /AS ok/);
  assert.match(up, /AS detail/);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.match(down, /WHERE check_name='parts_eta_panel_only_589'/);
  assert.doesNotMatch(down, /DROP FUNCTION|CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i);
  assert.equal(scanSql(down).length, 0);
  const faults = fs.readFileSync('docs/REPORTED_FAULTS.md', 'utf8');
  assert.match(faults, /parts_eta_panel_only_589/);
  assert.match(faults, new RegExp(md5(up)));
  assert.match(faults, new RegExp(md5(down)));
  assert.match(faults, /Set/);
});

test('setting a date and placing STOPPAGE paints the panel and the planner, not the whole board', async () => {
  const doc = createDocument();
  const listeners = [];
  doc.addEventListener = (type, fn) => { listeners.push({ type, fn }); };
  doc.visibilityState = 'visible';
  const calls = [];
  const json = data => ({ ok: true, status: 200, text: async () => JSON.stringify(data) });
  const context = {
    window: null, document: doc, console,
    setInterval() { return 0; }, setTimeout() { return 0; },
    PDC_SUPABASE_CONFIG: {
      url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-only', projectRef: 'cdsmnqxtyyoeoznmbidd'
    },
    __pdcCachedAccessToken: 'tok',
    vehicleLocationsScreenRows: () => [
      { id: VID, stock_number: '13018398', key_number: '25901' },
      { id: EMPTY, stock_number: '13018395', key_number: '25900' }
    ],
    vehicleKey: row => row.id,
    fetch: async (url, init = {}) => {
      const name = String(url).split('/rpc/')[1];
      const body = init.body ? JSON.parse(init.body) : {};
      calls.push({ name, body });
      if (name === 'get_pdc_parts_stoppage_board_564') return json({
        can_edit: true, today: '2026-10-28',
        vehicles: [
          { vehicle_id: VID, eta_date: '2026-11-02', note: 'Bull bar', stock_number: '13018398' },
          { vehicle_id: EMPTY, eta_date: '', note: '', stock_number: '13018395' }
        ]
      });
      if (name === 'get_pdc_jita_eta_board') return json({ vehicles: [] });
      if (name === 'get_pdc_parts_eta_stoppage_board_573') return json({ vehicles: [] });
      if (name === 'set_pdc_parts_stoppage_564') return json({ ok: true, changed: true, eta_date: body.p_eta_date, note: body.p_note, set_by_actor: 'craig' });
      if (name === 'place_parts_eta_stoppage_573') return json({
        ok: true, stock_number: '13018398', key_number: '25901', eta_date: body.p_eta, note: body.p_note,
        reason: 'STOPPAGE · Parts ETA 02/11/26 · Bull bar', set_by_actor: 'craig', booking_id: 'book-1'
      });
      if (name === 'get_pdc_parts_stoppage_history_564') return json({ history: [] });
      return json(null);
    }
  };
  context.window = context;
  const started = performance.now();
  vm.runInNewContext(fs.readFileSync('pdc-parts-stoppage.js', 'utf8'), context, { filename: 'pdc-parts-stoppage.js' });
  for (let i = 0; i < 20 && calls.length < 3; i += 1) await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls.map(call => call.name), [
    'get_pdc_parts_stoppage_board_564', 'get_pdc_jita_eta_board', 'get_pdc_parts_eta_stoppage_board_573'
  ]);
  const fire = (type, target) => {
    const event = { type, target, preventDefault() {}, stopPropagation() {} };
    for (const row of listeners) if (row.type === type) row.fn(event);
  };
  const dated = stop.detailHtml({ vehicleId: VID, canEdit: true, today: '2026-10-28', manual: { eta_date: '2026-11-02', note: 'Bull bar' } });
  const empty = stop.detailHtml({ vehicleId: EMPTY, canEdit: true, today: '2026-10-28', manual: null });
  const slot = stop.slotHtml({ vehicleId: VID, canEdit: true, today: '2026-10-28', manual: { eta_date: '2026-11-02', note: 'Bull bar' } });
  doc.body.innerHTML = `<table id="vlt-table-host"><tr data-vlt-key="${VID}"><td class="c-eta">${slot}</td></tr></table>${dated}${empty}<section class="workshop-parts-stoppage"></section>`;
  assert.equal(doc.querySelector('td.c-eta button'), null);
  fire('click', doc.querySelector('td.c-eta span'));
  assert.equal(doc.querySelector('td.c-eta form, td.c-eta button'), null);
  fire('click', doc.querySelector(`[data-pdc-stoppage-detail="${VID}"] [data-pdc-stoppage-edit]`));
  const form = doc.querySelector(`[data-pdc-stoppage-form="${VID}"]`);
  assert.ok(form, 'Set date opens the panel form');
  assert.match(form.textContent, /Place as STOPPAGE/);
  assert.equal(doc.querySelector('td.c-eta button, td.c-eta form'), null);
  form.querySelector('[data-pdc-stoppage-date]').value = '2026-11-04';
  form.querySelector('[data-pdc-stoppage-note]').value = 'Bull bar';
  form.querySelector('[data-pdc-stoppage-place]').checked = true;
  const before = calls.length;
  fire('submit', form);
  for (let i = 0; i < 20 && calls.length < before + 2; i += 1) await new Promise(resolve => setImmediate(resolve));
  const wrote = calls.slice(before);
  assert.deepEqual(wrote.map(call => call.name), ['set_pdc_parts_stoppage_564', 'place_parts_eta_stoppage_573']);
  assert.equal(wrote[0].body.p_eta_date, '2026-11-04');
  assert.equal(wrote[1].body.p_place, true);
  assert.equal(wrote[1].body.p_eta, '2026-11-04');
  assert.equal(calls.filter(call => call.name === 'get_pdc_parts_eta_stoppage_board_573').length, 1, 'placing does not re-read the whole stoppage board');
  const planner = doc.querySelector('.workshop-parts-stoppage').textContent;
  assert.match(planner, /STOPPAGE/);
  assert.match(planner, /13018398/);
  assert.match(planner, /25901/);
  assert.equal(doc.querySelector('td.c-eta button'), null);
  assert.match(doc.querySelector('td.c-eta').textContent, /04\/11|02\/11/);
  const emptyBox = doc.querySelector(`[data-pdc-stoppage-place-now="${EMPTY}"]`);
  emptyBox.checked = true;
  const placeCalls = calls.length;
  fire('change', emptyBox);
  for (let i = 0; i < 5; i += 1) await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.length, placeCalls, 'a STOPPAGE with no date does not call the database');
  assert.match(doc.querySelector(`[data-pdc-stoppage-detail="${EMPTY}"]`).textContent, /Set a parts ETA before placing a STOPPAGE/);
  assert.match(doc.querySelector(`[data-pdc-stoppage-detail="${EMPTY}"]`).textContent, /Place as STOPPAGE/);
  const elapsed = performance.now() - started;
  assert.ok(elapsed < 1000, `panel paint took ${elapsed.toFixed(1)} ms`);
});
