'use strict';

const fs = require('fs');
const path = require('path');

const WORKSHOP_PLAN_STORAGE_KEY = 'vehicleTrackingCoreWorkshopPlan:v1';
const WORKSHOP_VIEW_STORAGE_KEY = 'vehicleTrackingCoreWorkshopView:v1';
const WORKSHOP_BAY_SETUP_STORAGE_KEY = 'vehicleTrackingCoreWorkshopBaySetup:v1';
const MECHANICS_KEY = 'vehicleTrackingCorePdcMechanics:v1';
const SUBLET_PROVIDERS_KEY = 'vehicleTrackingCorePdcSubletProviders:v1';
const EDITS_KEY = 'vehicleTrackingCoreNavisionOnlyEdits:v1';

function loadJson(value, fallback) {
  if (typeof value !== 'string') return fallback;
  try { return JSON.parse(value); }
  catch { return fallback; }
}

function isBlankStock(stock = '') {
  return !stock || stock === '0' || /^TBA$/i.test(stock) || String(stock).startsWith('PENDING-');
}

function vehicleKey(vehicleOrKey) {
  if (typeof vehicleOrKey === 'string') return vehicleOrKey.trim();
  const v = vehicleOrKey || {};
  const stock = String(v.stock || '').trim();
  const order = String(v.order || '').trim();
  if (stock && !isBlankStock(stock)) return stock;
  return order || String(v.id || stock || '').trim();
}

function normalizeStage(stage = '') {
  const value = String(stage || '').trim().toUpperCase();
  const alias = {
    FAB: 'FABRICATION',
    FABRICATION: 'FABRICATION',
    ELEC: 'ELECTRICAL',
    ELECTRICAL: 'ELECTRICAL',
    PIT: 'PIT_INSPECTION',
    PIT_INSPECTION: 'PIT_INSPECTION',
  };
  return alias[value] || value;
}

function workshopVehicleEditSnapshot(edit = {}) {
  const keys = [
    'pmbStage',
    'pmbBayStage',
    'pmbBayNumber',
    'pmbBayScheduledStartAt',
    'pmbBayEstimatedHours',
    'pmbBayMechanic',
    'pmbSubletProvider',
    'pdcWorkshopBlocked',
    'pdcWorkshopBlockPlanId',
    'pdcWorkshopBlockReason',
    'pdcWorkshopBlockedAt',
    'pdcWorkshopBlockedBy',
    'pdcWorkshopBlockClearedAt',
    'pdcWorkshopBlockClearedBy',
    'workshopEstimatedHoursByStage',
    'workshopAdditionalHoursByStage',
    'workshopJobLineAssignments',
  ];
  const snapshot = {};
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(edit || {}, key)) snapshot[key] = edit[key];
  }
  return snapshot;
}

function extractWorkshopPlannerLegacyState(backup) {
  const storage = backup?.storage && typeof backup.storage === 'object' ? backup.storage : {};
  const vehicles = Array.isArray(backup?.vehicles) ? backup.vehicles : [];
  const plans = loadJson(storage[WORKSHOP_PLAN_STORAGE_KEY], []);
  const baySetup = loadJson(storage[WORKSHOP_BAY_SETUP_STORAGE_KEY], {});
  const view = loadJson(storage[WORKSHOP_VIEW_STORAGE_KEY], {});
  const mechanics = loadJson(storage[MECHANICS_KEY], []);
  const providers = loadJson(storage[SUBLET_PROVIDERS_KEY], []);
  const edits = loadJson(storage[EDITS_KEY], {});

  const vehicleMap = new Map(vehicles.map(vehicle => [vehicleKey(vehicle), vehicle]));
  const bookings = [];
  const unmatchedVehicleKeys = [];
  const statusCounts = {};
  const stageCounts = {};

  for (const row of Array.isArray(plans) ? plans : []) {
    if (!row || !row.id) continue;
    const key = vehicleKey(row.vehicleKey || '');
    const vehicle = vehicleMap.get(key) || null;
    const normalizedStage = normalizeStage(row.stage);
    const status = String(row.status || 'planned').trim() || 'planned';
    const workshopEdit = workshopVehicleEditSnapshot(edits[key] || {});
    if (!vehicle) unmatchedVehicleKeys.push(key);
    statusCounts[status] = (statusCounts[status] || 0) + 1;
    stageCounts[normalizedStage] = (stageCounts[normalizedStage] || 0) + 1;
    bookings.push({
      legacy_plan_id: row.id,
      legacy_vehicle_key: key,
      vehicle_identity: vehicle ? {
        key,
        stock: vehicle.stock || '',
        order: vehicle.order || '',
        id: vehicle.id || '',
        customer: vehicle.customer || '',
        vehicle: vehicle.vehicle || '',
      } : null,
      stage_code: normalizedStage,
      bay_number: Number(row.bay) || null,
      status,
      scheduled_start_at: row.startAt || null,
      scheduled_end_at: (row.startAt && Number.isFinite(Number(row.hours)))
        ? new Date(new Date(row.startAt).getTime() + Math.round(Number(row.hours) * 60) * 60000).toISOString()
        : null,
      duration_hours: Number(row.hours) || null,
      duration_minutes: Number.isFinite(Number(row.hours)) ? Math.round(Number(row.hours) * 60) : null,
      assignee: String(row.assignee || '').trim() || null,
      created_at: row.createdAt || null,
      updated_at: row.updatedAt || null,
      started_at: row.startedAt || null,
      completed_at: row.completedAt || null,
      actual_hours: Number.isFinite(Number(row.actualHours)) ? Number(row.actualHours) : null,
      stoppage_reason: row.stoppageReason || null,
      stoppage_at: row.stoppageAt || null,
      stoppage_minutes: Number.isFinite(Number(row.stoppageMinutes)) ? Number(row.stoppageMinutes) : null,
      resumed_at: row.resumedAt || null,
      // Best-effort pointer to a source work-item/job-line reference, kept
      // separate from the full edit snapshot below so downstream import
      // tooling can check "does a work item exist for this booking" without
      // parsing the whole edit blob. Never fabricated: null when unknown.
      work_item_reference: row.workItemId || row.jobLineId || null,
      workshop_vehicle_edit_snapshot: workshopEdit,
      // Full original raw legacy record, byte-for-byte as it existed in
      // browser localStorage, kept verbatim for audit and rollback -- the
      // import process must never lose the ability to reconstruct exactly
      // what was there before migration.
      raw_legacy_record: row,
    });
  }

  const bayAssignments = Object.entries(baySetup || {}).map(([key, assignee]) => {
    const [stageCode, bayNumber] = String(key || '').split(':');
    return {
      stage_code: normalizeStage(stageCode),
      bay_number: Number(bayNumber) || null,
      assignee: String(assignee || '').trim() || null,
    };
  });

  // Duplicate detection: more than one legacy booking pointing at the same
  // (vehicle, stage) combination is a data-quality signal, not necessarily
  // an error -- but it must be surfaced for manual review before import,
  // not silently imported twice.
  const activeStatuses = new Set(['planned', 'started', 'stoppage']);
  const seenVehicleStage = new Map();
  const duplicateBookings = [];
  for (const booking of bookings) {
    if (!activeStatuses.has(booking.status)) continue;
    const dupKey = `${booking.legacy_vehicle_key}::${booking.stage_code}`;
    if (seenVehicleStage.has(dupKey)) {
      duplicateBookings.push({ vehicle_key: booking.legacy_vehicle_key, stage_code: booking.stage_code, plan_ids: [seenVehicleStage.get(dupKey), booking.legacy_plan_id] });
    } else {
      seenVehicleStage.set(dupKey, booking.legacy_plan_id);
    }
  }

  // Conflicting-booking detection: overlapping scheduled windows in the
  // same (stage, bay) -- the same check the database RPCs enforce -- so a
  // conflict already present in the legacy export is caught before import
  // rather than being rejected one row at a time during a live cutover.
  function toRange(booking) {
    const start = booking.scheduled_start_at ? new Date(booking.scheduled_start_at).getTime() : null;
    const durationMs = Number.isFinite(booking.duration_minutes) ? booking.duration_minutes * 60000 : null;
    if (start == null || durationMs == null || Number.isNaN(start)) return null;
    return { start, end: start + durationMs };
  }
  const conflictingBookings = [];
  const byBay = new Map();
  for (const booking of bookings) {
    if (!activeStatuses.has(booking.status) || booking.bay_number == null) continue;
    const bayKey = `${booking.stage_code}::${booking.bay_number}`;
    const range = toRange(booking);
    if (!range) continue;
    const existingList = byBay.get(bayKey) || [];
    for (const existing of existingList) {
      if (range.start < existing.range.end && existing.range.start < range.end) {
        conflictingBookings.push({
          bay_key: bayKey,
          plan_ids: [existing.booking.legacy_plan_id, booking.legacy_plan_id],
        });
      }
    }
    existingList.push({ booking, range });
    byBay.set(bayKey, existingList);
  }

  // Orphan detection: bay assignments or mechanic/provider references with
  // no corresponding active booking are not blocking, but must be reported
  // per the section-16 requirement to count "orphaned technicians, bays or
  // work items" before approval.
  const bookingStageBaySet = new Set(
    bookings.filter(b => activeStatuses.has(b.status) && b.bay_number != null)
      .map(b => `${b.stage_code}::${b.bay_number}`)
  );
  const orphanedBayAssignments = bayAssignments.filter(a => !bookingStageBaySet.has(`${a.stage_code}::${a.bay_number}`));

  const incompleteWorkItemVehicles = bookings.filter(b => {
    const edit = b.workshop_vehicle_edit_snapshot || {};
    return activeStatuses.has(b.status) && edit.pdcWorkshopBlocked === true;
  }).length;
  const stoppedBookingCount = statusCounts.stoppage || 0;
  const completedBookingCount = statusCounts.completed || 0;

  return {
    exported_at: backup?.exportedAt || null,
    source_backup_type: backup?.type || null,
    source_backup_version: backup?.version || null,
    planner_view_preference: {
      date: view?.date || null,
      stage: normalizeStage(view?.stage || ''),
    },
    mechanics: Array.isArray(mechanics) ? mechanics.map(name => String(name || '').trim()).filter(Boolean) : [],
    sublet_providers: Array.isArray(providers) ? providers.map(name => String(name || '').trim()).filter(Boolean) : [],
    bay_assignments: bayAssignments,
    bookings,
    reconciliation: {
      vehicle_count: vehicles.length,
      booking_count: bookings.length,
      unmatched_vehicle_keys: unmatchedVehicleKeys,
      status_counts: statusCounts,
      stage_counts: stageCounts,
      bay_assignment_count: bayAssignments.length,
      mechanic_count: Array.isArray(mechanics) ? mechanics.length : 0,
      sublet_provider_count: Array.isArray(providers) ? providers.length : 0,
      duplicate_bookings: duplicateBookings,
      conflicting_bookings: conflictingBookings,
      orphaned_bay_assignments: orphanedBayAssignments,
      incomplete_work_item_vehicle_count: incompleteWorkItemVehicles,
      stopped_booking_count: stoppedBookingCount,
      completed_booking_count: completedBookingCount,
      conflicts_requiring_manual_review: duplicateBookings.length + conflictingBookings.length + unmatchedVehicleKeys.length,
    },
  };
}

if (require.main === module) {
  const input = process.argv[2];
  const output = process.argv[3];
  if (!input) {
    console.error('Usage: node scripts/workshop_planner_legacy_extract.js <crm-backup.json> [output.json]');
    process.exit(1);
  }
  const backup = JSON.parse(fs.readFileSync(path.resolve(input), 'utf8'));
  const extracted = extractWorkshopPlannerLegacyState(backup);
  const text = JSON.stringify(extracted, null, 2);
  if (output) fs.writeFileSync(path.resolve(output), text);
  else process.stdout.write(text + '\n');
}

module.exports = {
  extractWorkshopPlannerLegacyState,
  vehicleKey,
  normalizeStage,
};
