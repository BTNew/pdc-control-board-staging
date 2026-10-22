/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r401 (F10): Pit and weigh never blocks anything and any tick role can tick it.
// Craig, 20 Oct 2026 20:39 AWST: "pit and weigh do not affect anything and can be
// ticked by any department."
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const service = require('./pdc-email-vehicle-location-service.js');
function extract(name) {
  const start = app.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let open = app.indexOf(') {', start) + 2, depth = 0;
  for (let i = open; i < app.length; i += 1) {
    if (app[i] === '{') depth += 1;
    if (app[i] === '}' && --depth === 0) return app.slice(start, i + 1);
  }
  throw new Error(name);
}
const sql = fs.readFileSync('supabase/migrations/20261020130317_r401_pit_neutral.sql', 'utf8');

test('the board never counts Pit as a required job', () => {
  const ctx = { vehicleHasBatchNumber: () => true, pdcJobFallbackRequired: () => true };
  vm.createContext(ctx);
  vm.runInContext(extract('pdcJobRequired') + '\nthis.req=pdcJobRequired;', ctx);
  const def = { key: 'pitInspection', requireKey: 'pdcRequiresPitInspection' };
  assert.strictEqual(ctx.req({ pdcRequiresPitInspection: true }, def), false);
  assert.strictEqual(ctx.req({}, def), false);
  assert.strictEqual(ctx.req({ pdcRequiresBus4x4: true }, { key: 'bus4x4', requireKey: 'pdcRequiresBus4x4' }), true, 'other jobs unchanged');
});

test('Pit tick checkbox is optional and posts to the Pit RPC, not the QC tick', () => {
  const ctx = { escapeHtml: String, pdcPitTickState: new Map(), pdcPitTickPending: new Set(), pdcPitTickErrors: new Map(), pdcPitTickHandlerInstalled: true };
  vm.createContext(ctx);
  vm.runInContext(['pdcPitTickKey', 'pdcPitTickFor', 'pdcPitTickCaption', 'formatPdcPitTickTime', 'pdcPitTickCheckboxHtml', 'installPdcPitTickHandler'].map(extract).join('\n') + '\nthis.box=pdcPitTickCheckboxHtml;this.cap=pdcPitTickCaption;this.key=pdcPitTickKey;', ctx);
  const vehicle = { __emailVehicleId: '11111111-1111-4111-8111-111111111111' };
  const line = { lineIdentity: 'source:22222222-2222-4222-8222-222222222222', description: 'PIT AND WEIGH' };
  let html = ctx.box(vehicle, line);
  assert.match(html, /data-pit-tick-line="source:2222/);
  assert.doesNotMatch(html, /data-qc-operation-check/);
  assert.doesNotMatch(html, /checked/);
  ctx.pdcPitTickState.set(ctx.key(vehicle.__emailVehicleId, line.lineIdentity), { ticked: true, version: 3, ticked_by_email: 'tech@example.test', ticked_role: 'fitter' });
  html = ctx.box(vehicle, line);
  assert.match(html, /data-pit-tick-version="3"/);
  assert.match(html, /checked/);
  assert.match(ctx.cap(vehicle, line), /never blocks QC or RFT · ticked by tech@example\.test \(fitter\)/);
});

test('service exposes the Pit tick and read RPCs', () => {
  assert.strictEqual(service.PDC_PIT_LINE_TICK_RPC, 'set_pdc_pit_line_tick_401');
  assert.strictEqual(service.PDC_PIT_LINE_TICKS_READ_RPC, 'get_pdc_pit_line_ticks_401');
  const src = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
  assert.ok(src.includes('setPitLineTick, readPitLineTicks'));
  assert.ok(src.includes('data.blocks_nothing !== true'));
});

test('server migration: own tick table, any tick role, never required work, pinned', () => {
  for (const marker of ['cdsmnqxtyyoeoznmbidd', 'pdc_pit_line_ticks_401', 'pdc_pit_line_tick_history_401', 'set_pdc_pit_line_tick_401',
    'get_pdc_pit_line_ticks_401', 'pdc_line_is_pit_401', "'operator','administrator','fitter','salesperson'", 'pit_lines_neutral_and_tickable',
    'pdc_ops.expected_function_md5', 'ensure_required_work_20261019']) assert.ok(sql.includes(marker), marker);
  assert.ok(!/AND s\.code IN\([^)]*PIT_INSPECTION/.test(sql), 'Pit no longer creates required work');
  const rpc = sql.slice(sql.indexOf('$r401t$'), sql.lastIndexOf('$r401t$'));
  for (const forbidden of ['UPDATE public.vehicles', 'vehicle_work_items', 'pdc_qc_operation_completions_379']) assert.ok(!rpc.includes(forbidden), forbidden);
  assert.ok(fs.existsSync('supabase/rollbacks/20261020130317_r401_pit_neutral.down.sql'));
});
