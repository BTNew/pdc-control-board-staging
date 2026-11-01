'use strict';
// Stock take. r720 (F330) page wiring, r723 X, r724 found box, r808 (F443): every key at PMB low to high, tap = Seen,
// green ✓ / red ✗ per item (every station, no picking), Close = Processed (orange), New stock take for administrators.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const st = require('./pdc-stock-take.js');
const now = Date.parse('2026-11-01T11:00:00Z');
const payload = { can_tick: true, can_reset: false, round_at: '2026-11-01T10:45:00Z', cars: [
  { id: 'v1', k: '7', s: '13018394', v: 'HiLux', missing: false },
  { id: 'v2', k: '12', s: 'IS50969833', v: 'ISUDMA', missing: false, seen_at: '2026-11-01T10:50:00Z', seen_by: 'Oleg' },
  { id: 'v3', k: '40', s: '13001111', v: 'Prado', missing: false, seen_at: '2026-11-01T10:51:00Z', seen_by: 'Oleg', processed_at: '2026-11-01T10:55:00Z', processed_by: 'Garrath' },
  { id: 'v4', k: '41', s: '13001112', v: 'LC79', missing: true, missing_by: 'Craig', missing_at: '2026-11-01T10:56:00Z' },
] };
const detail = { ok: true, id: 'v1', n: ['Delivered Un-Registered'], l: [
  { id: 'source:a', st: 'FITTING', d: 'Bullbar', h: 2, done: true, by: 'Garrath', at: '2026-11-01T10:59:30Z' },
  { id: 'source:b', st: 'SUBLET', d: 'MMT seat covers', h: 0.5, done: false, x: true, x_by: 'Oleg', x_at: '2026-11-01T10:20:00Z' },
  { id: 'source:c', st: 'TYRE', d: 'Spare wheel', h: 0.2, done: false },
] };
const view = (over = {}) => ({ search: '', hideProcessed: false, missingOnly: false, pending: new Set(), errors: new Map(), details: new Map(), ...over });

test('r808: every key low to high with Not seen / Seen / Processed (orange) / Missing', () => {
  const html = st.panelHtml(payload, view(), now);
  assert.ok(html.indexOf('Key 7') < html.indexOf('Key 12') && html.indexOf('Key 12') < html.indexOf('Key 40'));
  assert.match(html, /st-car is-todo" data-st-car="v1"[\s\S]*?st-status">Not seen</);
  assert.match(html, /st-car is-seen" data-st-car="v2"[\s\S]*?st-status">Seen<\/span><span class="st-who">Oleg 18:50/);
  assert.match(html, /st-car is-processed" data-st-car="v3"[\s\S]*?st-status">Processed<\/span><span class="st-who">Garrath 18:55/);
  assert.match(html, /st-car is-missing" data-st-car="v4"[\s\S]*?CAR MISSING · flagged by Craig 18:56/);
  assert.match(html, /4 cars at PMB · <b class="st-s-todo">1 not seen<\/b> · <b class="st-s-seen">1 seen<\/b> · <b class="st-s-done">1 processed<\/b> · <b class="st-sum-miss">1 missing/);
  assert.doesNotMatch(html, /data-st-station|st-chip/, 'no station picking');
  assert.doesNotMatch(html, /data-st-yes=/, 'collapsed cars hide their items');
  const css = fs.readFileSync('pdc-stock-take.css', 'utf8');
  assert.match(css, /\.st-car\.is-processed \{[^}]*#f97316/, 'processed is orange');
});
test('r808: an open car shows every item with a green ✓ (there) and a red ✗ (missing), notes, and Close', () => {
  const html = st.panelHtml(payload, view({ openCar: 'v1', details: new Map([['v1', detail]]) }), now);
  assert.match(html, /data-st-toggle="v1" aria-expanded="true"/);
  assert.match(html, /data-st-yes="v1\|source:a" aria-pressed="true"/);
  assert.match(html, /data-st-no="v1\|source:a" aria-pressed="false"/, 'a ticked item can still be crossed');
  assert.match(html, /data-st-no="v1\|source:b" aria-pressed="true"/);
  assert.match(html, /data-st-yes="v1\|source:c" aria-pressed="false"/);
  assert.match(html, /<em>Sublet<\/em><b>✗ Missing · Oleg 18:20/);
  assert.match(html, /<em>Fitting<\/em><b>✓ Garrath 18:59/);
  assert.match(html, /st-line is-done is-fresh/);
  assert.match(html, /st-notes">Delivered Un-Registered/);
  assert.match(html, /<b class="st-t-yes">✓ 1<\/b><b class="st-t-no">✗ 1<\/b><b class="st-t-left">1 not checked/);
  assert.match(html, /data-st-close="v1">Close<\/button>/);
  assert.match(st.panelHtml(payload, view({ openCar: 'v1' }), now), /Loading the items/);
});
test('r808: a processed car shows who closed it with Undo; view-only logins cannot tick, close or flag', () => {
  const html = st.panelHtml(payload, view({ openCar: 'v3', details: new Map([['v3', { ...detail, id: 'v3' }]]) }), now);
  assert.match(html, /Processed by Garrath 18:55 · <button type="button" class="st-link" data-st-reopen="v3">Undo/);
  const ro = st.panelHtml({ ...payload, can_tick: false }, view({ openCar: 'v1', details: new Map([['v1', detail]]) }), now);
  assert.match(ro, /view only: a controller login ticks items/);
  assert.match(ro, /data-st-yes="v1\|source:c" aria-pressed="false" disabled/);
  assert.doesNotMatch(ro, /data-st-close=|data-st-missing=|data-st-reopen=/);
});
test('r808: search by key or stock; hide processed; missing only; New stock take for administrators (two taps)', () => {
  assert.deepEqual(st.visibleCars(payload, view({ search: 'K7' })).map(c => c.k), ['7']);
  assert.deepEqual(st.visibleCars(payload, view({ search: '9833' })).map(c => c.k), ['12']);
  assert.deepEqual(st.visibleCars(payload, view({ hideProcessed: true })).map(c => c.k), ['7', '12', '41']);
  assert.deepEqual(st.visibleCars(payload, view({ missingOnly: true })).map(c => c.k), ['41']);
  assert.doesNotMatch(st.panelHtml(payload, view(), now), /data-st-reset/);
  assert.match(st.panelHtml({ ...payload, can_reset: true }, view(), now), /data-st-reset>New stock take</);
  assert.match(st.panelHtml({ ...payload, can_reset: true }, view({ armReset: true }), now), /Tap again: every car back to Not seen/);
  assert.match(st.panelHtml(payload, view(), now), /Stock take started 1\/11 18:45/);
});
test('r808: wiring: open marks Seen, Close marks Processed, ✓ is the board tick, ✗ is the r723 cross, list is fast', () => {
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /rpc\('get_pdc_stock_take_808', \{\}\)/);
  assert.match(js, /rpc\('get_pdc_stock_take_car_808', \{ p_vehicle_id: id \}\)/);
  assert.match(js, /rpc\('get_pdc_stock_take_rev_808', \{\}\)/);
  assert.match(js, /save\('set_pdc_stock_take_car_808', \{ p_vehicle_id: id, p_action: 'seen' \}/);
  assert.match(js, /save\('set_pdc_stock_take_car_808', \{ p_vehicle_id: id, p_action: 'processed' \}/);
  assert.match(js, /save\('set_panel_line_completion_565', \{ p_vehicle_id: carId, p_line_identity: lineId, p_completed: on \}/);
  assert.match(js, /save\('set_pdc_stock_take_x_723', \{ p_vehicle_id: carId, p_line_identity: lineId, p_x: on \}/);
  assert.doesNotMatch(js, /function advance\(/, 'Close does not open the next car (that would mark it Seen)');
  const sql = fs.readFileSync('supabase/migrations/20261101190500_r808_stock_take_seen_processed.sql', 'utf8');
  assert.match(sql, /btrim\(coalesce\(v\.key_number, ''\)\) ~ '\^\\d\+\$'/);
  assert.match(sql, /ORDER BY p\.key_number::bigint, p\.stock_number/);
  assert.match(sql, /IF v_role NOT IN \('operator', 'administrator'\) THEN RETURN jsonb_build_object\('ok', false, 'error', 'controller_required'\)/);
  assert.match(sql, /IF v_role <> 'administrator' THEN RETURN jsonb_build_object\('ok', false, 'error', 'administrator_required'\)/);
  for (const fn of ['get_pdc_stock_take_808\\(\\)', 'get_pdc_stock_take_car_808\\(uuid\\)', 'get_pdc_stock_take_rev_808\\(\\)', 'set_pdc_stock_take_car_808\\(uuid, text\\)', 'start_pdc_stock_take_round_808\\(\\)']) {
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon;`));
  }
  assert.match(sql, /FILTER \(WHERE l\.st <> 'JOB_CARD_NOTES'\)/, 'every item except notes');
  assert.doesNotMatch(sql.split('CREATE FUNCTION public.get_pdc_stock_take_808()')[1].split('CREATE FUNCTION public.get_pdc_stock_take_car_808')[0], /pdc_qc_operation_lines_379/, 'the list never reads work lines (17 s for 214 cars)');
});
test('wired: menu, page, iPad route, short link, build', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /data-view="stock-take"/);
  assert.match(html, /<section id="stock-take" class="view">/);
  assert.match(html, /pdc-stock-take\.js\?r720=2026\.10\.29\.r720[^"]*&amp;r808=2026\.11\.01\.r808/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /'#\/stock-take'\]\.includes\(location\.hash\)/);
  assert.match(fs.readFileSync('stocktake/index.html', 'utf8'), /#\/stock-take/);
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(build, /'pdc-stock-take\.js'/);
  assert.match(build, /'stocktake\/index\.html'/);
});
test('updates never jump the screen and a release does not reload a tablet mid stock take', () => {
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /if \(list && fresh && ids\(list\.children\) === ids\(fresh\.children\)\)/);
  assert.match(js, /old\.replaceWith\(car\.cloneNode\(true\)\)/);
  assert.match(js, /if \(!el\.querySelector\('\.st-bar'\) \|\| state\.barDirty\) \{/);
  assert.match(js, /state\.open = true; root\.PDC_UNSAVED_WORK = true;/);
  assert.match(js, /state\.open = false; root\.PDC_UNSAVED_WORK = false;/);
  assert.match(fs.readFileSync('pdc-auto-reload.js', 'utf8'), /if \(win\.PDC_UNSAVED_WORK === true\) return true;/);
  assert.match(js, /settleTimer = setTimeout\(\(\) => \{ if \(!inflight\) void load\(\); \}, 2500\)/);
});
test('r724: found a car not on the list, with where the board has it', () => {
  const html = st.foundListHtml([
    { id: 'f1', k: '505', s: 'ZZ1', by: 'Oleg', at: '2026-10-29T05:59:00Z', board: null },
    { id: 'f2', k: '142', s: '13077203', note: 'Bay 3', by: 'Craig', at: '2026-10-29T05:58:00Z', board: { on_board: true, where: 'PMB', key: '142' } },
  ], true);
  assert.match(html, /Key 505<\/span><span class="st-fs">ZZ1<\/span><span class="st-fw"><b class="st-fb-none">Not on the board<\/b>/);
  assert.match(html, /On the board: <b>PMB<\/b>/);
  assert.match(html, /data-st-sorted="f2"/);
  assert.doesNotMatch(st.foundListHtml([{ id: 'f1', k: '1', s: 'S', board: null }], false), /data-st-sorted/, 'view-only logins cannot sort');
  assert.match(fs.readFileSync('pdc-stock-take.js', 'utf8'), /rpc\('set_pdc_stock_take_found_724'/);
});
