const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const PMB_STAGE_BAY_COUNTS = {
  TINT: 2,
  HOIST: 3,
  FITTING: 5,
  FABRICATION: 13,
  ELECTRICAL: 10,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

function loadVehicleData(file) {
  const context = { window: {} };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(file, 'utf8'), context, { filename: file });
  return context.window.VEHICLE_TRACKING_DATA;
}

function vehicleKey(vehicle) {
  return String(vehicle.stock || vehicle.batch || vehicle.toyotaBatch || vehicle.id || '').trim();
}

function activePmbVehicle(vehicle) {
  const stage = String(vehicle.pmbStage || '').trim().toUpperCase();
  const location = String(vehicle.pdcLocation || vehicle.pdcStatus || vehicle.manualLocation || '').trim().toUpperCase();
  const completed = Boolean(vehicle.rftCollected || vehicle.rftCollectedAt || vehicle.completedVehicle);
  return Boolean(stage) && location !== 'RFT' && !completed;
}

function checkPmbBayIntegrity(file) {
  const data = loadVehicleData(file);
  assert(data && Array.isArray(data.vehicles), `${file} did not expose VEHICLE_TRACKING_DATA.vehicles`);
  const occupied = new Map();
  for (const vehicle of data.vehicles) {
    if (!activePmbVehicle(vehicle)) continue;
    const stage = String(vehicle.pmbStage || '').trim().toUpperCase();
    const bayRaw = String(vehicle.pmbBayNumber || '').trim();
    if (!bayRaw) continue;
    assert(Object.prototype.hasOwnProperty.call(PMB_STAGE_BAY_COUNTS, stage), `${file}: unknown PMB stage ${stage} on ${vehicleKey(vehicle)}`);
    const bay = String(Number.parseInt(bayRaw, 10)).padStart(2, '0');
    assert(/^\d+$/.test(bayRaw) && Number(bay) >= 1 && Number(bay) <= PMB_STAGE_BAY_COUNTS[stage], `${file}: ${vehicleKey(vehicle)} assigned to ${stage} Bay ${bayRaw}, outside capacity ${PMB_STAGE_BAY_COUNTS[stage]}`);
    const key = `${stage}:${bay}`;
    assert(!occupied.has(key), `${file}: duplicate active PMB bay ${stage} Bay ${bay}: ${occupied.get(key)} and ${vehicleKey(vehicle)}`);
    occupied.set(key, vehicleKey(vehicle));
  }
}

for (const file of ['data.js', 'data-test-50.js', 'data-test-75.js', 'data-test-100.js']) {
  checkPmbBayIntegrity(file);
}

console.log('Data integrity checks passed');
