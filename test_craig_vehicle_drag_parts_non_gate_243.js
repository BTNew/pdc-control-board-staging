'use strict';
const assert = require('assert');
const fs = require('fs');
const { buildWorkshopSharedActions } = require('./workshop-shared-actions.js');

const migration = fs.readFileSync('supabase/staging_only/243_craig_vehicle_drag_parts_non_blocking.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

assert.match(migration, /create or replace function public\.workshop_parts_ready[\s\S]*?select true/);
assert.match(migration, /work_key[\s\S]*?not in \('QC','PARTS'\)/);
assert.match(migration, /administrator_schedule_workshop_vehicle/);
assert.match(migration, /workshop_require_website_administrator_238/);
assert.match(migration, /operation_type in \('move','create'\)/);
assert.match(migration, /unique_violation[\s\S]*?idempotent_replay/);
assert.match(migration, /operation_type='create'[\s\S]*?Administrator Undo to Unallocated/);
assert.match(migration, /undo_actor_mismatch/);
assert.match(migration, /undo_expired/);
assert.match(migration, /undo_conflict/);
assert.match(migration, /grant execute[\s\S]*administrator_schedule_workshop_vehicle[\s\S]*to authenticated/);

assert.match(app, /pdcQualityControlRequirementDefinitions[\s\S]*?filter\(job => job\.key !== 'parts'\)/);
assert.match(app, /function confirmPartsIncompleteMovement\(\) \{\s*return \{ updates: \{\}, audit: null \};/);
assert.doesNotMatch(app, /Parts is clear/);
assert.match(planner, /workshop-unallocated-vehicle-pill/);
assert.match(planner, /Admin \/ Unallocated vehicle pills/);
assert.match(planner, /addEventListener\('pointerdown'[\s\S]*?pointerType === 'mouse'[\s\S]*?elementFromPoint[\s\S]*?scheduleWorkshopVehicle/);
assert.match(planner, /administratorScheduleVehicle/);
assert.match(planner, /workshopRememberAdministratorMove\(result\)/);
assert.match(service, /administrator_schedule_workshop_vehicle/);
assert.match(service, /serverMessage/);
assert.match(css, /workshop-unallocated-vehicle-pill[\s\S]*?touch-action: none/);
assert.match(index, /2026\.08\.14\.51-disable-rls-der-authority/);

const calls = [];
const actions = buildWorkshopSharedActions({ mutate: async (name, params) => { calls.push({ name, params }); return { ok: true }; } });
(async () => {
  await actions.administratorScheduleVehicle({
    vehicleId: 'v1', vehicleExpectedVersion: 9, stageCode: 'FITTING', bayNumber: 2,
    scheduledStartAt: '2026-08-14T00:00:00Z', durationMinutes: 120, technicianId: null,
    metadata: { source: 'test' }, requestId: '11111111-1111-4111-8111-111111111111', cascade: true,
  });
  assert.deepStrictEqual(calls[0], { name: 'administrator_schedule_workshop_vehicle', params: {
    p_vehicle_id: 'v1', p_vehicle_expected_version: 9, p_stage_code: 'FITTING', p_bay_number: 2,
    p_scheduled_start_at: '2026-08-14T00:00:00Z', p_duration_minutes: 120, p_technician_id: null,
    p_metadata: { source: 'test' }, p_request_id: '11111111-1111-4111-8111-111111111111', p_cascade: true,
  }});
  console.log('PASS staging 243 Craig vehicle pill, Parts non-gate, authority, create/idempotency/Undo and cache closure contract');
})().catch(error => { console.error(error); process.exit(1); });
