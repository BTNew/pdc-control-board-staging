'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fitters = require('./pdc-fitters.js');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const migration = fs.readFileSync('supabase/migrations/20261020150000_bus4x4_conversion_section_ticks.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261020150000_bus4x4_conversion_section_ticks.down.sql', 'utf8');

const line = (sections, extra = {}) => ({
  line_identity: 'source:hiace', description: 'BUS 4X4 CONVERSION SLWB & COMMUTER', stage_code: 'BUS_4X4', hours: 40,
  completed: false, completed_fraction: 0, note: '',
  conversion: { id: 'hiace_commuter', sections_total: sections.length, sections_done: sections.filter(s => s.status === 'complete').length, sections },
  ...extra,
});
const state = { editable: true, disabled: false, booking: 'b1', paused: false, noteDrafts: new Map(), open: true };

test('each section is its own Start / Done tick with a per-section note', () => {
  const html = fitters.conversionTicksHtml(line([
    { id: 'PA', label: 'Pre-assembly A', description: 'Adaptor housing preparation', planned_minutes: 60, status: 'not_started' },
    { id: '1', label: 'Section 1', description: 'Vehicle preparation', planned_minutes: 120, status: 'not_started' },
  ]), 0, state);
  assert.match(html, /0 of 2 sections done/);
  assert.equal((html.match(/data-conversion-step="start"/g) || []).length, 2);
  assert.equal((html.match(/data-conversion-step="done"/g) || []).length, 2);
  assert.match(html, /Pre-assembly A — Adaptor housing preparation/);
  assert.match(html, /1h 00m/);
  assert.match(html, /Add a note/);
  assert.doesNotMatch(html, /data-fitter-line=|Release blocked|comparable timed builds|Planning allowance/);
});

test('the running section animates in CSS, shows overrun, and pauses while stopped', () => {
  const running = { id: '2', label: 'Section 2', description: 'Rear lift', planned_minutes: 360, status: 'in_progress', elapsed_minutes: 90 };
  let html = fitters.conversionSectionHtml(line([running]), running, state);
  assert.match(html, /--conv-from:25%;--conv-run:16200s/);
  assert.match(html, /In progress · 1h 30m of 6h 00m/);
  html = fitters.conversionSectionHtml(line([running]), running, { ...state, paused: true });
  assert.match(html, /conv-bar is-paused/);
  const over = { ...running, elapsed_minutes: 400 };
  html = fitters.conversionSectionHtml(line([over]), over, state);
  assert.match(html, /conv-bar is-over/);
  assert.match(html, /over by 0h 40m/);
  const css = fs.readFileSync('pdc-conversion-ticks.css', 'utf8');
  assert.match(css, /@keyframes conv-fill/);
  assert.match(css, /animation-play-state:paused/);
  assert.match(css, /prefers-reduced-motion/);
});

test('done sections turn green with actual time; read-only views disable every tick', () => {
  const done = { id: '3', label: 'Section 3', description: 'Extension housing', planned_minutes: 120, status: 'complete', actual_minutes: 135 };
  let html = fitters.conversionSectionHtml(line([done]), done, state);
  assert.match(html, /conv-section is-done/);
  assert.match(html, /Done · actual 2h 15m/);
  html = fitters.conversionTicksHtml(line([done]), 0, { ...state, editable: false, disabled: true });
  assert.equal((html.match(/disabled/g) || []).length >= 2, true);
});

test('migration is staging-only, pins the guarded functions and has no bare DML', () => {
  assert.deepEqual(scanSql(migration), []);
  assert.match(migration, /pdc_monitor_staging_guard/);
  assert.match(migration, /pdc_production_environment_sentinel/);
  assert.equal(migration.includes('vjdtsswhroyguxyfjdkt'), false);
  for (const md5 of ['40ab1b0a75d347b56c69e54c65ddd193', '45b3b8f43a2a630cca14466c1a9e1567', 'befe9ecce7ea624be54b9c637a8b15df',
    'db9db4ca6a63161d873480edf8a078b6', '5bc5a3372f0d9ce7e25d1717ec027f6e', 'c49e4557e6b5d978352476e36589731b']) assert.match(migration, new RegExp(md5));
  for (const name of ['public.start_workshop_work_pre_116', 'public.fitter_job_command', 'pdc_fitter_private.conversion_view',
    'pdc_fitter_private.conversion_completion_guard', 'public.workshop_clock_tick']) {
    assert.equal(migration.includes(`CREATE OR REPLACE FUNCTION ${name}`), false, name);
  }
  assert.match(migration, /CREATE OR REPLACE FUNCTION pdc_fitter_private\.conversion_enrich/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION pdc_fitter_private\.conversion_save/);
  assert.match(migration, /NOT IN \('start','done','reset','note'\)/);
  assert.match(migration, /conversion_section_in_progress/);
  assert.match(migration, /sk:=coalesce\(c->>'scope_hash',l->>'scope_hash'\)/);
  assert.match(down, /5bc5a3372f0d9ce7e25d1717ec027f6e/);
  assert.match(down, /c49e4557e6b5d978352476e36589731b/);
  assert.equal(/DELETE\s+FROM/i.test(down), false);
});
