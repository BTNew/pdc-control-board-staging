'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migrationPath = path.join(root, 'supabase/staging_only/087_workshop_authoritative_candidate_gate.sql');
assert(fs.existsSync(migrationPath), 'migration 087 must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();

assert(/create or replace function public\.workshop_candidate_schedule_gate/.test(sql), 'one canonical candidate gate is required');
assert(sql.includes('workshop_station_eligibility') && sql.includes('schedule_enabled'), 'candidate gate must consume authoritative station eligibility');
assert(sql.includes("'location_ineligible'") && sql.includes("'missing_eta'"), 'known disabled reasons must stay structured');
assert(/create or replace function public\.schedule_vehicle_work[\s\S]*workshop_candidate_schedule_gate/.test(sql), 'direct scheduling must preflight the authoritative candidate gate');
assert(/create or replace function public\.cascade_workshop_schedule[\s\S]*workshop_candidate_schedule_gate/.test(sql), 'cascade insert scheduling must preflight the same candidate gate');
assert(sql.includes('revoke all on function public.workshop_candidate_schedule_gate'), 'candidate gate must not be directly callable by browser roles');

console.log('Workshop authoritative candidate gate contracts passed');