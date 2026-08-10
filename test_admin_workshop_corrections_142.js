'use strict';
const fs = require('fs');
const assert = require('assert');

const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/142_vehicle_work_states_and_unallocated_stoppages.sql', 'utf8');
let count = 0;
const ok = (value, message) => { assert.ok(value, message); count += 1; };

ok(app.includes('async function saveSharedVehicleWorkStates('), 'vehicle detail has an authoritative work-state saver');
ok(app.includes('/rest/v1/rpc/set_pdc_vehicle_work_states'), 'work-state saver uses the protected staging RPC');
ok(app.includes('p_expected_version: ref.version'), 'work-state saves carry optimistic concurrency');
ok(app.includes("await loadWorkshopEligibilitySnapshot('vehicle_work_states_saved')"), 'successful work-state saves refresh Control Board eligibility');
ok(app.includes("loadWorkshopEligibilitySnapshot('route_entry_refresh')"), 'Control Board entry refreshes a connected snapshot');
ok(app.includes("String(entry?.status || '').toLowerCase() === 'stoppage'"), 'station strip detects authoritative stoppage bookings');
ok(app.includes('STOPPAGE${stoppedBooking.stoppageReason'), 'station stoppage marker includes its reason');

ok(planner.includes('function workshopRequiredJobsForStageHtml('), 'station modal renders scoped required jobs');
ok(planner.includes('Required jobs for ${escapeHtml(pmbStageLabel(stage))}'), 'station modal labels required jobs for the selected station');
ok(planner.includes('const calculatedHours = currentPlan ? workshopClampDurationHours(currentPlan.hours)'), 'modal planned time is sourced from the selected booking chip');
ok(planner.includes('name="estimated_hours"') && planner.includes('value="${escapeHtml(calculatedHours)}"'), 'estimated-hours field matches selected booking hours');
ok(css.includes('.workshop-required-job-list'), 'station required jobs have dedicated styling');

ok(sql.includes('create or replace function public.set_pdc_vehicle_work_states('), 'migration defines canonical work-state mutation');
ok(sql.includes("perform public.require_pdc_role('operator')"), 'mutation requires operator/admin authority');
ok(sql.includes("'vehicle_version_conflict'"), 'mutation rejects stale vehicle versions');
ok(sql.includes("'active_booking_exists'"), 'mutation rejects requirement removal/completion with an active booking');
const prevalidationStart = sql.indexOf('-- Validate the complete requested state map before the first durable write.');
const firstWorkMutation = Math.min(sql.indexOf('insert into public.vehicle_parts_updates('), sql.indexOf('insert into public.vehicle_work_items('));
ok(prevalidationStart >= 0 && sql.indexOf("'invalid_work_state'", prevalidationStart) < firstWorkMutation && sql.indexOf("'active_booking_exists'", prevalidationStart) < firstWorkMutation, 'all state and active-booking validation precedes work/parts mutation');
ok(sql.includes("from public.vehicle_parts_updates pu where pu.vehicle_id=p_vehicle_id order by pu.updated_at desc, pu.id desc limit 1"), 'Parts response returns one deterministic latest history row');
ok(sql.includes("jsonb_build_object('source','vehicle_detail_work_states'"), 'mutation writes auditable source metadata');
ok(sql.includes('p_reason text default null') && sql.includes("p_metadata jsonb default '{}'::jsonb"), 'migration replaces the real four-argument return helper');
ok(sql.includes("workshop_consume_transition_authorization(p_booking_id, 'return_to_queue')"), 'explicit stoppage consumes the wrapper authorization it does not use');
ok(sql.includes("else 'stoppage'::public.workshop_booking_status"), 'explicit stopped returns retain stoppage status');
ok(sql.includes('stoppage_reason = v_stoppage_reason'), 'just-move clears legacy stoppage reason instead of retaining it');
ok(sql.includes("status = 'stoppage'::public.workshop_booking_status"), 'migration repairs legacy queued stoppage anomalies');
ok(sql.includes("new.status='stoppage'") && sql.includes('new.bay_id is null'), 'validation admits only explicit unallocated stoppages');

console.log(`Admin/workshop correction regression: ${count} assertions passed.`);
