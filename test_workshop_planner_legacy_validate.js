'use strict';

const assert = require('assert');
const { validateLegacyImport } = require('./scripts/workshop_planner_legacy_validate');

function baseReference() {
  return {
    vehicles: [
      { id: 'veh-1', stock_number: 'STK-100', permanent_vehicle_id: 'perm-1' },
      { id: 'veh-2', stock_number: 'STK-200', permanent_vehicle_id: 'perm-2' },
      // Duplicate stock number on purpose, to exercise duplicate_vehicle_match
      { id: 'veh-2b', stock_number: 'STK-200', permanent_vehicle_id: 'perm-2b' },
    ],
    stages: [
      { id: 'stage-hoist', code: 'HOIST' },
      { id: 'stage-fitting', code: 'FITTING' },
    ],
    bays: [
      { id: 'bay-hoist-1', stage_id: 'stage-hoist', bay_number: 1 },
      { id: 'bay-hoist-2', stage_id: 'stage-hoist', bay_number: 2 },
    ],
    technicians: [
      { id: 'tech-alex', name: 'Alex' },
    ],
    workItems: [],
    requireWorkItemForStages: ['FITTING'],
  };
}

function extractWith(bookings) {
  return { bookings };
}

// 1. A fully clean booking is safely_matched
{
  const extract = extractWith([{
    legacy_plan_id: 'p1', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180, assignee: 'Alex',
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.safely_matched, 1, '1a clean booking is safely matched');
  assert.strictEqual(report.buckets.safely_matched[0].resolved.vehicle_id, 'veh-1', '1b resolves to the correct vehicle id');
  assert.strictEqual(report.buckets.safely_matched[0].resolved.bay_id, 'bay-hoist-1', '1c resolves to the correct bay id');
  assert.strictEqual(report.buckets.safely_matched[0].resolved.technician_id, 'tech-alex', '1d resolves to the correct technician id');
  console.log('PASS 1: clean booking classified as safely_matched with correct resolved ids');
}

// 2. Missing vehicle
{
  const extract = extractWith([{
    legacy_plan_id: 'p2', legacy_vehicle_key: 'STK-999', stage_code: 'HOIST', bay_number: 1,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180,
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.missing_vehicle, 1, '2a unmatched vehicle key routed to missing_vehicle');
  assert.strictEqual(report.counts.safely_matched, 0, '2b not also counted as safely matched');
  console.log('PASS 2: missing vehicle detected, never silently imported');
}

// 3. Duplicate vehicle match
{
  const extract = extractWith([{
    legacy_plan_id: 'p3', legacy_vehicle_key: 'STK-200', stage_code: 'HOIST', bay_number: 1,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180,
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.duplicate_vehicle_match, 1, '3a duplicate stock number routed to duplicate_vehicle_match');
  console.log('PASS 3: duplicate vehicle match detected, never guessed');
}

// 4. Missing bay (valid stage, invalid bay number)
{
  const extract = extractWith([{
    legacy_plan_id: 'p4', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 99,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180,
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.missing_bay, 1, '4a nonexistent bay number routed to missing_bay');
  console.log('PASS 4: missing bay detected');
}

// 5. Missing technician
{
  const extract = extractWith([{
    legacy_plan_id: 'p5', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180, assignee: 'Nobody',
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.missing_technician, 1, '5a unmatched assignee name routed to missing_technician');
  console.log('PASS 5: missing technician detected');
}

// 6. Missing work item (stage requires one, vehicle has none)
{
  const extract = extractWith([{
    legacy_plan_id: 'p6', legacy_vehicle_key: 'STK-100', stage_code: 'FITTING', bay_number: null,
    status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180,
  }]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.missing_work_item, 1, '6a stage requiring a work item with none present is flagged');
  console.log('PASS 6: missing work item detected for a stage that requires one');
}

// 7. Invalid date / duration
{
  const extract = extractWith([
    { legacy_plan_id: 'p7a', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: 'not-a-date', duration_minutes: 180 },
    { legacy_plan_id: 'p7b', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 0 },
    { legacy_plan_id: 'p7c', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: -30 },
  ]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.invalid_date_or_duration, 3, '7a unparsable date, zero duration, and negative duration all rejected');
  console.log('PASS 7: invalid dates/durations rejected, never coerced to a guess');
}

// 8. Overlapping bay booking (two otherwise-valid bookings, same bay, overlapping time)
{
  const extract = extractWith([
    { legacy_plan_id: 'p8a', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180 },
    { legacy_plan_id: 'p8b', legacy_vehicle_key: 'STK-200', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: '2026-07-20T01:00:00.000Z', duration_minutes: 180 },
  ]);
  // STK-200 is intentionally ambiguous in baseReference(); use a fresh single-match reference for this test
  const ref = baseReference();
  ref.vehicles = ref.vehicles.filter(v => v.id !== 'veh-2b');
  const report = validateLegacyImport(extract, ref);
  assert.strictEqual(report.counts.overlapping_bay_booking, 2, '8a both overlapping records flagged, not just one');
  assert.strictEqual(report.counts.safely_matched, 0, '8b neither overlapping record is silently imported');
  console.log('PASS 8: overlapping same-bay bookings are both flagged, none silently imported');
}

// 9. Overlapping technician booking
{
  const ref = baseReference();
  ref.vehicles = ref.vehicles.filter(v => v.id !== 'veh-2b');
  const extract = extractWith([
    { legacy_plan_id: 'p9a', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'planned', scheduled_start_at: '2026-07-20T00:00:00.000Z', duration_minutes: 180, assignee: 'Alex' },
    { legacy_plan_id: 'p9b', legacy_vehicle_key: 'STK-200', stage_code: 'HOIST', bay_number: 2, status: 'planned', scheduled_start_at: '2026-07-20T01:00:00.000Z', duration_minutes: 180, assignee: 'Alex' },
  ]);
  const report = validateLegacyImport(extract, ref);
  assert.strictEqual(report.counts.overlapping_technician_booking, 2, '9a same technician, overlapping windows, different bays -- still both flagged');
  console.log('PASS 9: overlapping same-technician bookings (different bays) are flagged');
}

// 10. Completed/stopped bookings always route to requires_manual_review even if otherwise clean
{
  const extract = extractWith([
    { legacy_plan_id: 'p10a', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 1, status: 'completed', scheduled_start_at: '2026-07-10T00:00:00.000Z', duration_minutes: 180 },
    { legacy_plan_id: 'p10b', legacy_vehicle_key: 'STK-100', stage_code: 'HOIST', bay_number: 2, status: 'stoppage', scheduled_start_at: '2026-07-11T00:00:00.000Z', duration_minutes: 180 },
  ]);
  const report = validateLegacyImport(extract, baseReference());
  assert.strictEqual(report.counts.requires_manual_review, 2, '10a completed and stoppage bookings both routed to manual review');
  assert.strictEqual(report.counts.safely_matched, 0, '10b never auto-imported despite passing every other check');
  console.log('PASS 10: completed/stopped bookings always require manual review regardless of other checks passing');
}

// 11. No booking is silently dropped: every legacy booking appears in at least one bucket
{
  const extract = extractWith([
    { legacy_plan_id: 'q1', legacy_vehicle_key: 'STK-999', stage_code: 'UNKNOWN_STAGE', bay_number: 1, status: 'planned', scheduled_start_at: 'garbage', duration_minutes: -1 },
  ]);
  const report = validateLegacyImport(extract, baseReference());
  const appearsSomewhere = Object.values(report.buckets).some(list => list.some(item => item.booking.legacy_plan_id === 'q1'));
  assert.ok(appearsSomewhere, '11a a maximally broken record still appears in at least one bucket, never silently vanishes');
  console.log('PASS 11: a maximally invalid record is still classified, never silently dropped');
}

console.log('Workshop legacy import validation checks passed');
