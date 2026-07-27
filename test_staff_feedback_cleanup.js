'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/staging_only/072_navision_safe_overlap_and_shared_sublet.sql'), 'utf8').toLowerCase();

assert(!app.includes('data-ai-intake-reason'), 'AI Intake must not render or read a staff decision-reason field');
assert(app.includes("decision === 'apply' ? 'Approved through AI Intake' : 'Denied through AI Intake'"), 'AI Intake must retain truthful automatic audit reasons');
assert(app.includes('service.decide(attempt.proposal, decision, reason, attempt.idempotencyKey)'), 'AI decisions must still use the protected exact proposal/version/idempotency path');

assert(planner.includes("Future workshop booking created before Parts readiness was confirmed"), 'Parts-incomplete future bookings must retain an automatic planning-risk audit reason');
assert(!planner.includes('const reason = await workshopOverrideReasonModal();'), 'Routine future planning must not prompt staff for a Parts override reason');
assert(planner.includes("new Set(['moveBooking', 'scheduleVehicleWork', 'cascadeSchedule'])"), 'Only booking and rescheduling actions may use the automatic planning retry');
assert(app.includes('function confirmPartsIncompleteMovement('), 'Physical workshop movement Parts gate must remain intact');

for (const removed of ['id="sidebar-toggle"', 'id="browser-assessment-export"', 'id="export-backup-top"', 'id="add-customer-top"', '>Upload Navision / PD Document</button>']) {
  assert(!staging.includes(removed), `Staging top chrome must remove ${removed}`);
}
assert(staging.includes('id="pdc-auth-user"') && staging.includes('id="pdc-auth-signout"'), 'Top chrome must retain login details and Sign out');
assert(!app.includes("on($('#sidebar-toggle'), 'click', toggleSidebar)"), 'Sidebar must no longer be collapsible');

assert(app.includes('return vehicleLocationBoardRows().filter(vehicle =>'), 'Sublet queue must use canonical Vehicle Locations rows');
assert(app.includes('update_pdc_sublet_booking_field') || fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8').includes('update_pdc_sublet_booking_field'), 'Shared Sublet edits must use the server RPC');
assert(migration.includes('create table public.pdc_sublet_bookings'), 'Shared Sublet data must have a dedicated authoritative table');
assert(migration.includes('pdc_sublet_booking_history'), 'Shared Sublet edits must be audited');
assert(migration.includes("v_role not in ('operator','importer','administrator')"), 'Shared Sublet writes must remain role gated');
assert(migration.includes("lower(wi.work_key)='sublet'") && migration.includes('wi.required and not wi.completed'), 'Only active required Sublet work may receive bookings');

assert(migration.includes('navision_import_safety_assessment_pre072'), 'Navision safety v1 must be preserved behind the bounded wrapper');
assert(migration.includes('v_selected*100>=v_incoming*95') && migration.includes('v_incoming>=100'), 'Navision release must require a large 95% dealer-identity match');
assert(migration.includes("'missing_destination','temporary_holding'") && migration.includes("'hard_delete',false"), 'Omitted Navision rows must enter reversible holding, never deletion');
assert(migration.includes("v_cross=0"), 'Cross-dealer overlap must remain blocked');

console.log('Staff feedback cleanup, future planning, Navision safety and shared Sublet contracts passed');
