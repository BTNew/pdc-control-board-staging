'use strict';
// r405 (F14): a Pit and weigh / Pit inspection line is Pit by its wording, whatever its category.
// r405 (F15): rolled-back release tests wait for the clock tick and never hold the
// top-level change lock across a minute boundary.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');

const ID = '20261020135427_r405_pit_text_never_on_qc';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const flow = fs.readFileSync('docs/RELEASE_FLOW.md', 'utf8');
const win = fs.readFileSync('scripts/rolled_back_test_window.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const OLD = {
  helper: '6d071672dd859d7ec3e889ece66624ff', nc400: 'eac292a1d85506a02a6b5143d979a632',
  ensure: '4db6302844ef0da651d165a3716bbbac', cats: '0f77e09d7ab31418082bf4beb6af036a',
  gate: '8187b6197138008bd0248979bbc64e1b',
};
const NEW = {
  helper: '2379b7ad49c2c472e09118cedc1bd8ce', nc400: 'c79f98485c69b285cdf43ea82bafa592',
  ensure: 'd164e32cdde78185f2dbdf2612459d9e', cats: '6c295090fc3bb9b500eef31072bcfe5f',
  gate: '2d9f3d968a51790d3395c0367af70578',
};
const SAMPLES = {
  pit: ['PIT AND WEIGH', 'Pit & Weigh', 'Pit and weigh', 'PIT N WEIGH', "PIT 'N' WEIGH", 'PITS AND WEIGH', 'PIT/WEIGH', 'PIT+WEIGH', 'PIT  AND  WEIGH', 'PITANDWEIGH'.replace('ANDWEIGH', ' WEIGH'), 'PIT INSPECTION', 'Pit Inspection', 'PITINSPECTION', 'Supply pit and weigh certificate'],
  not: ['Complete Pre-Delivery Inspection', 'PITS - REFER BRYCE', 'PITS IF REQUIRED', 'TRANSPORT TO PITS', 'NO PITTING REQUIRED', 'PIT FEE FOR FUEL TANK CERTIFICATION', 'PIT IN BROOME - REFER BRYCE', 'MECHANICAL INSPECTION AN PIT PASSING', 'SPITWEIGHT', ''],
};

test('migration: staging only, exact base md5s, never names production', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  for (const md5 of Object.values(OLD)) assert.ok(up.includes(`'${md5}'`), `base md5 ${md5} asserted`);
  for (const md5 of Object.values(NEW)) assert.ok(up.includes(md5) && down.includes(md5), `new md5 ${md5} asserted up and down`);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
});

test('migration: Pit by wording, and every Pit consumer uses the helper', () => {
  assert.ok(up.includes("~ '(^|[^A-Z])PITS? ?(AND|&|\\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'"), 'wording rule');
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.pdc_qc_line_not_checkable_400[\s\S]*?OR public\.pdc_line_is_pit_401\(p_vehicle_id,p_line\)/);
  assert.match(up, /CREATE OR REPLACE FUNCTION pdc_operation_updates_private\.ensure_required_work_20261019[\s\S]*?AND NOT public\.pdc_line_is_pit_401\(p_vehicle_id,l\)/);
  assert.match(up, /CREATE OR REPLACE FUNCTION pdc_work_categories_private\.vehicle_categories[\s\S]*?AND NOT public\.pdc_line_is_pit_401\(vehicle,l\)/);
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.pdc_qc_gate_issues[\s\S]*?AND NOT public\.pdc_line_is_pit_401\(p_vehicle_id,l\)/);
  const topLevel = up.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$c405\$[\s\S]*?\$c405\$/g, '');
  assert.doesNotMatch(topLevel, /^\s*(UPDATE|DELETE FROM|INSERT INTO)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_pit_line_ticks_401)/im, 'no data rows changed');
  assert.match(up, /'pit_text_lines_never_on_qc_checklist'/);
  assert.match(up, /'F14'/);
  assert.match(up, /release='r405'|'r405'/);
});

test('undo restores the five old functions and removes pins and check', () => {
  for (const md5 of Object.values(OLD)) assert.ok(down.includes(md5), `old md5 ${md5} re-asserted`);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE[\s\S]*pit_text_lines_never_on_qc_checklist/);
  assert.match(down, /release='r405'/);
});

test('board QC page uses the same Pit wording', () => {
  const start = app.indexOf('function qcPageOperationLineIsDeferredPit(');
  const src = app.slice(start, app.indexOf('\n}\n', start) + 2);
  const fn = new Function(`${src}; return qcPageOperationLineIsDeferredPit;`)();
  for (const d of SAMPLES.pit) assert.strictEqual(fn({}, { description: d, stageCode: 'FITTING' }), true, d);
  for (const d of SAMPLES.not) assert.strictEqual(fn({}, { description: d, stageCode: 'FITTING' }), false, d);
  assert.ok(src.includes(String.raw`/(^|[^A-Z])PITS? ?(AND|&|\+|\/|N|'N')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT/`), 'same rule as the server');
  assert.match(app, /\.filter\(line => line\?\.active === true && qcPageOperationLineIsDeferredPit\(vehicle, line\)\);/, 'listed under Not required for QC with the Pit tick');
  assert.strictEqual((html.match(/pit-text=2026\.10\.20\.01/g) || []).length, 1, 'cache token');
});

test('F15: rolled-back test window template', () => {
  assert.match(win, /staging-workshop-clock-cascade/);
  assert.match(win, /BETWEEN 2 AND 15/);
  assert.match(win, /SET LOCAL lock_timeout = '2s'/);
  assert.match(win, /interval '50 seconds'/);
  assert.match(win, /pg_temp\.deadline\(\)/);
  assert.match(win, /@TAG@_DEADLINE/);
  assert.ok(win.indexOf('$window_wait$') < win.indexOf('BEGIN;'), 'waits before taking any lock');
  assert.match(flow, /scripts\/rolled_back_test_window\.sql/);
  assert.match(flow, /Proposed tick guard \(not applied\)/);
  assert.match(flow, /pg_try_advisory_xact_lock/);
});

test('FAULT_LOG has F14 and F15 after F13', () => {
  const i13 = log.indexOf('| F13 |'), i14 = log.indexOf('| F14 |'), i15 = log.indexOf('| F15 |');
  assert.ok(i13 >= 0 && i13 < i14 && i14 < i15);
  assert.ok(log.includes('20261020135427'));
  assert.ok(log.includes('pit_text_lines_never_on_qc_checklist'));
});
