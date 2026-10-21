'use strict';
// r426 (F39): the Board's sales-prep ticks (Tint / Build PO / Tray) are controller/administrator only.
// Server: update_pdc_vehicle_sales_preparation no longer accepts viewers. Screen: importers and viewers see the ticks disabled.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20261021013317_r426_sales_prep_ticks_role_guard.sql');
const rollback = read('supabase/rollbacks/20261021013317_r426_sales_prep_ticks_role_guard.down.sql');

function fnBody(sql, header) {
  const start = sql.indexOf(header);
  assert.notEqual(start, -1, header);
  const open = sql.indexOf('$function$', start);
  const close = sql.indexOf('$function$', open + 10);
  return sql.slice(open + 10, close);
}
const HEADER = 'CREATE OR REPLACE FUNCTION public.update_pdc_vehicle_sales_preparation(';

test('server: sales-prep ticks save for operator and administrator only', () => {
  const body = fnBody(migration, HEADER);
  assert.match(body, /v_role not in \('operator', 'administrator'\)/);
  assert.doesNotMatch(body, /'viewer'|'importer'/);
});

test('rollback restores the original viewer/operator/administrator list and drops the pin and check', () => {
  const body = fnBody(rollback, HEADER);
  assert.match(body, /v_role not in \('viewer', 'operator', 'administrator'\)/);
  assert.match(rollback, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r426';/);
  assert.match(rollback, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='sales_prep_ticks_role_guard'/);
  // Apart from the gate (and its comment) the function is byte for byte the same.
  const strip = s => s.replace(/  -- r426 \(F39\)[^\n]*\n/, '').replace("('operator', 'administrator')", "('viewer', 'operator', 'administrator')");
  assert.equal(strip(fnBody(migration, HEADER)), fnBody(rollback, HEADER));
});

test('migration is windowed, staging-only, guarded, pinned and checked; Karratha 135 and the clock tick untouched', () => {
  assert.match(migration, /NOT BETWEEN 2 AND 45/);
  assert.match(migration, /cdsmnqxtyyoeoznmbidd/);
  assert.match(migration, /8b6b7ae47fb0656679aeb539c262bc21/);
  assert.match(migration, /'21c28f7dbf99e22f0c47e0f735b732ac','r426'/);
  assert.match(migration, /'sales_prep_ticks_role_guard','F39'/);
  assert.match(migration, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.doesNotMatch(migration, /FUNCTION karratha135_pdc\./);
  assert.doesNotMatch(migration, /workshop_clock_tick\(boolean,timestamptz\) *(RETURNS|AS)/i);
  assert.doesNotMatch(migration, /pit_line_tick/i);
});

function loadUi() {
  const app = read('app.js');
  const start = app.indexOf('function salesPreparationEditRoleAllowed(');
  const end = app.indexOf('function salesDashboardVehicleHtml(');
  assert.ok(start > 0 && end > start);
  const fields = app.slice(app.indexOf('const SALES_PREPARATION_FIELDS'), app.indexOf('function dashboardSalespersonCode('));
  const ctx = { window: { PDC_AUTH_CONTEXT: { role: null } }, escapeHtml: s => String(s) };
  vm.createContext(ctx);
  vm.runInContext(fields.replace('const SALES_PREPARATION_FIELDS', 'var SALES_PREPARATION_FIELDS') + app.slice(start, end), ctx);
  return ctx;
}

test('screen: ticks are editable for controllers and administrators, disabled for everyone else', () => {
  const ctx = loadUi();
  const vehicle = { __emailVehicleId: 'v1', salesPreparation: { tintRaised: true } };
  for (const role of ['operator', 'administrator']) {
    ctx.window.PDC_AUTH_CONTEXT.role = role;
    const html = ctx.salesPreparationControlsHtml(vehicle);
    assert.doesNotMatch(html, /disabled/, role);
    assert.equal((html.match(/type="checkbox"/g) || []).length, 5);
  }
  for (const role of ['importer', 'viewer', 'salesperson', 'fitter', null]) {
    ctx.window.PDC_AUTH_CONTEXT.role = role;
    const html = ctx.salesPreparationControlsHtml(vehicle);
    assert.equal((html.match(/ disabled aria-disabled="true"/g) || []).length, 5, String(role));
    assert.match(html, /checked disabled/, 'current ticks still shown');
  }
});

test('screen: change handlers only for editable roles, and the save path refuses read-only roles', () => {
  const app = read('app.js');
  assert.match(app, /if \(salesPreparationEditRoleAllowed\(\)\) \$\$\('\[data-sales-prep-field\]', host\)\.forEach/);
  const fn = app.slice(app.indexOf('async function updateSalesPreparationControl('), app.indexOf('function renderSalesDashboardBoard('));
  assert.ok(fn.indexOf('salesPreparationEditRoleAllowed()') < fn.indexOf('service.updateSalesPreparation('));
  assert.match(read('index.html'), /&amp;r426=2026\.10\.21\.01/);
});

test('no personal emails in the r426 SQL', () => {
  for (const sql of [migration, rollback]) assert.doesNotMatch(sql, /@(pmgwa|broometoyota|toyotawa)\./i);
});
