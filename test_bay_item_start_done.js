/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fitters = require('./pdc-fitters.js');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const migration = fs.readFileSync('supabase/migrations/20261020160000_bay_item_start_done.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261020160000_bay_item_start_done.down.sql', 'utf8');
const item = extra => ({ line_identity: 'source:fit-1', description: 'Fit bull bar', stage_code: 'FITTING', hours: 1.5, completed: false, note: '', scope_hash: 'h', ...extra });
const state = { editable: true, disabled: false, note: '', open: false, paused: false };

test('every bay item has Start and Done; since r440 Done needs Start first', () => {
  const html = fitters.fitterLineCardHtml(item(), 0, state);
  assert.match(html, /data-fitter-line="source:fit-1"/);
  assert.match(html, /data-fitter-item-start="source:fit-1"/);
  assert.doesNotMatch(html, /data-fitter-item-start="[^"]*"[^>]*disabled/);
  assert.match(html, /data-fitter-line="[^"]*"[^>]*disabled/);
  assert.doesNotMatch(fitters.fitterLineCardHtml(item({ item_status: 'running', item_start_seconds: 0 }), 0, state), /data-fitter-line="[^"]*"[^>]*disabled/);
  assert.doesNotMatch(html, /conv-bar/);
});

test('a started item animates against its allowance from the live job clock and pauses with it', () => {
  let html = fitters.fitterLineCardHtml(item({ item_status: 'running', item_start_seconds: 600, item_elapsed_minutes: 5 }), 0, { ...state, jobSeconds: 600 + 45 * 60 });
  assert.match(html, /fitter-line is-running/);
  assert.match(html, /--conv-from:50%;--conv-run:2700s/);
  assert.match(html, /In progress · 0h 45m of 1h 30m/);
  html = fitters.fitterLineCardHtml(item({ item_status: 'running', item_start_seconds: 0 }), 0, { ...state, paused: true, jobSeconds: 100 * 60 });
  assert.match(html, /conv-bar is-over is-paused/);
  assert.match(html, /over by 0h 10m/);
  html = fitters.fitterLineCardHtml(item({ hours: null, item_status: 'running', item_start_seconds: 0, item_stale: true }), 0, { ...state, jobSeconds: 1200 });
  assert.match(html, /0h 20m · no allowance · running too long/);
  assert.doesNotMatch(html, /conv-bar/);
});

test('Done turns green with the actual time; supplier and conversion items get no item Start', () => {
  let html = fitters.fitterLineCardHtml(item({ completed: true, item_status: 'done', item_actual_minutes: 75 }), 0, state);
  assert.match(html, /fitter-line is-done/);
  assert.match(html, /Done · actual 1h 15m/);
  assert.match(html, /data-fitter-item-start="source:fit-1" checked disabled/);
  html = fitters.fitterLineCardHtml(item({ external_work: true }), 0, state);
  assert.doesNotMatch(html, /data-fitter-item-start/);
  html = fitters.fitterLineCardHtml(item({ conversion: { id: 'x' } }), 0, state);
  assert.doesNotMatch(html, /data-fitter-item-start/);
});

test('Bus sections: several may run at once', () => {
  const running = { id: 'PA', label: 'Pre-assembly A', description: 'Adaptor', planned_minutes: 60, status: 'in_progress', elapsed_minutes: 10 };
  const other = { id: 'PB', label: 'Pre-assembly B', description: 'Bracket', planned_minutes: 60, status: 'not_started' };
  const line = { line_identity: 'source:c', description: 'Coaster', stage_code: 'BUS_4X4', hours: 60, completed: false, completed_fraction: 0,
    conversion: { id: 'coaster', sections_total: 2, sections_done: 0, sections_running: 1, sections: [running, other] } };
  const html = fitters.conversionTicksHtml(line, 0, { editable: true, disabled: false, booking: 'b', paused: false, noteDrafts: new Map(), open: true });
  assert.match(html, /0 of 2 sections done · 1 running/);
  assert.doesNotMatch(html, /data-conversion-step="start" data-conversion-line="source:c" data-conversion-section="PB"\s+disabled/);
  const stale = fitters.conversionSectionHtml(line, { ...running, stale: true }, { editable: true, disabled: false, booking: 'b', noteDrafts: new Map() });
  assert.match(stale, /running too long/);
});

test('board %: Done only, running shown separately, stale flagged; reset only where allowed', () => {
  const progress = { percent: 28, completed_hours: 1, total_hours: 3.5, running: 2, stale: 1, current: [
    { booking_id: 'b1', line_identity: 'l2', section: null, description: 'Wire UHF', technician: 'Sam', elapsed_minutes: 40, allowance_minutes: 90, stale: false },
    { booking_id: 'b1', line_identity: 'c', section: 'PA', description: 'Section PA', technician: 'Sam', elapsed_minutes: 300, allowance_minutes: 60, stale: true }] };
  let html = fitters.progressHtml(progress, true);
  assert.match(html, /aria-valuenow="28"/);
  assert.match(html, /style="width:28%"/);
  assert.match(html, /Running: 2/);
  assert.match(html, /Now: Wire UHF · Sam · 0h 40m of 1h 30m \+1/);
  assert.match(html, /1 running too long · reset from the planner/);
  assert.doesNotMatch(html, /<button/);
  html = fitters.progressHtml(progress, true, { resettable: true });
  assert.match(html, /data-fitter-item-reset="b1" data-fitter-item-line="c" data-fitter-item-section="PA"/);
  assert.equal((html.match(/<button/g) || []).length, 1);
  assert.equal(fitters.progressHtml({ percent: 50, completed_hours: 1, total_hours: 2 }, true).includes('fitter-running'), false);
  assert.match(fs.readFileSync('workshop-planner.js', 'utf8'), /progressHtml\(entry\.fitterProgress, true, \{ resettable: true[,} ]/);
  assert.match(fs.readFileSync('control-board-overview.js', 'utf8'), /progressHtml\(item\.source\.fitter_progress, true[,)]/);
});

test('migration is staging-only, pinned, lint-clean and leaves the clock, QC and PMB paths alone', () => {
  assert.deepEqual(scanSql(migration), []);
  assert.match(migration, /pdc_monitor_staging_guard/);
  assert.match(migration, /pdc_production_environment_sentinel/);
  assert.equal(migration.includes('vjdtsswhroyguxyfjdkt'), false);
  for (const md5 of ['40ab1b0a75d347b56c69e54c65ddd193', 'c43afa5c1312392aa5d3666a8aa7cf65', '84af7607bfd0ce9907c89bae8644d5b6',
    '00f532fdd214dcd242c267616f43bc7f', 'eea5bb523c2538742db52508665191d3', '3e5c6b28e7c025a6ebbae61879ff3a82',
    'db9db4ca6a63161d873480edf8a078b6', '6154aaf1490f5d49acfc3a5f3232edc2', 'b388403d94d1adbb5c01fd4cb979ebd2',
    '2f156fdc1cafc810d60637f50b346f12', 'fb4d6cd82f40ee27476186e0ac5b05f4']) assert.match(migration, new RegExp(md5));
  for (const name of ['public.start_workshop_work_pre_116', 'public.workshop_clock_tick', 'pdc_work_categories_private.base_lines',
    'pdc_fitter_private.summary', 'pdc_fitter_private.timing', 'pdc_codex_intake_private.apply_service_pmb_complete',
    'pdc_codex_intake_private.finish_tune_checkout', 'pdc_work_categories_private.invalidate_qc_operation_lines_cache']) {
    assert.equal(migration.includes(`CREATE OR REPLACE FUNCTION ${name}(`), false, name);
  }
  assert.equal(/CREATE TRIGGER/i.test(migration), false);
  assert.equal(/UPDATE public\.workshop_bookings/.test(migration.split('-- ===== CONVERSION SAVE')[0]), false);
  assert.equal(migration.includes("'error','conversion_section_in_progress'"), false);
  assert.match(migration, /p_action NOT IN\('start','line','stop','resume','complete','conversion','item_start','item_reset'\)/);
  assert.match(down, /db9db4ca6a63161d873480edf8a078b6/);
  assert.match(down, /E'\\n', E'\\r\\n'/);
  assert.equal(/DELETE\s+FROM|DROP TABLE/i.test(down), false);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*item-ticks=2026\.10\.20\.02/);
});

test('a job completed by Sub Status 80 / 99 shows no running items and is never reset', () => {
  const progress = migration.slice(migration.indexOf('FUNCTION pdc_fitter_private.progress('));
  assert.match(progress, /IF b\.deleted_at IS NULL AND b\.status IN \('queued','planned','started','stoppage'\) THEN/);
  const reset = migration.slice(migration.indexOf('FUNCTION public.reset_fitter_item_timing('));
  assert.match(reset, /IF b\.status NOT IN \('queued','planned','started','stoppage'\) THEN RETURN jsonb_build_object\('ok',false,'error','booking_not_active'\)/);
  assert.match(fs.readFileSync('pdc-fitters.js', 'utf8'), /booking_not_active:'That job is already complete/);
  assert.equal(fs.existsSync('tests/bay_item_start_done_substatus_rollback.sql'), true);
});
