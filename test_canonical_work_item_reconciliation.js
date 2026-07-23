'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const sql = read('supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql');
const lifecycle = read('supabase/migrations/050_workshop_tile_completion_and_live_bay.sql');
const app = read('app.js');
const planner = read('workshop-planner.js');
const eligibility = read('workshop-eligibility.js');
const backup = read('scripts/pdc_backup.py');
const applyScript = read('scripts/apply_migration_045_staging.py');
const reconcileScript = read('scripts/reconcile_legacy_stage_staging.py');
const backupGate = read('scripts/release_backup_gate.py');
const stagingHtml = read('staging.html');

const eligibilitySql = sql.slice(sql.indexOf('create or replace function public.workshop_station_eligibility'), sql.indexOf('create or replace function public.get_station_workshop_snapshot'));
assert(eligibilitySql.includes('from public.vehicle_work_items wi') && eligibilitySql.includes('wi.required and not wi.completed'), 'outstanding work item must be the sole candidate authority');
assert(!eligibilitySql.includes('v.pmb_stage') && !eligibilitySql.includes('workshop_canonical_stage_code(v.pmb_stage)'), 'legacy pmb_stage must not participate in eligibility');
assert(!eligibilitySql.includes('union'), 'active bookings must annotate, never union into candidates');
assert(eligibilitySql.includes('existing_booking') && eligibilitySql.includes("status in('queued','planned','started','stoppage')"), 'active booking must be an annotation for unscheduled semantics');
assert(eligibilitySql.includes("in('PMB','YH','IT')") && eligibilitySql.includes("='IT' and v.eta_to_kewdale is null"), 'location and IT ETA rules must remain explicit');
assert(eligibilitySql.includes('workshop_require_booking_schedule_eligibility') && eligibilitySql.includes('select 1 from public.workshop_station_eligibility(v_target)'), 'same-station move/resize/bay mutations must recheck current canonical eligibility');
assert(!eligibilitySql.includes('v_target is distinct from v_current'), 'same-station booking mutations must not bypass canonical work authority');
const guardStart = sql.indexOf('create or replace function public.workshop_prevent_disabled_planner_booking_mutation()');
const guardEnd = sql.indexOf('create or replace function public.get_station_workshop_snapshot', guardStart);
const bookingGuard = sql.slice(guardStart, guardEnd);
assert(guardStart >= 0 && guardEnd > guardStart, 'migration 045 must replace and rebind the table-level booking mutation guard');
assert(bookingGuard.includes('workshop_station_eligibility(v_stage)') && bookingGuard.includes('create trigger workshop_bookings_planner_enabled_guard'), 'direct and cascade booking shifts must use current canonical eligibility');
assert(!bookingGuard.includes('v_eligible:=true'), 'same-station active bookings must not bypass current work-item authority');

const preview = sql.slice(sql.indexOf('create or replace function public.preview_legacy_stage_reconciliation'), sql.indexOf('create or replace function public.apply_legacy_stage_reconciliation'));
for (const classification of ['A_SAFE_CREATE','B_ACTIVE_BOOKING','C_COMPLETED_OR_OBSOLETE','D_AMBIGUOUS']) assert(preview.includes(classification), `preview missing ${classification}`);
assert(preview.includes('active_same_bookings>1') && preview.includes('booking_completion_markers'), 'conflicting booking evidence must fail into D');
assert(preview.includes('completed_items>0 and f.active_same_bookings>0') && preview.includes('completed_work_conflicts_with_active_booking'), 'completed work plus a live booking must be ambiguous');
assert(preview.includes('extensions.uuid_generate_v5'), 'work-item identity must be deterministic');
assert(!preview.includes('customer') && !preview.includes('notes'), 'preview must remain sanitized');

const apply = sql.slice(sql.indexOf('create or replace function public.apply_legacy_stage_reconciliation'), sql.indexOf('create or replace function public.rollback_legacy_stage_reconciliation'));
assert(apply.includes("classification='A_SAFE_CREATE'") && /on conflict\s*\(vehicle_id,work_key\) do nothing/.test(apply), 'apply must only create A rows and prevent duplicates');
assert(apply.includes('legacy_stage_reconciliation_receipts') && apply.includes('insert into public.audit_events') && apply.includes('legacy_pmb_stage_reconciliation_decision'), 'apply must persist one receipt decision audit plus any work-item audit');
for (const forbidden of ['delete from public.vehicle_work_items','update public.vehicles','update public.workshop_bookings','customer_name','notes=']) assert(!apply.toLowerCase().includes(forbidden.toLowerCase()), `apply contains forbidden mutation ${forbidden}`);
const rollback = sql.slice(sql.indexOf('create or replace function public.rollback_legacy_stage_reconciliation'), sql.indexOf('revoke all on function public.rollback_legacy_stage_reconciliation'));
assert(!/delete\s+from/i.test(rollback) && rollback.includes('set required=false'), 'rollback must be non-destructive');
assert(rollback.includes("(v_before->>'updated_at')::timestamptz<>r.work_item_updated_at"), 'rollback must refuse to overwrite post-reconciliation changes');
assert(sql.includes('enable row level security') && /revoke all on table public\.legacy_stage_reconciliation_receipts from public,\s*anon,\s*authenticated/.test(sql), 'receipts must be service-only');
assert(sql.includes('revoke all on function public.apply_legacy_stage_reconciliation') && sql.includes('revoke all on function public.rollback_legacy_stage_reconciliation'), 'reconciliation RPCs must not be browser callable');
assert(backup.includes('legacy_stage_reconciliation_receipts'), 'backup manifest must include receipts');
assert(backup.includes('number >= 45') && backup.includes('difference(MIGRATION_045_BACKUP_TABLES)'), 'pre-045 backup must work before receipt table exists and 045+ must require it');
const stationSnapshotSql = sql.slice(sql.indexOf('create or replace function public.get_station_workshop_snapshot'), sql.indexOf('create or replace function public.get_workshop_eligibility_snapshot'));
assert(stationSnapshotSql.includes("public.workshop_stage_code_for_work_key(wi.work_key)=v_stage"), 'station work_items child collection must be scoped to the selected station');
assert(stationSnapshotSql.includes("'requirements',(select") && stationSnapshotSql.includes('where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed'), 'station DTO must expose a separate sanitized canonical requirements list for the left-hand requirements column');
assert(!stationSnapshotSql.includes("'notes',wi.notes") && !stationSnapshotSql.includes("'customer_name'"), 'sanitized requirements DTO must not expose notes or customer data');
assert(planner.includes('Array.isArray(authority?.requirements)') && planner.includes('workshopSnapshotVehicleToPlannerRow(vehicle, displayWorkItems'), 'planner must render the server-authoritative requirements list, including Sublet, without using browser-local requirements');
const candidateHydration = app.slice(app.indexOf('function workshopEligibilityCandidateVehicle'), app.indexOf('function authoritativeWorkshopVehiclesForStage'));
assert(candidateHydration.includes('pmbJobs: { ...shared.pmbJobs }') && !candidateHydration.includes('local?.pmbJobs'), 'browser-local requirements must never survive canonical absence');
assert(!candidateHydration.includes('...(local || {})') && candidateHydration.includes("client: ''"), 'Control Board canonical hydration must not widen the sanitized DTO with local customer or note aliases');
assert(!planner.includes('...local') && planner.includes("customerName: vehicle.customer_name || ''") && planner.includes("notes: ''"), 'planner canonical hydration must retain only the approved authoritative customer name and discard local/note aliases');
const lifecycleSnapshot = lifecycle.slice(lifecycle.indexOf('create or replace function public.get_station_workshop_snapshot'), lifecycle.indexOf('revoke all on function public.get_station_workshop_snapshot'));
assert(lifecycleSnapshot.includes("'customer_name',v.customer_name") && !lifecycleSnapshot.includes("'notes',v.notes"), 'operator/admin station snapshot must expose customer name without widening to notes');
for (const script of [applyScript, reconcileScript]) {
  assert(script.includes('validate_release_backup') && script.includes("add_argument('--restore-schema',required=True)"), 'staging write scripts must require validated encrypted backup and isolated restore evidence');
  assert(script.includes('active_same_station_bookings') && script.includes('open_equivalent_work_items'), 'exact reconciliation guard must use the migration evidence vocabulary');
  assert(!script.includes('conflicting_booking_evidence'), 'exact reconciliation guard must use a reason code emitted by migration 045');
}
assert(applyScript.includes("version in('043','044','045')") && applyScript.includes("versions!=['044']"), 'apply gate must explicitly reject migration 043 and pre-existing 045');
assert(reconcileScript.includes("choices=('record','finalize')") && reconcileScript.includes("expected_migration='044' if a.phase=='record' else '045'"), 'reconciliation must require distinct pre-045 and post-045 backup gates');
assert(reconcileScript.includes("status':'pending_post_045_backup_restore'") && reconcileScript.includes("status':'reconciliation_finalized'"), 'record phase must not report final success before the post-045 restore proof');
assert(reconcileScript.includes('backup_finished<last_receipt'), 'post-045 backup must be newer than committed receipts');
assert(reconcileScript.includes('max(created_at)') && !reconcileScript.includes('max(applied_at)'), 'finalize must compare the real receipt creation timestamp column');
assert(!stagingHtml.includes('random-100-vehicles.csv'), 'zero-data staging Pages shell must not expose an undeployed CSV download');
assert(reconcileScript.includes('md5(to_jsonb(v)::text)') && reconcileScript.includes('md5(to_jsonb(wi)::text)') && reconcileScript.includes('md5(to_jsonb(b)::text)'), 'no-create gate must hash complete vehicle/work-item/booking rows');
assert(!reconcileScript.includes('customer_email') && !reconcileScript.includes('customer_phone'), 'no-create gate must not query nonexistent vehicle columns');
for (const gate of ['decrypt_backup','validate_backup_contract','PDC_BACKUP_ENCRYPTION_KEY','max_age_seconds','restore_test_runs','all_checks_passed','information_schema.schemata']) {
  assert(backupGate.includes(gate), `backup gate is missing ${gate}`);
}

assert(eligibility.includes("else if (!work.outstanding) reason") && !eligibility.includes('!work.outstanding && !activeBooking'), 'frontend candidate authority must require outstanding work');
const boardNeed = app.slice(app.indexOf('function pmbVehicleNeedsStationWork'), app.indexOf('function pmbVehiclesNeedingStationWork'));
assert(!boardNeed.includes('inferredPmbStage') && boardNeed.includes('pdcJobRequired'), 'browser-local Control Board fallback must not use pmb_stage');
const localPlanner = planner.slice(planner.indexOf('function workshopStageVehicles'), planner.indexOf('function workshopSnapshotVehicleToPlannerRow'));
assert(!localPlanner.includes('inferredPmbStage') && localPlanner.includes('pdcJobRequired'), 'browser-local planner fallback must not use pmb_stage');
assert(planner.includes('outstanding_candidates') && planner.includes('Outstanding candidates') && planner.includes('bookings on selected date') && planner.includes('unscheduled'), 'planner must expose the three count concepts');
assert(planner.includes('const queue = unscheduled;') && planner.includes('<strong>Outstanding candidates</strong><span>${queue.length}</span>'), 'already-booked vehicles must be removed from the actionable Outstanding candidates pile');
assert(planner.includes('Requirements:') && planner.includes('pdcRequirementDefinitions(vehicle)'), 'left candidate column must show canonical requirements, including Sublet');
assert(!planner.includes("path: 'workshop/sublet'") && !app.includes("view: 'planner-sublet'"), 'Sublet must remain planner-excluded');

console.log('Migration 045 canonical authority and reconciliation contract passed');
