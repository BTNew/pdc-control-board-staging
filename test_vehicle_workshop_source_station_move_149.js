'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

async function main() {
  const appText = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
  const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '149_move_source_lines_between_workshop_stations.sql'), 'utf8').toLowerCase();
  const hardeningSql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '150_lock_source_and_target_completion_for_station_moves.sql'), 'utf8').toLowerCase();

  const sourceMoveStart = appText.indexOf('async function moveVehicleWorkshopSourceLineStage(');
  const lineMoveStart = appText.indexOf('async function moveVehicleWorkshopLineStage(');
  const nextFunction = appText.indexOf('async function scheduleVehicleWorkshopNextAvailable(', lineMoveStart);
  assert(sourceMoveStart > 0 && lineMoveStart > sourceMoveStart && nextFunction > lineMoveStart, 'source station move helpers must exist');
  const sourceMoveText = appText.slice(sourceMoveStart, lineMoveStart);
  const lineMoveText = appText.slice(lineMoveStart, nextFunction);
  assert(lineMoveText.indexOf('moveVehicleWorkshopSourceLineStage(select, targetStage)') < lineMoveText.indexOf("window.prompt('Enter estimated hours"), 'source operations must use the station-only RPC before any manual-line hours prompt');
  assert(sourceMoveText.includes('/rpc/move_vehicle_workshop_source_line_stage'), 'source operation move must use its narrow audited RPC');
  assert(!sourceMoveText.includes('p_estimated_hours') && !sourceMoveText.includes('p_description'), 'browser must not rewrite source hours or description during a station move');

  assert(sql.includes("require_pdc_role('operator')"), 'RPC must require Operator authority');
  assert(sql.includes("v_line_key !~ '^source:"), 'RPC must accept only durable source operation identity');
  assert(sql.includes('and wi.required and not wi.completed'), 'target station must be required and incomplete');
  assert(hardeningSql.includes('v_current_stage:=v_before.stage_code') && hardeningSql.includes('workshop_source_stage_completed_or_unavailable'), 'current effective source station must also remain required and incomplete');
  assert((hardeningSql.match(/and wi\.required and not wi\.completed/g) || []).length >= 2, 'source and target completion must both be locked');
  assert(sql.includes("source_kind in ('source','display')") && sql.includes('estimated_hours between 0 and 999.99'), 'source overlays must preserve null, zero and precise imported hours');
  assert(sql.includes("source_kind='manual'") && sql.includes('mod(estimated_hours,0.25)=0'), 'manual lines must retain quarter-hour validation');
  const moveSql = sql.slice(sql.indexOf('create or replace function public.move_vehicle_workshop_source_line_stage'), sql.indexOf('$move$;', sql.indexOf('create or replace function public.move_vehicle_workshop_source_line_stage')));
  for (const forbidden of ['insert into public.vehicles', 'update public.vehicles', 'insert into public.workshop_bookings', 'update public.workshop_bookings', 'vehicle_parts_updates', 'update public.vehicle_work_items']) {
    assert(!moveSql.includes(forbidden), `station-only RPC must not mutate ${forbidden}`);
    const hardenedMoveSql = hardeningSql.slice(hardeningSql.indexOf('create or replace function public.move_vehicle_workshop_source_line_stage'), hardeningSql.indexOf('$move$;', hardeningSql.indexOf('create or replace function public.move_vehicle_workshop_source_line_stage')));
    assert(!hardenedMoveSql.includes(forbidden), `hardened station-only RPC must not mutate ${forbidden}`);
  }
  assert(sql.includes("'hours_changed',false") && sql.includes("'bookings_changed',false") && sql.includes("'completion_changed',false") && sql.includes("'location_changed',false"), 'audit metadata must explicitly record the station-only mutation boundary');

  const calls = [];
  let reloads = 0;
  let alerts = 0;
  const canonicalId = '11111111-1111-4111-8111-111111111111';
  const lineKey = 'source:22222222-2222-4222-8222-222222222222';
  const select = { dataset: { lineKey, adjustmentId: '', adjustmentVersion: '0' } };
  const moveVehicleWorkshopSourceLineStage = Function(
    'selectedVehicle', 'vehicleWorkshopDetailCanonicalId', 'app', 'vehicleWorkshopCanEditLines',
    'window', 'getPdcSupabaseAccessToken', 'fetch', 'loadVehicleWorkshopDetail',
    `${sourceMoveText}; return moveVehicleWorkshopSourceLineStage;`
  )(
    () => ({ id: canonicalId }),
    vehicle => vehicle.id,
    { vehicleWorkshopDetailCache: new Map([[canonicalId, { detail: { vehicle_id: canonicalId } }]]) },
    () => true,
    { PDC_SUPABASE_CONFIG: { url: 'https://staging.invalid', publishableKey: 'public-key' }, alert: () => { alerts += 1; } },
    () => 'operator-token',
    async (url, options) => { calls.push({ url, options }); return { ok: true, json: async () => ({ ok: true, code: 'workshop_source_line_station_moved' }) }; },
    async () => { reloads += 1; }
  );

  assert.strictEqual(await moveVehicleWorkshopSourceLineStage(select, 'ELECTRICAL'), true);
  assert.strictEqual(calls.length, 1);
  assert(calls[0].url.endsWith('/rest/v1/rpc/move_vehicle_workshop_source_line_stage'));
  const body = JSON.parse(calls[0].options.body);
  assert.deepStrictEqual(body, {
    p_vehicle_id: canonicalId,
    p_adjustment_id: null,
    p_expected_version: 0,
    p_line_key: lineKey,
    p_stage_code: 'ELECTRICAL',
  });
  assert.strictEqual(reloads, 1, 'successful station move must reload authoritative detail');
  assert.strictEqual(alerts, 0);

  console.log('source operation station-only move and precise-hour preservation verified');
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
