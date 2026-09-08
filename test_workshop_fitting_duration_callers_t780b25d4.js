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
global.partsDepartmentStatus = () => 'notordered';
global.partsDepartmentStatusLabel = () => 'Not Ordered';
global.partsWorstEtaLabel = () => '';
global.partsWorstEtaCountdownLabel = () => '';
global.pmbBayHours = () => 0;
global.pmbStageBayCount = () => 5;
global.pmbStageLabel = value => value;
global.escapeHtml = value => String(value);
global.statusCategory = () => 'pmb';
global.kewdaleEtaValue = vehicle => vehicle.navisionKewdaleEta || vehicle.etaAtKewdale || '';
global.parseDateAU = value => {
  const match = String(value || '').match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  return match ? new Date(Number(match[3]), Number(match[2]) - 1, Number(match[1])) : null;
};
global.parseIsoTimestamp = value => {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};
global.app = { data: [], workshopPlanner: { date: '2026-09-09', stage: 'FITTING' } };

const candidates = [
  { stock: '12705177', id: '11111111-1111-4111-8111-111111111111', hours: 2.25, minutes: 135, location: 'IT', eta: '2026-09-01' },
  { stock: '13007660', id: '22222222-2222-4222-8222-222222222222', hours: 1.5, minutes: 90, location: 'YH', eta: null },
];
const snapshot = {
  vehicles: candidates.map(row => ({
    id: row.id,
    stock_number: row.stock,
    job_card_number: `JC-${row.stock}`,
    customer_name: 'Fixture',
    model: 'Fixture vehicle',
    current_location: row.location,
    eta_to_kewdale: row.eta,
    version: 3,
  })),
  work_items: candidates.map(row => ({ vehicle_id: row.id, work_key: 'fitting', required: true, completed: false })),
  outstanding_candidates: candidates.map(row => ({
    vehicle_id: row.id,
    stage_code: 'FITTING',
    existing_booking: false,
    schedule_enabled: true,
    disabled_reason: null,
    estimated_hours: row.hours,
    requirements: [],
  })),
  bookings: [],
};
window.__workshopDataService = {
  isEnabled: () => true,
  getLastSnapshot: () => snapshot,
  getTrustedSnapshot: () => snapshot,
};

const planner = require('./workshop-planner.js');
assert.strictEqual(typeof planner.workshopSchedulingDuration, 'function',
  'one shared duration resolver must own card, Best slot, Schedule and drag payloads');

for (const fixture of candidates) {
  const vehicle = planner.workshopVehicle(fixture.stock, 'FITTING');
  const duration = planner.workshopSchedulingDuration(vehicle, 'FITTING');
  assert.deepStrictEqual(duration, { hours: fixture.hours, minutes: fixture.minutes });
  const html = planner.workshopQueueCardHtml(vehicle, 'FITTING', '2026-09-09', []);
  assert.match(html, new RegExp(`Estimated: ${fixture.hours.toFixed(2)}h`));
  assert.match(html, new RegExp(`data-workshop-best-slot-hours="${fixture.hours}"`));
  assert.doesNotMatch(html, /Estimated: Hours unknown/);
}

const unknown = { ...planner.workshopVehicle('13007660', 'FITTING'), workshopEstimatedHoursByStage: {} };
assert.strictEqual(planner.workshopSchedulingDuration(unknown, 'FITTING'), null,
  'shared mode must never replace unknown authoritative duration with a fake default');
const unknownHtml = planner.workshopQueueCardHtml(unknown, 'FITTING', '2026-09-09', []);
assert.match(unknownHtml, /Estimated: Hours unknown/);
assert.match(unknownHtml, /Scheduling unavailable/);
assert.doesNotMatch(unknownHtml, /data-workshop-best-slot-vehicle/);

const source = fs.readFileSync('workshop-planner.js', 'utf8');
for (const caller of [
  'workshopQueueCardHtml',
  'openWorkshopScheduleModal',
  'workshopScheduleVehicleNextAvailable',
  'scheduleWorkshopVehicle',
]) {
  const start = source.indexOf(`function ${caller}`);
  assert.ok(start >= 0, `${caller} must exist`);
  const next = source.indexOf('\nfunction ', start + 10);
  const body = source.slice(start, next < 0 ? source.length : next);
  assert.match(body, /workshopSchedulingDuration\(/,
    `${caller} must resolve the same authoritative duration contract`);
}
assert.match(source.slice(source.indexOf('function bindWorkshopPlanner'), source.indexOf('function bindWorkshopLane')),
  /workshopSchedulingDuration\(/,
  'queue pointer/native drag previews must resolve the same authoritative duration contract');

assert.ok(fs.existsSync('deployment-manifest.json'), 'a no-store deployment identity must exist for stale-tab detection');
const manifest = JSON.parse(fs.readFileSync('deployment-manifest.json', 'utf8'));
assert.strictEqual(manifest.workshopPlannerVersion, '2026.09.09.03-fitting-duration-coherence');
assert.match(source, /deployment-manifest\.json/);
assert.match(source, /cache:\s*'no-store'/);
assert.match(source, /visibilitychange/);
assert.match(source, /location\.replace/);

console.log('workshop Fitting duration caller/cache-coherence regression: PASS');
