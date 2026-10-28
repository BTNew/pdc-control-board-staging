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

test('stages and filters: to build, built, complete, all; search on key, stock, PO, customer', () => {
  assert.deepEqual(lines.map(mmt.stage), ['todo', 'built', 'complete']);
  assert.deepEqual(mmt.counts(lines), { todo: 1, built: 1, complete: 1, all: 3 });
  assert.deepEqual(mmt.filterLines(lines, 'built').map(l => l.vehicle_id), ['b']);
  assert.deepEqual(mmt.filterLines(lines, 'all', '416').map(l => l.vehicle_id), ['b']);
  assert.deepEqual(mmt.filterLines(lines, 'all', 'gp3').map(l => l.vehicle_id), ['c']);
  assert.deepEqual(mmt.filterLines(lines, 'all', 'acme').map(l => l.vehicle_id), ['a']);
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
  for (const text of ['GP1', '206', '12667943', 'Acme', 'HiLux']) assert.ok(row.includes(text), text);
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
