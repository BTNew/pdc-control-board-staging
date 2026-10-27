'use strict';
// r578 (F196) / sort 354. The station icon follows every line of that station.
// Synthetic vehicles only. The migration is not applied here.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');
const stations = require('./sales/pmb-stations.js');
const guard = require('./vehicle-requirements-guard.js');
const eligibility = require('./workshop-eligibility.js');

const upPath = 'supabase/migrations/20261028020000_r578_station_icon_completion.sql';
const downPath = 'supabase/rollbacks/20261028020000_r578_station_icon_completion.down.sql';

test('r578 SQL is the next free check and does not rewrite a vehicle or a pin', () => {
  const up = fs.readFileSync(upPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
  assert.match(up, /'station_icon_completion_578', 'F196'/);
  assert.match(up, /true, 354, 'r578'/);
  assert.match(up, /sort_order=347 AND added_in='r576'/);
  assert.match(up, /sort_order=348 AND added_in='r566'/);
  assert.match(up, /check_name='bay_manager_hours_570' AND fault_id='F191' AND sort_order=349 AND added_in='r577'/);
  assert.match(up, /AS ok/);
  assert.match(up, /AS detail/);
  assert.doesNotMatch(up, /pg_catalog\.position\s*\(/);
  assert.match(up, /pg_catalog\.strpos/);
  assert.match(up, /<>241/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(up, /9808feb2a0a93a79b0d67aebdca0a4aa/);
  assert.match(up, /b7f90bff12643229ff80f8ca552663a2/);
  const setter = up.split('$set578$')[1].split('$set578$')[0];
  assert.match(setter, /controller_required/);
  assert.match(setter, /'operator', 'administrator'/);
  assert.equal(setter.includes('UPDATE public.vehicles'), false);
  assert.equal(setter.includes('vehicle_work_items'), false);
  assert.equal(setter.includes('workshop_bookings'), false);
  assert.equal(setter.includes('complete_workshop_work'), false);
  assert.equal(setter.includes('user_metadata'), false);
  assert.match(up, /GRANT EXECUTE ON FUNCTION public\.list_station_icon_completion_578\(uuid\[\]\) TO authenticated/);
  assert.match(up, /GRANT EXECUTE ON FUNCTION public\.set_station_completion_override_578\(uuid, text, boolean\) TO authenticated/);
  assert.doesNotMatch(up, /TO anon\b/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.match(down, /station_icon_completion_578/);
  assert.doesNotMatch(down, /panel_line_completion_565/);
  assert.doesNotMatch(down, /DELETE FROM public\.vehicles/);
  assert.doesNotMatch(down, /DELETE FROM pdc_ops\.expected_function_md5/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F196 \|/);
});

function source(name) {
  const lines = fs.readFileSync('app.js', 'utf8').split('\n');
  const start = lines.findIndex(line => new RegExp(`^(?:async )?function ${name}\\(|^const ${name} = `).test(line));
  assert.ok(start >= 0, name);
  if (/;\s*$/.test(lines[start]) && !/[[{(]\s*$/.test(lines[start])) return lines[start];
  for (let i = start + 1; i < lines.length; i += 1) if (/^[}\])]/.test(lines[i])) return lines.slice(start, i + 1).join('\n');
  throw new Error('unterminated ' + name);
}

function board() {
  const names = ['NAVISION_JITA_NUMBER_AUTHORITY', 'PDC_JOB_DEFS', 'PDC_JOB_BY_KEY', 'PMB_STAGE_TO_JOB_KEY', 'PDC_GRID_JOB_LABELS', 'PRODUCTION_FLOW_DEFS',
    'pmbStageForPdcJob', 'normalizePmbStage', 'inferredPmbStage', 'isPdcBlocked', 'pdcBlockReason', 'pdcJobRequired', 'pdcJobComplete',
    'pdcJobTriState', 'pdcJobCompletionTitle', 'pdcJobDefsPartsFirst', 'pdcGridJobLabel', 'parseIsoTimestamp', 'isBlankStock',
    'vehicleHasBatchNumber', 'vehicleNavisionJitaNumber', 'cleanNavisionText', 'escapeHtml', 'canonicalVehicleWorkState',
    'canonicalActiveSubletBooking', 'partsJobDef', 'partsStateComplete', 'isActivePartsStoppage', 'partsOrdered', 'importedPartsStatus',
    'importedPartsTitle', 'pdcStationLinesMakeComplete', 'pdcStationLinesOverrideBy', 'incomingWorkChecklistHtml'];
  const ctx = {
    window: { VehicleRequirementsGuard: guard, PDC_WORKSHOP_ELIGIBILITY: eligibility },
    WORKSHOP_ELIGIBILITY: eligibility,
    WORKSHOP_CANONICAL_STATION_DEFS: eligibility.stationDefinitions,
    vehicleKey: () => 'sample',
    pdcJobFallbackRequired: () => false,
    app: { stationIconCompletion: new Map() },
  };
  vm.runInNewContext(`${names.map(source).join('\n')}\nthis.api = { incomingWorkChecklistHtml, pdcJobComplete, pdcStationLinesMakeComplete, PDC_JOB_BY_KEY };\nthis.seedStation = (id, row) => { if (!(app.stationIconCompletion instanceof Map)) app.stationIconCompletion = new Map(); if (row) app.stationIconCompletion.set(String(id), row); else app.stationIconCompletion.delete(String(id)); };`, ctx);
  return ctx;
}

const tint = () => ({ id: '00000000-0000-4000-8000-000000000040', pdcRequiresTint: true, pdcCompleteTint: false });

test('all ticked lines turn the icon green, a partial tick does not, and untick reverts', () => {
  const ctx = board();
  const vehicle = tint();
  const id = vehicle.id;
  ctx.seedStation(id, { tint: { complete: true, override: false, by: '' } });
  const done = ctx.api.incomingWorkChecklistHtml(vehicle, { bookingProjection: { bookingRequired: false, activeBookings: [] } });
  assert.match(done, /pdc-station-tint is-required is-complete" title="Tint complete \(every line ticked\)"/);
  assert.match(done, /aria-hidden="true">✓/);
  assert.equal(ctx.api.pdcJobComplete(vehicle, ctx.api.PDC_JOB_BY_KEY.get('tint')), false);
  ctx.seedStation(id, {});
  const partial = ctx.api.incomingWorkChecklistHtml(vehicle, { bookingProjection: { bookingRequired: false, activeBookings: [] } });
  assert.match(partial, /pdc-station-tint is-required" title="TINT required - not signed off yet"/);
  assert.doesNotMatch(partial, /pdc-station-tint[^"]*is-complete/);
  ctx.seedStation(id, null);
  const cleared = ctx.api.incomingWorkChecklistHtml(vehicle, { bookingProjection: { bookingRequired: false, activeBookings: [] } });
  assert.doesNotMatch(cleared, /pdc-station-tint[^"]*is-complete/);
});

test('a station override is green and names who, and QC still reads the work-item flag', () => {
  const ctx = board();
  const vehicle = { ...tint(), pdcRequiresHoist: true, pdcCompleteHoist: false };
  ctx.seedStation(vehicle.id, { hoist: { complete: true, override: true, by: 'controller@example.test' } });
  const html = ctx.api.incomingWorkChecklistHtml(vehicle, { bookingProjection: { bookingRequired: false, activeBookings: [] } });
  assert.match(html, /pdc-station-hoist is-required is-complete" title="Hoist complete \(override by controller@example\.test\)"/);
  assert.equal(ctx.api.pdcJobComplete(vehicle, ctx.api.PDC_JOB_BY_KEY.get('hoist')), false);
  const qc = fs.readFileSync('app.js', 'utf8');
  const ready = qc.slice(qc.indexOf('function vehicleReadyForQualityControl'), qc.indexOf('function vehicleReadyForQualityControl') + 1800);
  assert.doesNotMatch(ready, /stationIconCompletion|pdcStationLines/);
  assert.doesNotMatch(source('pdcJobComplete'), /stationIconCompletion|pdcStationLines/);
  assert.match(source('canonicalVehicleWorkState'), /options\.completed === true \|\| options\.completed === false/);
  assert.doesNotMatch(source('canonicalVehicleWorkState'), /stationIconCompletion|pdcStationLines/);
  const entry = { vehicle_id: vehicle.id, has_stock: true, work: { hoist: { required: true, completed: false } },
    station_lines: [{ work_key: 'hoist', complete: true, override: true, override_email: 'controller@example.test' }] };
  const salesHtml = stations.stripHtml(stations.toBoardVehicle(entry));
  assert.match(salesHtml, /Hoist complete \(override by controller@example\.test\)/);
  assert.match(html, /Hoist complete \(override by controller@example\.test\)/);
});
