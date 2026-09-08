'use strict';

const assert = require('assert');
const fs = require('fs');

global.window = {
  PDC_SUPABASE_CONFIG: { enabled: true },
  workshopSharedModeEnabled: () => true,
  __activeWorkshopPlannerStage: 'FITTING',
  addEventListener: () => {},
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.vehicleKey = vehicle => vehicle.vehicleKey || vehicle.stockNumber || vehicle.stock_number || vehicle.id;
global.displayStockNumber = vehicle => vehicle.stockNumber || vehicle.stock_number || '';
global.vehicleJobcardNumber = vehicle => vehicle.jobCardNumber || vehicle.job_card_number || '';
global.vehicleCustomerName = vehicle => vehicle.customerName || vehicle.customer_name || '';
global.displayVehicle = vehicle => vehicle.model || '';
global.isPdcBlocked = () => false;
global.canonicalVehicleWorkState = () => ({ state: 'required' });
global.partsJobDef = () => ({ key: 'parts' });
global.pmbBayHours = () => 0;
global.pmbStageBayCount = () => 5;
global.pmbStageLabel = value => value;
global.escapeHtml = value => String(value);
global.statusCategory = () => 'pmb';
global.app = { data: [] };

const snapshot = {
  vehicles: [{
    id: '11111111-1111-4111-8111-111111111111',
    stock_number: '12705177',
    job_card_number: 'JC139123733',
    customer_name: 'MASSUDA',
    model: 'KDJ 150',
    current_location: 'IT',
    eta_to_kewdale: '2026-09-02',
    version: 17,
  }],
  work_items: [{
    vehicle_id: '11111111-1111-4111-8111-111111111111',
    work_key: 'fitting',
    required: true,
    completed: false,
  }],
  outstanding_candidates: [{
    vehicle_id: '11111111-1111-4111-8111-111111111111',
    stage_code: 'FITTING',
    existing_booking: false,
    schedule_enabled: true,
    disabled_reason: null,
    estimated_hours: 2.25,
    requirements: [],
  }],
  bookings: [],
};
window.__workshopDataService = {
  isEnabled: () => true,
  getLastSnapshot: () => snapshot,
  getTrustedSnapshot: () => snapshot,
};

const planner = require('./workshop-planner.js');
assert.ok(planner.workshopSharedModeActive(), 'fixture must execute the shared Workshop path');
assert.strictEqual(window.__workshopDataService.getLastSnapshot().vehicles[0].stock_number, '12705177');
const vehicle = planner.workshopVehicle('12705177', 'FITTING');
assert.ok(vehicle, 'the action path must resolve the exact scoped vehicle');

assert.deepStrictEqual(vehicle.workshopEstimatedHoursByStage, { FITTING: 2.25 },
  'the action-path vehicle must carry the same authoritative candidate duration as the rendered lane');
assert.strictEqual(planner.workshopCalculatedStageHours(vehicle, 'FITTING'), 2.25,
  'manual Schedule, drag and Best slot must resolve the server-authoritative 135 minutes');
assert.strictEqual(Math.round(planner.workshopCalculatedStageHours(vehicle, 'FITTING') * 60), 135,
  'the payload duration must equal the server expected_minutes=135');
assert.strictEqual(planner.workshopQueueEstimatedLabel(vehicle, 'FITTING'), '2.25h',
  'the card must truthfully display the authoritative duration even when scoped operation rows are omitted');

const appSource = fs.readFileSync('app.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
assert.ok(appSource.includes("const WORKSHOP_PLANNER_SCRIPT_VERSION = '2026.09.08.02-fitting-authoritative-duration';"),
  'the repaired planner must use a fresh dynamic-script cache identity');
assert.ok(indexSource.includes('fitting-duration=2026.09.08.02'),
  'the repaired app shell must use a fresh cache identity');

console.log('workshop fitting authoritative duration regression: PASS');
