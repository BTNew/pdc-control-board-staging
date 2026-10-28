'use strict';
// r642 (F257): Sublet page for Malaga Motor Trimmers. Pure helpers and wiring only; no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const mmt = require('./pdc-mmt-sublet.js');

const lines = [
  { vehicle_id: 'a', line_key: 'jc:J1:1', po_number: 'GP1', key_number: '206', stock_number: '12667943', customer: 'Acme', vehicle: 'HiLux', description: 'MMT 2 ROWS SEAT COVERS', built: false, complete: false, built_version: 0, complete_version: 0 },
  { vehicle_id: 'b', line_key: 'jc:J2:7', po_number: 'GP2', key_number: '416', stock_number: '13047148', customer: 'Beta', vehicle: 'LC79', description: 'SUB - MMT canvas', built: true, complete: false, built_version: 1, complete_version: 0 },
  { vehicle_id: 'c', line_key: 'jc:J3:2', po_number: 'GP3', key_number: '413', stock_number: '13073119', customer: 'Gamma', vehicle: 'Coaster', description: 'MMT multi row', built: true, complete: true, built_version: 1, complete_version: 2 },
];

test('stages and filters: to build, built, complete, all; search on PO, key or stock only', () => {
  assert.deepEqual(lines.map(mmt.stage), ['todo', 'built', 'complete']);
  assert.deepEqual(mmt.counts(lines), { todo: 1, built: 1, complete: 1, all: 3 });
  assert.deepEqual(mmt.filterLines(lines, 'built').map(l => l.vehicle_id), ['b']);
  assert.deepEqual(mmt.filterLines(lines, 'all', '416').map(l => l.vehicle_id), ['b']);
  assert.deepEqual(mmt.filterLines(lines, 'all', 'gp3').map(l => l.vehicle_id), ['c']);
  assert.deepEqual(mmt.filterLines(lines, 'all', 'K206').map(l => l.vehicle_id), ['a']);
  assert.deepEqual(mmt.filterLines(lines, 'all', '13073119').map(l => l.vehicle_id), ['c']);
  assert.deepEqual(mmt.filterLines(lines, 'all', 'acme'), [], 'customer is not searched');
});

test('Complete is locked until Built; Built is locked once Complete; read-only logins cannot tick', () => {
  assert.match(mmt.tickHtml(lines[0], 'complete', true), /disabled/);
  assert.doesNotMatch(mmt.tickHtml(lines[0], 'built', true), /disabled/);
  assert.doesNotMatch(mmt.tickHtml(lines[1], 'complete', true), /disabled/);
  assert.match(mmt.tickHtml(lines[2], 'built', true), /checked disabled/);
  assert.match(mmt.tickHtml(lines[1], 'built', false), /disabled/);
});

test('row shows PO, key, stock, customer and vehicle; panel escapes text', () => {
  const row = mmt.rowHtml(lines[0], true, new Set(), new Map());
  for (const text of ['GP1', 'K206', '12667943', 'Acme', 'HiLux']) assert.ok(row.includes(text), text);
  const panel = mmt.panelHtml({ can_tick: true, lines: [{ ...lines[0], customer: '<b>x</b>' }] }, { filter: 'all', search: '' });
  assert.match(panel, /&lt;b&gt;x&lt;\/b&gt;/);
  assert.match(mmt.panelHtml({ can_tick: false, lines: [] }, { filter: 'todo' }), /No MMT sublets at PMB/);
});

test('tab, view, app hooks and migration are wired', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /data-view="mmt-sublet"[^>]*>Sublet · MMT</);
  assert.match(html, /<section id="mmt-sublet" class="view">[\s\S]*id="mmt-sublet-content"/);
  assert.match(html, /pdc-mmt-sublet\.js\?r642=2026\.10\.28\.r642/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /case 'mmt-sublet':[\s\S]{0,80}PdcMmtSublet\?\.open\(\)/);
  const sql = fs.readFileSync('supabase/migrations/20261028233000_r642_mmt_sublet.sql', 'utf8');
  assert.match(sql, /project_ref = 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.match(sql, /'build_first'/);
  assert.match(sql, /pdc_sublet_line_ticks_439/);
  assert.match(sql, /= 'PMB'/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028233000_r642_mmt_sublet.down.sql'));
});

test('days at PMG badge sits beside the key, from the key number date', () => {
  const row = mmt.rowHtml({ ...lines[0], days_at_pmg: 9, key_at: '2026-10-19T02:00:00Z' }, true, new Set(), new Map());
  assert.match(row, /K206<\/span><span class="mmt-days is-mid"[^>]*>9d</);
  assert.equal(mmt.daysHtml({ days_at_pmg: null }), '');
  assert.match(mmt.daysHtml({ days_at_pmg: 20 }), /is-old/);
  assert.match(fs.readFileSync('supabase/migrations/20261028233000_r642_mmt_sublet.sql', 'utf8'), /pdc_vehicle_key_assigned_562/);
});

test('website gets the table, phones get the cards, and pmgpdc.au/mmt opens the page', () => {
  const panel = mmt.panelHtml({ can_tick: true, lines }, { filter: 'all', search: '' });
  assert.match(panel, /class="mmt-desktop table-wrap"><table class="data-table mmt-table">/);
  assert.match(panel, /class="mmt-cards"/);
  const css = fs.readFileSync('pdc-mmt-sublet.css', 'utf8');
  assert.match(css, /@media \(max-width: 760px\) \{\s*\.mmt-desktop \{ display: none; \}\s*\.mmt-cards \{ display: grid; \}/);
  assert.match(fs.readFileSync('mmt/index.html', 'utf8'), /\.\.\/#\/mmt-sublet/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'mmt\/index\.html'/);
});

test('Complete shows an Invoiced reminder; invoiced lines leave the page (server side)', () => {
  assert.equal(mmt.invoiceHtml(lines[1], true), '');
  assert.match(mmt.invoiceHtml(lines[2], true), /data-mmt-invoice="c\|jc:J3:2"[^>]*>Invoiced</);
  assert.match(mmt.rowHtml(lines[2], true, new Set(), new Map()), /Invoice when back in the office/);
  const sql = fs.readFileSync('supabase/migrations/20261028233000_r642_mmt_sublet.sql', 'utf8');
  assert.match(sql, /AND NOT coalesce\(b\.invoiced, false\)/);
  assert.match(sql, /'complete_first_invoice'/);
  assert.match(sql, /OR coalesce\(t\.ticked, false\)/, 'complete lines stay until invoiced even after leaving PMB');
});
