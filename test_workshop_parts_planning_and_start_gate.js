'use strict';

const assert = require('assert');
const fs = require('fs');

const migration = fs.readFileSync('supabase/staging_only/077_workshop_future_parts_planning_and_start_gate.sql', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const actions = fs.readFileSync('workshop-shared-actions.js', 'utf8');

assert.strictEqual(
  (migration.match(/require_pdc_role\('administrator'\)/g) || []).length,
  1,
  'Only immediate physical Start may require administrator escalation; future planning must remain operator-capable',
);
assert.match(migration, /schedule_vehicle_work[\s\S]*?parts_incomplete[\s\S]*?workshop_parts_overrides/,
  'Future scheduling must retain a structured Parts refusal and audited retry path');
assert.match(migration, /move_workshop_booking[\s\S]*?parts_incomplete[\s\S]*?workshop_parts_overrides/,
  'Future chip moves must retain a structured Parts refusal and audited retry path');
assert.match(migration, /cascade_workshop_schedule[\s\S]*?parts_incomplete[\s\S]*?workshop_parts_overrides|cascade_workshop_schedule[\s\S]*?parts_incomplete[\s\S]*?schedule_vehicle_work/,
  'Atomic Best-slot/cascade scheduling must retain the audited planning override path');
assert.match(migration, /start_workshop_work[\s\S]*?workshop_parts_ready\(v_target\.vehicle_id\)[\s\S]*?parts_incomplete_entry/,
  'Immediate Start must fail closed when physical Parts are incomplete');
assert.match(migration, /parts_incomplete_entry[\s\S]*?require_pdc_role\('administrator'\)[\s\S]*?insert into public\.workshop_parts_overrides/,
  'Immediate Parts-incomplete entry requires an administrator reason and immutable audit record');
assert.match(planner, /WORKSHOP_PLANNING_OVERRIDE_CAPABLE_ACTIONS[\s\S]*?Future workshop booking created before Parts readiness was confirmed/,
  'Future planning retries must use the fixed truthful audit reason without claiming Parts are ready');
assert.match(planner, /actionName === 'startWork'[\s\S]*?workshopOverrideReasonModal/,
  'Immediate Start must request a human override reason rather than auto-approving entry');
assert.match(actions, /startWork\(\{[\s\S]*?overrideReason[\s\S]*?parts_override_reason/,
  'Start bridge must send the explicit override reason to the protected RPC metadata');

console.log('Workshop future Parts planning and immediate Start gate contracts passed');