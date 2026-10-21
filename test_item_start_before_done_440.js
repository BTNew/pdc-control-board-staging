'use strict';
// r440 (F51): fitter bay items need Start before Done; the running animation covers only the started items' hours.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fitters = require('./pdc-fitters.js');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const migration = fs.readFileSync('supabase/migrations/20261021064714_r440_item_start_before_done.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261021064714_r440_item_start_before_done.down.sql', 'utf8');
const item = extra => ({ line_identity: 'source:fit-1', description: 'Fit bull bar', stage_code: 'FITTING', hours: 1.5, completed: false, note: '', scope_hash: 'h', ...extra });
const state = { editable: true, disabled: false, note: '', open: false, paused: false };
const doneBox = html => html.match(/<input type="checkbox" data-fitter-line="[^"]*"[^>]*>/)[0];

test('Done stays disabled with "Press Start first" until the item is started', () => {
  const html = fitters.fitterLineCardHtml(item(), 0, state);
  assert.match(doneBox(html), /disabled/);
  assert.match(html, /Press Start first/);
  assert.match(html, /fitter-line needs-start/);
  assert.doesNotMatch(html, /data-fitter-item-start="[^"]*"[^>]*disabled/);
  const running = fitters.fitterLineCardHtml(item({ item_status: 'running', item_start_seconds: 0 }), 0, { ...state, jobSeconds: 600 });
  assert.doesNotMatch(doneBox(running), /disabled/);
  assert.doesNotMatch(running, /Press Start first/);
});

test('unticked items no longer read "Done" in the item meta (F51 root cause 1)', () => {
  const meta = html => html.match(/<small>([^<]*)<\/small>/)[1];
  assert.equal(meta(fitters.fitterLineCardHtml(item(), 0, state)), 'FITTING · 1.5 h');
  assert.doesNotMatch(meta(fitters.fitterLineCardHtml(item({ item_status: 'running', item_start_seconds: 0 }), 0, state)), /Done/);
  assert.equal(meta(fitters.fitterLineCardHtml(item({ completed: true }), 0, state)), 'FITTING · 1.5 h · Work completed');
});

test('existing Done items stay ticked and can still be unticked; supplier items keep Done alone', () => {
  let html = fitters.fitterLineCardHtml(item({ completed: true }), 0, state);
  assert.match(doneBox(html), /checked/);
  assert.doesNotMatch(doneBox(html), /disabled/);
  assert.doesNotMatch(html, /Press Start first/);
  html = fitters.fitterLineCardHtml(item({ external_work: true }), 0, state);
  assert.doesNotMatch(doneBox(html), /disabled/);
  assert.doesNotMatch(html, /Press Start first/);
  html = fitters.fitterLineCardHtml(item(), 0, { ...state, editable: false, disabled: true });
  assert.doesNotMatch(html, /Press Start first/);
});

test('an actual under a minute says so instead of "0h 00m" (F51 root cause 2); minutes never read 60', () => {
  assert.match(fitters.fitterLineCardHtml(item({ completed: true, item_status: 'done', item_actual_minutes: 0.05 }), 0, state), /Done · actual under 1 min/);
  assert.match(fitters.fitterLineCardHtml(item({ completed: true, item_status: 'done', item_actual_minutes: 0.35 }), 0, state), /Done · actual under 1 min/);
  assert.match(fitters.fitterLineCardHtml(item({ completed: true, item_status: 'done', item_actual_minutes: 119.6 }), 0, state), /Done · actual 2h 00m/);
  assert.match(fitters.fitterLineCardHtml(item({ completed: true, item_status: 'done', item_actual_minutes: 75 }), 0, state), /Done · actual 1h 15m/);
});

test('progress bar: solid Done portion, animated segment only for started items, none when nothing is started', () => {
  const started = { percent: 12, completed_hours: 1.17, total_hours: 10, running: 1, current: [{ booking_id: 'b', line_identity: 'l', description: 'Fit', elapsed_minutes: 10, allowance_minutes: 300 }] };
  let html = fitters.progressHtml(started);
  assert.match(html, /<span style="width:12%"><\/span>/);
  assert.match(html, /class="fitter-progress-run" aria-hidden="true" style="left:12%;width:50%"/);
  assert.match(html, /fitter-progress has-running/);
  html = fitters.progressHtml({ ...started, current: [...started.current, { allowance_minutes: 120 }] });
  assert.match(html, /left:12%;width:70%/);
  html = fitters.progressHtml({ ...started, percent: 80, current: [{ allowance_minutes: 600 }] });
  assert.match(html, /left:80%;width:20%/, 'segment never runs past the end of the bar');
  html = fitters.progressHtml({ percent: 12, completed_hours: 1.17, total_hours: 10, running: 0, current: [] });
  assert.doesNotMatch(html, /fitter-progress-run|has-running/);
  html = fitters.progressHtml({ percent: 0, total_hours: 10, running: 1, current: [{ allowance_minutes: null }] });
  assert.doesNotMatch(html, /fitter-progress-run/, 'no allowance, no animated hours');
  assert.match(fitters.progressHtml(started, true), /is-compact has-running/);
  const css = fs.readFileSync('pdc-conversion-ticks.css', 'utf8');
  assert.match(css, /\.fitter-progress\.has-running\{background-image:none\}/);
  assert.match(css, /\.fitter-progress>\.fitter-progress-run\{[^}]*animation:fitter-progress-run/);
  assert.match(css, /prefers-reduced-motion:reduce\)\{\.fitter-progress>\.fitter-progress-run\{animation:none\}/);
});

test('server refusal has a fitter message; cache-bust tags', () => {
  const src = fs.readFileSync('pdc-fitters.js', 'utf8');
  assert.match(src, /item_not_started:'Press Start on this item first/);
  const index = fs.readFileSync('index.html', 'utf8');
  assert.match(index, /pdc-fitters\.js\?[^"]*item-ticks=2026\.10\.20\.02[^"]*start-before-done=2026\.10\.21\.r440/);
  assert.match(index, /pdc-conversion-ticks\.css\?v=2026\.10\.20\.02&amp;start-before-done=2026\.10\.21\.r440/);
});

test('migration: staging-only, lint-clean, one function, guard before the Done write, clock untouched, exact undo', () => {
  assert.deepEqual(scanSql(migration), []);
  assert.deepEqual(scanSql(down), []);
  for (const sql of [migration, down]) {
    assert.match(sql, /pdc_monitor_staging_guard/);
    assert.match(sql, /pdc_production_environment_sentinel/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/);
    assert.match(sql, /84af7607bfd0ce9907c89bae8644d5b6/);
    assert.match(sql, /SET LOCAL lock_timeout = '2s'/);
    assert.equal(sql.includes('vjdtsswhroyguxyfjdkt'), false);
    assert.equal((sql.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1);
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\.fitter_job_command\(/);
    assert.equal(/workshop_clock_(tick|plan|next_minute)\s*\(/.test(sql.replace(/oid='public\.workshop_clock_tick\(boolean,timestamptz\)'/g, '')), false);
    assert.equal(/cron\./.test(sql), false);
  }
  const fn = migration.slice(migration.indexOf('CREATE OR REPLACE FUNCTION public.fitter_job_command('));
  const guard = fn.indexOf("RETURN jsonb_build_object('ok',false,'error','item_not_started')");
  assert.ok(guard > 0 && guard < fn.indexOf('INSERT INTO pdc_fitter_private.operation_progress'), 'guard runs before the Done write');
  assert.match(fn, /IF p_completed AND NOT coalesce\(\(l->>'completed'\)::boolean,false\)/);
  assert.match(fn, /l->>'external_work' IS DISTINCT FROM 'true' AND coalesce\(jsonb_typeof\(l->'conversion'\),'null'\)='null'/);
  assert.match(fn, /'item_done_refused'/);
  assert.match(migration, /4952bea1ccb019c7d1dfe0dc873a5c67/);
  assert.match(migration, /9c30466cfef22ccda3c6d955bf484489/);
  assert.match(migration, /'item_start_before_done','F51'/);
  assert.match(down, /release='#387',note='multiple Start\/Done items'/);
  assert.equal(down.includes("'item_not_started'"), false, 'undo restores the #387 body');
  assert.equal(/DROP TABLE|TRUNCATE/i.test(migration + down), false);
  assert.equal(fs.existsSync('tests/item_start_before_done_440_rollback.sql'), true);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F51 \|/);
});
