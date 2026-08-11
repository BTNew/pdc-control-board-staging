'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.escapeHtml = value => String(value == null ? '' : value);
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.pmbStageLabel = value => String(value || '');
global.pmbJobDefForStage = () => ({ key: 'fitting' });

const planner = require('./workshop-planner.js');
const root = __dirname;
const plannerSource = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '152_planner_chip_operation_estimated_hours.sql'), 'utf8');
const remediationSql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '153_planner_operation_estimate_release_review_remediation.sql'), 'utf8');

assert(plannerSource.includes('defaultBookingDurationMinutes: 60'), 'three-hour boot default must be removed');
assert(!plannerSource.includes('defaultBookingDurationMinutes: 3 * 60'), 'three-hour test default must not remain');

const booking = {
  booking_id: 'booking-1',
  vehicle_id: 'vehicle-1',
  stage: { code: 'FITTING' },
  bay: { id: 'bay-1', bay_number: 1 },
  status: 'planned',
  scheduled_start_at: '2026-08-11T00:30:00Z',
  default_duration_minutes: 180,
  estimated_operation_hours: 6.5,
  version: 1,
};
const mapped = planner.workshopMapSnapshotBookingToLegacyRow(booking, new Map([
  ['vehicle-1', { id: 'vehicle-1', stock_number: '12661296' }],
]));
assert.strictEqual(mapped.hours, 6.5, 'Stock 12661296 chip must use its 6.5-hour fitting estimate, not stored 3-hour fallback');
assert.strictEqual(planner.workshopEntryEnd(mapped).getTime() - planner.workshopEntryStart(mapped).getTime(), 6.5 * 60 * 60 * 1000, '6.5-hour chip must span 6.5 working hours when no break intervenes');

const fallback = planner.workshopMapSnapshotBookingToLegacyRow({ ...booking, booking_id: 'booking-2', estimated_operation_hours: null }, new Map([
  ['vehicle-1', { id: 'vehicle-1', stock_number: '12661296' }],
]));
assert.strictEqual(fallback.hours, 3, 'an existing booking may retain its stored duration only when no authoritative estimate exists');

const vehicle = planner.workshopSnapshotVehicleToPlannerRow({
  id: 'vehicle-1',
  stock_number: '12661296',
  workshop_estimated_hours_by_stage: { FITTING: 6.5 },
  version: 1,
}, [{ vehicle_id: 'vehicle-1', work_key: 'fitting', required: true, completed: false }], 'FITTING');
assert.deepStrictEqual(vehicle.workshopEstimatedHoursByStage, { FITTING: 6.5 }, 'unscheduled vehicle must carry the authoritative stage estimate into scheduling');

assert(sql.includes("'estimated_operation_hours',public.workshop_vehicle_stage_estimated_hours(b.vehicle_id,s.code)"), 'booking DTO must expose authoritative operation estimate');
assert(sql.includes("'estimated_hours',public.workshop_vehicle_stage_estimated_hours(e.vehicle_id,v_stage)"), 'outstanding candidates must expose authoritative operation estimate');
assert(sql.includes("'workshop_estimated_hours_by_stage',jsonb_build_object(v_stage,public.workshop_vehicle_stage_estimated_hours(v.id,v_stage))"), 'snapshot vehicles must expose stage estimate map');
assert(sql.includes("set value=to_jsonb(60)"), 'shared three-hour fallback setting must be removed');
assert(sql.includes("a.line_key='source:'||ol.operation_line_id::text"), 'estimate must bind by immutable source operation-line identity');
assert(!remediationSql.includes('partition by ol.vehicle_id,ol.operation_no'), 'repeated OP numbers from separate job cards must not be collapsed');
assert(remediationSql.includes('operation_line_id is the immutable identity'), 'current source semantics must preserve Migration 107 durable source-line identity');
assert(remediationSql.includes("perform public.require_pdc_role(''viewer'');"), 'station snapshots must preserve Viewer read access');
assert(remediationSql.includes("'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage')"), 'all active chip DTOs must use the same estimate-driven interval; completed/cancelled history retains its persisted interval');
assert(remediationSql.includes('workshop_booking_effective_end_at'), 'snapshot, validation and cascade must share an effective operation-estimate end');
assert(remediationSql.includes('v_candidate_end'), 'candidate bay, vehicle, technician and leave checks must use the same effective interval');
assert(remediationSql.includes("'public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)'"), 'start lifecycle must persist the effective estimate duration before status transition');
assert(remediationSql.includes('pdc_operation_line_booking_duration_sync') && remediationSql.includes('workshop_adjustment_booking_duration_sync'), 'operation estimate mutations must reconcile persisted booking and assignment intervals in the same transaction');
assert(remediationSql.includes("'workshop-bay:'") && remediationSql.includes("'workshop-technician:'"), 'estimate reconciliation must use scheduler bay and technician lock namespaces');
assert(remediationSql.includes('operation_estimate_duration_mismatch'), 'direct scheduler RPCs must reject a duration that disagrees with an authoritative estimate');
assert(remediationSql.includes("('152','planner_chip_operation_estimated_hours'"), 'review remediation must close the previously omitted Migration 152 ledger row');
assert(remediationSql.includes("('153','planner_operation_estimate_release_review_remediation'"), 'review remediation must record Migration 153');

console.log('Operation-estimate planner chip contract passed');
