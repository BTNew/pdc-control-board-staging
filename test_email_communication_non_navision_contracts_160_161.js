#!/usr/bin/env node
const fs = require('fs');
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const comm = fs.readFileSync('supabase/staging_only/160_email_communication_board_actions.sql', 'utf8');
const nonnav = fs.readFileSync('supabase/staging_only/161_non_navision_jobcard_board_creation.sql', 'utf8');

for (const [name, sql] of [['160', comm], ['161', nonnav]]) {
  assert(/pdc_monitor_staging_guard\(\)/.test(sql), `${name}: staging guard missing`);
  assert(/pdc_provider_email_observations/.test(sql), `${name}: provider evidence missing`);
  assert(/pdc_monitor_exact_sender_enrollments/.test(sql), `${name}: exact sender enrolment missing`);
  assert(/pdc_monitor_stage_activation_writers/.test(sql), `${name}: enrolled writer gate missing`);
  assert(/grant execute[\s\S]*to authenticated/i.test(sql), `${name}: authenticated actor grant missing`);
  assert(!/grant execute[\s\S]*to service_role/i.test(sql), `${name}: operational service_role grant forbidden`);
  assert(/before update or delete/.test(sql), `${name}: immutable receipt trigger missing`);
  assert(/duplicate_of is not null/.test(sql), `${name}: duplicate intake guard missing`);
  assert(/received_at<clock_timestamp\(\)-interval '30 days'/.test(sql), `${name}: stale intake guard missing`);
  assert(/unique_violation/.test(sql), `${name}: replay/identity conflict handling missing`);
}

assert(/parts_complete/.test(comm) && /parts_received/.test(comm), '160: Parts completion action missing');
assert(/set_sublet_booking_date/.test(comm) && /update_pdc_sublet_booking_field/.test(comm), '160: Sublet date action missing');
assert(/add_accessory_work/.test(comm) && /communication_60m_fallback/.test(comm), '160: accessory/fallback action missing');
assert(/estimated_hours[^\n]*1\.00|1\.00[^\n]*'ai_estimate'/.test(comm), '160: missing-estimate 60m persistence missing');
assert(/booking_created',false/.test(comm), '160: no-booking postcondition missing');
assert(/location_changed',false/.test(comm), '160: no-location postcondition missing');
assert(!/update public\.vehicles set[^;]*current_location/is.test(comm), '160: communication must not change location');
assert(!/insert into public\.workshop_bookings/i.test(comm), '160: communication must not create workshop booking');
assert(/communication_vehicle_ambiguous/.test(comm) && /communication_vehicle_protected/.test(comm), '160: exact/protected vehicle gates missing');

assert(/backend_stock_not_found/.test(nonnav) === false, '161: fallback must not trust caller failure code');
assert(/v_navision>0[^;]*navision_record_requires_canonical_path/.test(nonnav), '161: current Navision path exclusion missing');
assert(/'active',true,'PMB','UNALLOCATED'/.test(nonnav), '161: new vehicle PMB initialization missing');
assert(/'Nissan'/.test(nonnav) && /'Isuzu'/.test(nonnav), '161: non-Toyota make handling missing');
assert(/cardinality\(v_candidates\)>1/.test(nonnav), '161: ambiguous operational identity guard missing');
assert(/non_navision_operational_vehicle_protected/.test(nonnav), '161: completed/deleted vehicle protection missing');
assert(/pdc_authenticated_email_operation_lines/.test(nonnav), '161: canonical operation lines missing');
assert(/estimated_hours_source[\s\S]*'job_card'/.test(nonnav), '161: authoritative job-card hours provenance missing');
assert(/'vehicle_created',v_created/.test(nonnav), '161: create/reuse evidence missing');
assert(!/insert into public\.workshop_bookings/i.test(nonnav), '161: job card must not create workshop booking');

console.log('Migrations 160/161 PMB email communication and non-Navision job-card contracts passed');
