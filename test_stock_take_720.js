'use strict';
// r720 (F330): Stock take. PMB cars by key, ticks are the board's own line tick, other people's ticks show with a name.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const st = require('./pdc-stock-take.js');
const now = Date.parse('2026-10-29T05:00:00Z');
const payload = { can_tick: true, cars: [
  { id: 'v1', k: '7', s: '13018394', v: 'HiLux', l: [
    { id: 'source:a', st: 'FITTING', d: 'Bullbar', h: 2, done: true, by: 'Garrath', at: '2026-10-29T04:59:30Z' },
    { id: 'source:b', st: 'FABRICATION', d: 'Tray', h: 1, done: false }] },
  { id: 'v2', k: '12', s: 'IS50969833', v: 'ISUDMA', l: [{ id: 'source:c', st: 'FITTING', d: 'Mats', h: 0.5, done: true, by: 'Oleg', at: '2026-10-29T03:00:00Z' }] },
] };
const view = (over = {}) => ({ stations: ['FITTING', 'FABRICATION'], search: '', openOnly: false, pending: new Set(), errors: new Map(), ...over });

test('cars by key with who ticked, fresh ticks flash', () => {
  const html = st.panelHtml(payload, view({ openCar: 'v1' }), now);
  assert.ok(html.indexOf('Key 7') < html.indexOf('Key 12'));
  assert.match(html, /✓ Garrath 12:59/);
  assert.match(html, /st-line is-done is-fresh/);
  assert.match(html, /2 cars at PMB · 1 checked · 1 finished · 2 of 3 items ticked/);
  assert.match(html, /data-st-tick="v1\|source:b"/);
});
test('search by key (K7, 7) or stock; hide finished cars', () => {
  assert.equal(st.visibleCars(payload, view({ search: 'K7' })).length, 1);
  assert.equal(st.visibleCars(payload, view({ search: '7' })).length, 1);
  assert.equal(st.visibleCars(payload, view({ search: '9833' })).length, 1);
  assert.deepEqual(st.visibleCars(payload, view({ openOnly: true })).map(c => c.k), ['7']);
});
test('view-only logins cannot tick', () => {
  const html = st.panelHtml({ ...payload, can_tick: false }, view(), now);
  assert.match(html, /view only: a controller login ticks items/);
  assert.doesNotMatch(html.replace(/disabled/g, 'D'), /data-st-tick="v1\|source:b"><span/);
});
test('wired: menu, page, iPad route, short link, board tick, server reads', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /data-view="stock-take"/);
  assert.match(html, /<section id="stock-take" class="view">/);
  assert.match(html, /pdc-stock-take\.js\?r720=2026\.10\.29\.r720/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /'#\/stock-take'\]\.includes\(location\.hash\)/);
  assert.match(fs.readFileSync('stocktake/index.html', 'utf8'), /#\/stock-take/);
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /set_panel_line_completion_565/);
  assert.match(js, /get_pdc_stock_take_rev_720/);
  const sql = fs.readFileSync('supabase/migrations/20261029140000_r720_stock_take.sql', 'utf8');
  assert.match(sql, /coalesce\(n\.panel_done, \(n\.x->>'completed'\)::boolean, false\)/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.get_pdc_stock_take_720\(text\[\]\) FROM PUBLIC, anon;/);
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(build, /'pdc-stock-take\.js'/);
  assert.match(build, /'stocktake\/index\.html'/);
});
test('updates never jump the screen and a release does not reload a tablet mid stock take', () => {
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /if \(list && fresh && ids\(list\.children\) === ids\(fresh\.children\)\)/);
  assert.match(js, /old\.replaceWith\(car\.cloneNode\(true\)\)/);
  assert.match(js, /state\.open = true; root\.PDC_UNSAVED_WORK = true;/);
  assert.match(js, /state\.open = false; root\.PDC_UNSAVED_WORK = false;/);
  assert.match(fs.readFileSync('pdc-auto-reload.js', 'utf8'), /if \(win\.PDC_UNSAVED_WORK === true\) return true;/);
});
test('Missing flag: shared, with who flagged it, and a Missing only filter', () => {
  const p = { can_tick: true, cars: [{ ...payload.cars[0], missing: true, missing_by: 'Oleg', missing_at: '2026-10-29T05:10:00Z' }, payload.cars[1]] };
  const html = st.panelHtml(p, view(), now);
  assert.match(html, /st-car is-missing/);
  assert.match(html, /MISSING · flagged by Oleg 13:10/);
  assert.match(html, /data-st-missing="v1" aria-pressed="true"[^>]*>Found it/);
  assert.match(html, /data-st-missing="v2" aria-pressed="false"[^>]*>Missing/);
  assert.match(html, /1 missing/);
  assert.deepEqual(st.visibleCars(p, view({ missingOnly: true })).map(c => c.k), ['7']);
  const sql = fs.readFileSync('supabase/migrations/20261029140000_r720_stock_take.sql', 'utf8');
  assert.match(sql, /CREATE FUNCTION public\.set_pdc_stock_take_missing_720\(p_vehicle_id uuid, p_missing boolean\)/);
  assert.match(sql, /IF v_role NOT IN \('operator', 'administrator'\) THEN RETURN jsonb_build_object\('ok', false, 'error', 'controller_required'\)/);
});
test('r723: X per item = looked at, not done; a car is checked when every item is ticked or X\'d', () => {
  const p = { can_tick: true, cars: [{ id: 'v1', k: '7', s: 'S', v: 'HiLux', l: [
    { id: 'source:a', st: 'FITTING', d: 'Towbar', h: 1, done: false, x: true, x_by: 'Oleg', x_at: '2026-10-29T05:40:00Z' },
    { id: 'source:b', st: 'FITTING', d: 'Mats', h: 0.5, done: true, by: 'Craig', at: '2026-10-29T05:39:00Z' }] }] };
  const html = st.panelHtml(p, view({ openCar: 'v1' }), now);
  assert.match(html, /st-line is-x/);
  assert.match(html, /✗ Not done · Oleg 13:40/);
  assert.match(html, /data-st-x="v1\|source:a" aria-pressed="true"/);
  assert.match(html, /data-st-x="v1\|source:b" aria-pressed="false" disabled/, 'a ticked item has no X');
  assert.match(html, /st-status">Looked at/);
  assert.match(html, /1 checked/);
  assert.match(html, /1 not done/);
  assert.equal(st.visibleCars(p, view({ openOnly: true })).length, 0, 'Hide checked cars hides it');
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /set_pdc_stock_take_x_723/);
  assert.match(js, /r723: done clears the X/);
});
test('r724: found a car not on the list, with where the board has it; typing is never redrawn', () => {
  const html = st.foundListHtml([
    { id: 'f1', k: '505', s: 'ZZ1', by: 'Oleg', at: '2026-10-29T05:59:00Z', board: null },
    { id: 'f2', k: '142', s: '13077203', note: 'Bay 3', by: 'Craig', at: '2026-10-29T05:58:00Z', board: { on_board: true, where: 'PMB', key: '142' } },
  ], true);
  assert.match(html, /Key 505<\/span><span class="st-fs">ZZ1<\/span><span class="st-fw"><b class="st-fb-none">Not on the board<\/b>/);
  assert.match(html, /On the board: <b>PMB<\/b>/);
  assert.match(html, /data-st-sorted="f2"/);
  assert.doesNotMatch(st.foundListHtml([{ id: 'f1', k: '1', s: 'S', board: null }], false), /data-st-sorted/, 'view-only logins cannot sort');
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /rpc\('set_pdc_stock_take_found_724'/);
  assert.match(js, /if \(!el\.querySelector\('\.st-bar'\) \|\| state\.barDirty\) \{/);
  assert.match(js, /swap\('\.st-sum'\); swap\('\.st-found-list'\);/);
  const sql = fs.readFileSync('supabase/migrations/20261029180000_r724_stock_take_found.sql', 'utf8');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.set_pdc_stock_take_found_724\(text, text, text, uuid\) FROM PUBLIC, anon;/);
});
test('r725: each car is a collapsed row with its status; open one to tick; it closes and the next opens', () => {
  const closed = st.panelHtml(payload, view(), now);
  assert.doesNotMatch(closed, /data-st-tick=/, 'collapsed cars hide their items');
  assert.match(closed, /data-st-toggle="v1" aria-expanded="false"/);
  assert.match(closed, /st-car is-part[^"]*" data-st-car="v1"/);
  assert.match(closed, /st-status">In progress<\/span><span class="st-count">✓ 1\/2</);
  assert.match(closed, /st-status">All done/);
  assert.match(closed, /data-st-missing="v1"/, 'Missing works without opening the car');
  const open = st.panelHtml(payload, view({ openCar: 'v1' }), now);
  assert.match(open, /data-st-toggle="v1" aria-expanded="true"/);
  assert.match(open, /data-st-tick="v1\|source:b"/);
  assert.doesNotMatch(open, /data-st-tick="v2\|/);
  const js = fs.readFileSync('pdc-stock-take.js', 'utf8');
  assert.match(js, /function advance\(car\)/);
  assert.match(js, /settleTimer = setTimeout\(\(\) => \{ if \(!inflight\) void load\(\); \}, 2500\)/);
  assert.doesNotMatch(js, /finally \{ state\.view\.pending\.delete\(id\); await load\(\); \}/, 'no reload after every tick');
});
