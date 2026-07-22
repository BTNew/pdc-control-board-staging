'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const sql = read('supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql');
const app = read('app.js');
const planner = read('workshop-planner.js');
const eligibility = read('workshop-eligibility.js');
const backup = read('scripts/pdc_backup.py');

const eligibilitySql = sql.slice(sql.indexOf('create or replace function public.workshop_station_eligibility'), sql.indexOf('create or replace function public.get_station_workshop_snapshot'));
assert(eligibilitySql.includes('from public.vehicle_work_items wi') && eligibilitySql.includes('wi.required and not wi.completed'), 'outstanding work item must be the sole candidate authority');
assert(!eligibilitySql.includes('v.pmb_stage') && !eligibilitySql.includes('workshop_canonical_stage_code(v.pmb_stage)'), 'legacy pmb_stage must not participate in eligibility');
assert(!eligibilitySql.includes('union'), 'active bookings must annotate, never union into candidates');
assert(eligibilitySql.includes('existing_booking') && eligibilitySql.includes("status in('queued','planned','started','stoppage')"), 'active booking must be an annotation for unscheduled semantics');
assert(eligibilitySql.includes("in('PMB','YH','IT')") && eligibilitySql.includes("='IT' and v.eta_to_kewdale is null"), 'location and IT ETA rules must remain explicit');

const preview = sql.slice(sql.indexOf('create or replace function public.preview_legacy_stage_reconciliation'), sql.indexOf('create or replace function public.apply_legacy_stage_reconciliation'));
for (const classification of ['A_SAFE_CREATE','B_ACTIVE_BOOKING','C_COMPLETED_OR_OBSOLETE','D_AMBIGUOUS']) assert(preview.includes(classification), `preview missing ${classification}`);
assert(preview.includes('active_same_bookings>1') && preview.includes('booking_completion_markers'), 'conflicting booking evidence must fail into D');
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

assert(eligibility.includes("else if (!work.outstanding) reason") && !eligibility.includes('!work.outstanding && !activeBooking'), 'frontend candidate authority must require outstanding work');
const boardNeed = app.slice(app.indexOf('function pmbVehicleNeedsStationWork'), app.indexOf('function pmbVehiclesNeedingStationWork'));
assert(!boardNeed.includes('inferredPmbStage') && boardNeed.includes('pdcJobRequired'), 'browser-local Control Board fallback must not use pmb_stage');
const localPlanner = planner.slice(planner.indexOf('function workshopStageVehicles'), planner.indexOf('function workshopSnapshotVehicleToPlannerRow'));
assert(!localPlanner.includes('inferredPmbStage') && localPlanner.includes('pdcJobRequired'), 'browser-local planner fallback must not use pmb_stage');
assert(planner.includes('outstanding_candidates') && planner.includes('Outstanding candidates') && planner.includes('bookings on selected date') && planner.includes('unscheduled'), 'planner must expose the three count concepts');
assert(planner.includes('Active booking exists · shown here because the requirement remains outstanding') && planner.includes("pmbJobs: { ...scoped.pmbJobs }"), 'booked outstanding candidates must stay discoverable without local override');
assert(planner.includes('Requirements:') && planner.includes('pdcRequirementDefinitions(vehicle)'), 'left candidate column must show canonical requirements, including Sublet');
assert(!planner.includes("path: 'workshop/sublet'") && !app.includes("view: 'planner-sublet'"), 'Sublet must remain planner-excluded');

console.log('Migration 045 canonical authority and reconciliation contract passed');
