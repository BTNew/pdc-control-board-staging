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
      workshop_vehicle_edit_snapshot: workshopEdit,
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
