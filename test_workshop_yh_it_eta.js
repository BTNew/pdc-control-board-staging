'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

global.cleanNavisionText = value => String(value || '').trim();
global.vehiclePdcLocation = vehicle => vehicle.pdcLocation || vehicle.manualLocation || '';
global.statusCategory = vehicle => String(vehicle.pdcLocation || '').toUpperCase() === 'PMB' ? 'pmb' : 'other';
global.kewdaleEtaValue = vehicle => vehicle.kewdaleEta || '';
global.parseDateAU = value => {
  const match = String(value || '').match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!match) return null;
  const date = new Date(Number(match[3]), Number(match[2]) - 1, Number(match[1]));
  return date.getFullYear() === Number(match[3]) && date.getMonth() === Number(match[2]) - 1 && date.getDate() === Number(match[1]) ? date : null;
};
global.parseIsoTimestamp = value => { const date = new Date(value); return Number.isNaN(date.getTime()) ? null : date; };
global.vehicleKey = vehicle => vehicle.id;
global.displayStockNumber = vehicle => vehicle.stock || vehicle.id;
global.inferredPmbStage = vehicle => vehicle.stage || 'FABRICATION';
global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.pmbStageJobDef = stage => ({ code: stage });
global.pdcJobRequired = vehicle => vehicle.required !== false;
global.pdcJobComplete = vehicle => vehicle.complete === true;
global.app = { data: [] };
global.pmbVehiclesNeedingStationWork = () => global.app.data.filter(vehicle => vehicle.pdcLocation === 'PMB');
global.alert = () => {};
const planner = require('./workshop-planner.js');

const yh = { id: 'yh-1', stock: 'YH1', pdcLocation: 'YH', kewdaleEta: '21/07/2026', stage: 'FABRICATION' };
const it = { id: 'it-1', stock: 'IT1', pdcLocation: 'IT', kewdaleEta: '22/07/2026', stage: 'FABRICATION' };
const pmb = { id: 'pmb-1', stock: 'PMB1', pdcLocation: 'PMB', stage: 'FABRICATION', required: true, complete: false };
const pmbSublet = { id: 'pmb-sublet', stock: 'PMBS', pdcLocation: 'PMB', stage: 'SUBLET', pmbSubletProvider: 'Vendor' };
global.app.data = [yh, it, pmb];

assert.strictEqual(planner.workshopVehiclePlanningLocation(yh), 'YH');
assert.strictEqual(planner.workshopVehiclePlanningLocation(it), 'IT');
assert.deepStrictEqual(planner.workshopStageVehicles('FABRICATION').map(row => row.id), ['it-1', 'pmb-1', 'yh-1'], 'YH and IT vehicles with outstanding work must join the normal awaiting-schedule candidates');
global.app.data.push(pmbSublet);
assert.deepStrictEqual(planner.workshopStageVehicles('SUBLET').map(row => row.id), ['pmb-sublet'], 'PMB SUBLET vehicles must remain in the normal unallocated queue');

const exactEta = planner.workshopEtaScheduleValidation(yh, new Date(2026, 6, 21, 8, 0));
assert.strictEqual(exactEta.ok, true, 'Booking on ETA date must be allowed');
const afterEta = planner.workshopEtaScheduleValidation(yh, new Date(2026, 6, 22, 8, 0));
assert.strictEqual(afterEta.ok, true, 'Booking after ETA date must be allowed');
const beforeEta = planner.workshopEtaScheduleValidation(yh, new Date(2026, 6, 20, 8, 0));
assert.strictEqual(beforeEta.ok, false, 'Booking before ETA must fail closed');
assert.strictEqual(beforeEta.reason, 'before_eta');
assert.strictEqual(beforeEta.earliestDateKey, '2026-07-21', 'Before-ETA refusal must expose the earliest permitted date');

const blank = planner.workshopVehicleEtaConstraint({ ...yh, kewdaleEta: '' });
assert.strictEqual(blank.ok, false);
assert.strictEqual(blank.reason, 'missing_eta');
const invalid = planner.workshopVehicleEtaConstraint({ ...yh, kewdaleEta: '31/02/2026' });
assert.strictEqual(invalid.ok, false);
assert.strictEqual(invalid.reason, 'invalid_eta');

const existing = { id: 'booking-1', vehicleKey: yh.id, status: 'planned', startAt: new Date(2026, 6, 21, 8, 0).toISOString() };
assert.strictEqual(planner.workshopEtaRiskForEntry(existing, yh), null, 'Booking on current ETA must not be at risk');
const laterEtaVehicle = { ...yh, kewdaleEta: '23/07/2026' };
const risk = planner.workshopEtaRiskForEntry(existing, laterEtaVehicle);
assert.ok(risk && risk.reason === 'before_eta', 'Later ETA must flag the existing booking for review without moving or deleting it');
assert.strictEqual(existing.startAt, new Date(2026, 6, 21, 8, 0).toISOString(), 'Risk calculation must not move the booking');

const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
assert.ok(/bucketKey === 'yardhold'[\s\S]*data-yh-transfer-pmb[\s\S]*data-open-stock/.test(appSource), 'Every YH card must expose an Open action without transferring it');
assert.ok(appSource.includes('data-open-stock'), 'YH Open must use the same full vehicle-card route as other screens');

const plannerSource = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
assert.ok(plannerSource.includes('workshopRequireEtaSchedule(vehicle, start)'), 'All new schedule paths must enforce ETA before persistence');
assert.ok(plannerSource.includes('ETA RISK · earliest'), 'Existing bookings must render a review risk when ETA moves later');
const migration = fs.readFileSync(path.join(__dirname, 'supabase/migrations/038_combined_staging_dealer_scope_eta_planning.sql'), 'utf8');
assert.ok(migration.includes('v_vehicle.eta_to_kewdale'), 'Database enforcement must use the actual shared ETA column');
assert.ok(migration.includes('before insert or update of scheduled_start_at, vehicle_id'), 'Every booking insert/reschedule/vehicle reassignment must pass the ETA trigger');
assert.ok(migration.includes("in ('YH','IT')"), 'Database ETA enforcement must be limited to YH/IT planning locations');
assert.ok(migration.includes("eta_risk_status='at_risk'") || migration.includes("v_new_status:="), 'Later ETA changes must durably mark planned bookings at risk');
assert.ok(migration.includes("'eta_risk_changed'"), 'ETA risk transitions must retain booking-history audit evidence');
assert.ok(migration.includes('set search_path = pg_catalog, public, extensions'), 'Redefined scheduling RPC must retain hardened SECURITY DEFINER search path');
assert.ok(migration.includes("current_location = case when upper(btrim(coalesce(v_vehicle.current_location,''))) in ('YH','IT') then v_vehicle.current_location"), 'YH/IT scheduling must retain current location');
assert.ok(migration.includes('revoke all on function public.workshop_enforce_vehicle_eta()'), 'Trigger helpers must not be directly executable by authenticated clients');
console.log('Workshop YH/IT ETA regression: 30 assertions passed.');
