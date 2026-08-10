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

console.log('Operation-estimate planner chip contract passed');
