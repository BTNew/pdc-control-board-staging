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
  const html = st.panelHtml(payload, view(), now);
  assert.ok(html.indexOf('Key 7') < html.indexOf('Key 12'));
  assert.match(html, /✓ Garrath 12:59/);
  assert.match(html, /st-line is-done is-fresh/);
  assert.match(html, /2 cars at PMB · 1 finished · 2 of 3 items ticked/);
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
  assert.match(js, /if \(fresh && ids\(list\.children\) === ids\(fresh\.children\)\)/);
  assert.match(js, /old\.replaceWith\(car\.cloneNode\(true\)\)/);
  assert.match(js, /state\.open = true; root\.PDC_UNSAVED_WORK = true;/);
  assert.match(js, /state\.open = false; root\.PDC_UNSAVED_WORK = false;/);
  assert.match(fs.readFileSync('pdc-auto-reload.js', 'utf8'), /if \(win\.PDC_UNSAVED_WORK === true\) return true;/);
});
