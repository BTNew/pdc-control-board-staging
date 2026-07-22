'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const sql = read('supabase/migrations/044_blocker_only_all_station_release_closure.sql');
const app = read('app.js');
const service = read('workshop-data-service.js');
const realtime = read('workshop-realtime.js');

assert(!fs.existsSync(path.join(root, 'supabase/migrations/043_all_station_review_closure.sql')), 'rejected 043 must not remain active');
assert(sql.includes('Supersedes rejected, never-applied migration 043'), '044 must formally supersede 043');
const station = sql.slice(sql.indexOf('create or replace function public.get_station_workshop_snapshot'), sql.indexOf('create or replace function public.get_workshop_eligibility_snapshot'));
const booking = sql.slice(sql.indexOf('create or replace function public.workshop_planner_booking_dto'), sql.indexOf('create or replace function public.get_station_workshop_snapshot'));
const eligibility = sql.slice(sql.indexOf('create or replace function public.get_workshop_eligibility_snapshot'), sql.indexOf('-- Scheduling wrappers'));
assert(!/to_jsonb\s*\(/i.test(`${booking}\n${station}\n${eligibility}`), 'planner DTOs must never serialize broad rows');
for (const forbidden of ['customer_name','customer_email','customer_phone','notes','metadata','deleted_reason','audit_log']) {
  assert(!station.includes(`'${forbidden}'`), `station DTO leaks ${forbidden}`);
  assert(!booking.includes(`'${forbidden}'`), `booking DTO leaks ${forbidden}`);
  assert(!eligibility.includes(`'${forbidden}'`), `eligibility DTO leaks ${forbidden}`);
}
const vehicleFields = [
  'id','permanent_vehicle_id','stock_number','toyota_order_number','job_card_number','make','model','registration',
  'current_location','pmb_stage','pmb_bay_stage','pmb_bay_number','eta_to_kewdale',
  'active_workshop_booking_id','workshop_status','version'
];
for (const field of vehicleFields) assert(station.includes(`'${field}'`), `vehicle DTO missing ${field}`);
for (const field of ['vehicle_id','work_key','required','completed','completed_at']) assert(station.includes(`'${field}'`), `work-item DTO missing ${field}`);
assert(station.includes('wi.vehicle_id=any(v_ids)') && station.includes('b.vehicle_id=any(v_ids)'), 'relational collections must share v_ids');
assert((station.match(/v\.lifecycle_state='active' and v\.deleted_at is null/g) || []).length >= 3, 'all vehicle/booking scopes must exclude inactive/deleted vehicles');
assert(station.includes("b.status in('queued','planned','started','stoppage','completed')") && station.includes('b.scheduled_start_at<v_to and b.scheduled_end_at>v_from'), 'active bookings require explicit status and overlap window');
assert(station.includes("b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to"), 'completed display requires approved actual-end window');
assert((station.match(/b\.deleted_at is null/g) || []).length >= 2 && booking.includes('b.deleted_at is null'), 'soft-deleted bookings must be excluded from shared scope and DTOs regardless of status');
assert(sql.includes("raise exception 'Unknown, inactive or planner-disabled workshop station'") && sql.includes("raise exception 'Unknown or planner-disabled workshop station'"), 'Sublet/disabled stages must fail closed');

assert(sql.includes("'vehicles','vehicle_aliases','vehicle_master_revision','vehicle_lifecycle_resolver_revision'") && sql.includes("'vehicle_movements','vehicle_parts_updates','vehicle_eta_history','vehicle_timeline_events'") && sql.includes('drop policy if exists') && sql.includes('workshop_is_planner_operator()'), 'all workshop and workflow-history policy inheritance must be replaced');
assert(sql.includes("in ('operator','administrator')"), 'only operator/admin may read workshop tables');
assert(sql.includes('create policy vehicles_planner_operator_select') && sql.includes('using(public.workshop_is_planner_operator())'), 'vehicle workflow rows and Realtime must deny importer inheritance');
assert(/revoke all on function public\.get_workshop_snapshot\(date,date\) from public,anon,authenticated/i.test(sql), 'legacy broad workshop snapshot must be browser-inaccessible');
for(const fn of ['get_workshop_configuration','list_workshop_bays','list_technicians','workshop_current_revision']) {
  const start=sql.indexOf(`function public.${fn}`);
  const end=sql.indexOf('revoke all on function',start);
  assert(start>=0 && sql.slice(start,end).includes('workshop_require_planner_operator'), `${fn} must deny importer inheritance`);
}
assert(sql.includes('revoke insert,update,delete') && sql.includes('from public,anon,authenticated'), 'direct workshop writes must be denied');
for (const fn of ['workshop_create_booking','workshop_move_booking','workshop_resize_booking','workshop_reassign_booking','workshop_start_booking','workshop_record_stoppage','workshop_resume_booking','workshop_return_booking_to_queue','workshop_delete_booking','workshop_restore_booking','workshop_complete_booking']) {
  assert(sql.includes(`revoke execute on function public.${fn}`), `${fn} must not remain directly callable`);
}

const wrapperNames = ['schedule_vehicle_work','move_workshop_booking','resize_workshop_booking','change_booking_bay','assign_booking_technician','start_workshop_work','stop_workshop_work','complete_workshop_work','resume_workshop_work','return_completed_work','return_work_to_queue','cancel_workshop_booking','restore_workshop_booking'];
for (const wrapperName of wrapperNames) {
  const start=sql.indexOf(`create or replace function public.${wrapperName}`);
  const nextFunction=sql.indexOf('create or replace function public.',start+40);
  const highLevel=sql.indexOf('-- High-level browser RPCs',start);
  const candidates=[nextFunction,highLevel].filter(value=>value>start);
  const end=Math.min(...candidates);
  const body=sql.slice(start,end);
  assert(start>=0 && end>start, `missing wrapper ${wrapperName}`);
  assert(body.includes('workshop_require_planner_operator'), `${wrapperName} lacks exact-role guard`);
  assert(!/update\s+public\.vehicles|update\s+public\.vehicle_work_items/i.test(body), `${wrapperName} mutates vehicle/work-item authority`);
}
assert(sql.includes("vehicle_not_eligible_for_station") && sql.includes('workshop_station_eligibility(v_code)'), 'create/cascade scheduling must transactionally recheck current eligibility');
for (const fn of ['move_vehicle','mark_vehicle_deleted','qc_complete_vehicle','rft_transfer_vehicle','rft_collect_vehicle','restore_vehicle','edit_vehicle_master','get_vehicle_core_snapshot','resolve_vehicle_lifecycle_identity','get_vehicle_intelligence_snapshot','approve_ai_review_item','reject_ai_review_item','cascade_workshop_schedule']) {
  assert(sql.includes(`public.${fn}(`), `${fn} inherited importer gate must be closed`);
}
assert(sql.includes('Active non-deleted vehicle is required for Workshop Planner scheduling') && sql.includes('Vehicle is not eligible for target Workshop Planner station'), 'all scheduling-shape mutations need active vehicle and shared target eligibility guards');
assert(sql.includes('workshop_require_booking_restore_eligibility(p_booking_id)') && sql.includes("b.deleted_at is not null") && sql.includes('Outstanding station requirement is required for Workshop Planner restore'), 'restore must independently recheck deleted booking, active vehicle, location and outstanding station eligibility');
assert(sql.includes("where b.deleted_at is null and b.status in('queued','planned','started','stoppage')"), 'canonical aggregate eligibility must exclude soft-deleted active-looking bookings');
for (const fn of ['assign_booking_technician','start_workshop_work','stop_workshop_work','complete_workshop_work','return_completed_work','return_work_to_queue','cancel_workshop_booking','restore_workshop_booking','resume_workshop_work']) {
  const start=sql.indexOf(`create or replace function public.${fn}`);
  const end=sql.indexOf('create or replace function public.',start+40);
  assert(start>=0 && sql.slice(start,end>start?end:undefined).includes('workshop_require_booking_active_vehicle'), `${fn} must reject inactive/deleted vehicle authority`);
}
assert(sql.includes('Ambiguous historical PITSHOIST/PITINSPECTION'), 'historical alias ambiguity must fail closed without data rewrite');

assert(app.includes('failWorkshopEligibilityOverviewSubscription') && app.includes('workshopEligibilityRequestGeneration += 1'), 'aggregate authority loss must invalidate requests');
assert(service.includes('onAuthorityLost,') && service.includes('activeLoadToken !== loadToken'), 'station late responses must be generation-invalidated');
assert(service.includes('!snapshotTrusted || pendingReloadTimer || activeLoadToken') && service.includes('setState(WORKSHOP_CONNECTION_STATE.RECONNECTING)'), 'revision signals must immediately make stale snapshots non-actionable');
assert(realtime.includes('dataService.onAuthorityLost?.()'), 'channel failures/replacements/disposal must invalidate station authority');

console.log(`Blocker remediation contract passed: ${vehicleFields.length} vehicle DTO fields, ${wrapperNames.length} safe wrappers`);
