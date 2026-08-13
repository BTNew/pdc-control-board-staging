'use strict';
const assert = require('assert');
const fs = require('fs');

const superseded = fs.readFileSync('supabase/staging_only/077_workshop_future_parts_planning_and_start_gate.sql', 'utf8');
const canonical = fs.readFileSync('supabase/staging_only/243_craig_vehicle_drag_parts_non_blocking.sql', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const actions = fs.readFileSync('workshop-shared-actions.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');

assert.match(superseded, /parts_incomplete_entry/, 'historical migration documents the superseded gate regression');
assert.match(canonical, /create or replace function public\.workshop_parts_ready[\s\S]*?select true/,
  'Canonical compatibility predicate must never block because of Parts state');
assert.match(canonical, /not in \('QC','PARTS'\)/,
  'QC outstanding-work predicate must exclude Parts');
assert.doesNotMatch(planner, /Future workshop booking created before Parts readiness was confirmed/,
  'Planner must not retry through a fabricated Parts override');
assert.doesNotMatch(planner, /actionName === 'startWork'[\s\S]*?workshopOverrideReasonModal/,
  'Start must not request a Parts override reason');
assert.doesNotMatch(actions, /approvePartsIncompleteOverride/,
  'Frontend must not expose an obsolete Parts-gate override mutation');
assert.doesNotMatch(service, /approve_parts_incomplete_override/,
  'Data service must not advertise an obsolete Parts-gate override mutation');
assert.match(planner, /Parts must not block workshop work/,
  'A stale Parts-gate response must be identified as runtime/database drift');
console.log('Workshop Parts remains trackable but is not a planning, start, completion, QC or RFT gate');
