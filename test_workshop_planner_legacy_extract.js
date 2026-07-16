'use strict';

const assert = require('assert');
const { extractWorkshopPlannerLegacyState } = require('./scripts/workshop_planner_legacy_extract');

const backup = {
  type: 'vehicle-tracking-core-backup',
  version: 1,
  exportedAt: '2026-07-16T09:30:00.000Z',
  storage: {
    'vehicleTrackingCoreWorkshopPlan:v1': JSON.stringify([
      {
        id: 'HOIST::STK-100',
        vehicleKey: 'STK-100',
        stage: 'HOIST',
        bay: 2,
        startAt: '2026-07-17T00:00:00.000Z',
        hours: 3,
        assignee: 'Alex',
        status: 'planned',
        createdAt: '2026-07-16T08:00:00.000Z',
        updatedAt: '2026-07-16T08:05:00.000Z'
      },
      {
        id: 'SUBLET::PO-200',
        vehicleKey: 'PO-200',
        stage: 'SUBLET',
        bay: 1,
        startAt: '2026-07-18T00:00:00.000Z',
        hours: 5,
        assignee: 'ARB',
        status: 'stoppage',
        stoppageReason: 'Waiting on parts',
        stoppageAt: '2026-07-18T02:00:00.000Z',
        stoppageMinutes: 45,
        updatedAt: '2026-07-18T02:05:00.000Z'
      }
    ]),
    'vehicleTrackingCoreWorkshopBaySetup:v1': JSON.stringify({
      'HOIST:2': 'Alex',
      'SUBLET:1': 'ARB'
    }),
    'vehicleTrackingCoreWorkshopView:v1': JSON.stringify({ date: '2026-07-17', stage: 'HOIST' }),
    'vehicleTrackingCorePdcMechanics:v1': JSON.stringify(['Alex', 'Jamie']),
    'vehicleTrackingCorePdcSubletProviders:v1': JSON.stringify(['ARB', 'PTE']),
    'vehicleTrackingCoreNavisionOnlyEdits:v1': JSON.stringify({
      'STK-100': {
        workshopEstimatedHoursByStage: { HOIST: 3 },
        pmbBayMechanic: 'Alex'
      },
      'PO-200': {
        pmbSubletProvider: 'ARB',
        pdcWorkshopBlocked: true,
        pdcWorkshopBlockReason: 'Waiting on parts'
      }
    })
  },
  vehicles: [
    { id: 'v1', stock: 'STK-100', order: 'TO-100', customer: 'Customer A', vehicle: 'Hilux' },
    { id: 'v2', stock: '', order: 'PO-200', customer: 'Customer B', vehicle: 'Ranger' }
  ]
};

const extracted = extractWorkshopPlannerLegacyState(backup);
assert.equal(extracted.reconciliation.booking_count, 2, 'Booking count should be preserved');
assert.equal(extracted.reconciliation.unmatched_vehicle_keys.length, 0, 'All booking vehicle keys should resolve');
assert.equal(extracted.planner_view_preference.stage, 'HOIST', 'Planner stage preference should be retained');
assert.equal(extracted.mechanics.length, 2, 'Mechanic roster should be extracted');
assert.equal(extracted.sublet_providers.length, 2, 'Provider list should be extracted');
assert.equal(extracted.bay_assignments.length, 2, 'Bay assignments should be extracted');
assert.equal(extracted.reconciliation.status_counts.planned, 1, 'Planned status count should be tracked');
assert.equal(extracted.reconciliation.status_counts.stoppage, 1, 'Stoppage status count should be tracked');
assert.equal(extracted.bookings[0].duration_minutes, 180, '3 hours should become 180 minutes');
assert.equal(extracted.bookings[1].vehicle_identity.order, 'PO-200', 'Order-based vehicle key should resolve when stock is blank');
assert.equal(extracted.bookings[1].workshop_vehicle_edit_snapshot.pdcWorkshopBlockReason, 'Waiting on parts', 'Workshop edit snapshot should be preserved');
assert.deepEqual(extracted.reconciliation.duplicate_bookings, [], 'No duplicate bookings in the clean fixture');
assert.deepEqual(extracted.reconciliation.conflicting_bookings, [], 'No conflicting bookings in the clean fixture');
assert.equal(extracted.reconciliation.stopped_booking_count, 1, 'Stoppage count reported in reconciliation');
assert.equal(extracted.reconciliation.completed_booking_count, 0, 'Completed count reported in reconciliation');
assert.equal(extracted.bookings[0].scheduled_end_at, new Date(new Date('2026-07-17T00:00:00.000Z').getTime() + 180 * 60000).toISOString(), 'scheduled_end_at is derived from start + duration');
assert.deepEqual(extracted.bookings[0].raw_legacy_record, {
  id: 'HOIST::STK-100',
  vehicleKey: 'STK-100',
  stage: 'HOIST',
  bay: 2,
  startAt: '2026-07-17T00:00:00.000Z',
  hours: 3,
  assignee: 'Alex',
  status: 'planned',
  createdAt: '2026-07-16T08:00:00.000Z',
  updatedAt: '2026-07-16T08:05:00.000Z'
}, 'raw_legacy_record preserves the original browser record byte-for-byte for audit/rollback');
assert.strictEqual(extracted.bookings[0].work_item_reference, null, 'work_item_reference is null (not guessed) when no source pointer exists');

console.log('Workshop planner legacy extraction checks passed');

// --- Duplicate / conflict / orphan detection (section-16 reconciliation) ---

const conflictBackup = {
  type: 'vehicle-tracking-core-backup',
  version: 1,
  exportedAt: '2026-07-16T09:30:00.000Z',
  storage: {
    'vehicleTrackingCoreWorkshopPlan:v1': JSON.stringify([
      {
        id: 'HOIST::STK-100::a',
        vehicleKey: 'STK-100',
        stage: 'HOIST',
        bay: 2,
        startAt: '2026-07-17T00:00:00.000Z',
        hours: 3,
        status: 'planned',
      },
      {
        // Same vehicle + stage as above -> duplicate booking
        id: 'HOIST::STK-100::b',
        vehicleKey: 'STK-100',
        stage: 'HOIST',
        bay: 2,
        startAt: '2026-07-20T00:00:00.000Z',
        hours: 3,
        status: 'planned',
      },
      {
        // Different vehicle, same bay, overlapping time window -> conflict
        id: 'HOIST::STK-200::c',
        vehicleKey: 'STK-200',
        stage: 'HOIST',
        bay: 2,
        startAt: '2026-07-17T01:00:00.000Z',
        hours: 3,
        status: 'started',
      },
    ]),
    'vehicleTrackingCoreWorkshopBaySetup:v1': JSON.stringify({
      'HOIST:2': 'Alex',
      'FITTING:1': 'Jamie', // no matching active booking -> orphaned
    }),
    'vehicleTrackingCoreWorkshopView:v1': JSON.stringify({}),
    'vehicleTrackingCorePdcMechanics:v1': JSON.stringify([]),
    'vehicleTrackingCorePdcSubletProviders:v1': JSON.stringify([]),
    'vehicleTrackingCoreNavisionOnlyEdits:v1': JSON.stringify({}),
  },
  vehicles: [
    { id: 'v1', stock: 'STK-100', order: '', customer: 'Customer A', vehicle: 'Hilux' },
    { id: 'v2', stock: 'STK-200', order: '', customer: 'Customer B', vehicle: 'Ranger' },
  ],
};

const conflictExtracted = extractWorkshopPlannerLegacyState(conflictBackup);
assert.equal(conflictExtracted.reconciliation.duplicate_bookings.length, 1, 'Duplicate same-vehicle-same-stage booking detected');
assert.deepEqual(
  conflictExtracted.reconciliation.duplicate_bookings[0].plan_ids.sort(),
  ['HOIST::STK-100::a', 'HOIST::STK-100::b'].sort(),
  'Duplicate detection reports both legacy plan ids'
);
assert.equal(conflictExtracted.reconciliation.conflicting_bookings.length, 1, 'Overlapping same-bay booking detected as a conflict');
assert.equal(conflictExtracted.reconciliation.orphaned_bay_assignments.length, 1, 'Bay assignment with no active booking flagged as orphaned');
assert.equal(conflictExtracted.reconciliation.orphaned_bay_assignments[0].stage_code, 'FITTING');
assert.ok(
  conflictExtracted.reconciliation.conflicts_requiring_manual_review >= 2,
  'Conflicts-requiring-manual-review rolls up duplicates + conflicts + unmatched keys'
);

console.log('Workshop planner legacy extraction conflict/duplicate/orphan detection checks passed');
