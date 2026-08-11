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
  assert(/extracted_text/.test(sql) && /text_extraction_status\s*<>\s*'extracted'/.test(sql), `${name}: retained extracted-text binding missing`);
  assert(/r\.role='importer'/.test(sql) && !/r\.role in\('viewer','importer'\)/.test(sql), `${name}: operational role must be Importer-only`);
  assert(/pdc_email_evidence_consumptions/.test(sql), `${name}: global evidence-consumption guard missing`);
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
assert(/communication_vehicle_identity_disagreement/.test(comm), '160: all populated vehicle identifiers must agree');
assert(/communication_completed_work_protected/.test(comm) && !/do update set required=true,completed=false/.test(comm), '160: completed work reopening forbidden');
assert(/communication_actions_invalid/.test(comm) && /count\(\*\) from jsonb_array_elements\(v_actions\)/.test(comm), '160: contradictory/duplicate action rejection missing');
assert(/pdc_email_normalized_clause/.test(comm) && /regexp_split_to_table\(v_attachment\.extracted_text/.test(comm), '160: complete retained clause binding missing');
assert(comm.includes("E'[!?](?=\\\\s|$)") && nonnav.includes("E'[!?](?=\\\\s|$)"), '160/161: PostgreSQL E-string regex backslashes must survive parsing');
assert(comm.includes('|[?]|') && !comm.includes('|\\\\?|'), '160: literal question-mark rejection must not compile as an optional backslash');
assert(/retained_clause_sha256/.test(comm) && /action_sha256<>encode/.test(comm), '160: server-retained semantic receipt binding missing');
assert(/long range\( fuel\)\? tank[\s\S]*\(to\|onto\|on\)/.test(comm), '160: whole-phrase accessory grammar missing');
assert(/pdc_email_safe_uuid/.test(comm) && /pdc_email_safe_positive_integer/.test(comm), '160: safe UUID/integer JSON validation missing');
assert(/v_stock_candidates[\s\S]*v_vin_candidates[\s\S]*v_job_candidates/.test(comm), '160: identifiers must resolve independently');
assert(comm.indexOf("code='communication_receipt'") < comm.indexOf("received_at<clock_timestamp()-interval '30 days'"), '160: exact replay must precede freshness rejection');

assert(/backend_stock_not_found/.test(nonnav) === false, '161: fallback must not trust caller failure code');
assert(/cardinality\(v_stock_navision\)>0[\s\S]*navision_record_requires_canonical_path/.test(nonnav), '161: current Navision path exclusion missing');
assert(/'active',true,'PMB','UNALLOCATED'/.test(nonnav), '161: new vehicle PMB initialization missing');
assert(/'Nissan'/.test(nonnav) && /'Isuzu'/.test(nonnav), '161: non-Toyota make handling missing');
assert(/cardinality\(v_stock_candidates\)>1[\s\S]*cardinality\(v_vin_candidates\)>1[\s\S]*cardinality\(v_job_candidates\)>1/.test(nonnav), '161: ambiguous operational identity guard missing');
assert(/non_navision_operational_vehicle_protected/.test(nonnav), '161: completed/deleted vehicle protection missing');
assert(/non_navision_vehicle_identity_disagreement/.test(nonnav), '161: all populated vehicle identifiers must agree');
assert(/non_navision_completed_work_protected/.test(nonnav) && !/do update set required=true,completed=false/.test(nonnav), '161: completed work reopening forbidden');
assert(/operation_lines_sha256/.test(nonnav) && /non_navision_receipt_drift/.test(nonnav), '161: immutable ordered operation digest missing');
assert(/pdc_email_safe_positive_integer\(a->'source_row_no',50\)/.test(nonnav), '161: source-row type/canonical sequence guard missing');
assert(/pdc_email_safe_positive_numeric/.test(nonnav) && /pdc_email_safe_uuid/.test(nonnav), '161: safe JSON number/UUID validation missing');
assert(/pdc_email_jobcard_clause_matches/.test(nonnav) && /pmb-email-work-v2\/operation-line-v1/.test(nonnav), '161: exact retained parser-row contract missing');
assert(/pdc_non_navision_jobcard_source_row_receipts/.test(nonnav) && /tuple_sha256/.test(nonnav), '161: atomic source-coordinate tuple receipt missing');
assert(/pdc_email_jobcard_work_key/.test(nonnav), '161: work-key must be server-derived from retained description');
assert(/v_stock_navision[\s\S]*v_vin_navision[\s\S]*v_job_navision/.test(nonnav), '161: every identifier needs an independent current Navision check');
assert(/v_stock_candidates[\s\S]*v_vin_candidates[\s\S]*v_job_candidates/.test(nonnav), '161: every identifier needs independent canonical/alias resolution');
assert(/pdc_non_navision_operation_lines_immutable/.test(nonnav), '161: operation-line immutability missing');
assert(nonnav.indexOf("code='non_navision_jobcard_receipt'") < nonnav.indexOf("received_at<clock_timestamp()-interval '30 days'"), '161: exact replay must precede freshness rejection');
assert(/pdc_authenticated_email_operation_lines/.test(nonnav), '161: canonical operation lines missing');
assert(/estimated_hours_source[\s\S]*'job_card'/.test(nonnav), '161: authoritative job-card hours provenance missing');
assert(/'vehicle_created',v_created/.test(nonnav), '161: create/reuse evidence missing');
assert(!/insert into public\.workshop_bookings/i.test(nonnav), '161: job card must not create workshop booking');

console.log('Migrations 160/161 PMB email communication and non-Navision job-card contracts passed');
