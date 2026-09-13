'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const plannerPath = path.resolve(__dirname, '../../workshop-planner.js');
const localRequire = createRequire(plannerPath);

// Execute the complete browser planner with deterministic shared reference data.
// There is no DOM, network, timer, storage or database mutation in this fixture.
function createSlotRuntime(source = fs.readFileSync(plannerPath, 'utf8')) {
  const row = value => ({ value, version: 1 });
  const config = {
    day_start_time: row('07:00'), day_end_time: row('17:00'),
    scheduling_increment_minutes: row(15), default_booking_duration_minutes: row(60),
    working_week: row(['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']),
    closures: row([]), overtime_windows: row([]), technician_leave: row([]),
    break_windows: row([
      { day: 'saturday', start: '07:00', end: '08:00' },
      { day: 'saturday', start: '12:00', end: '17:00' },
    ]),
  };
  const technicians = [{ id: 'tech-a', name: 'Mechanic A', active: true }, { id: 'tech-b', name: 'Mechanic B', active: true }];
  const bays = [1, 2].map(bay => ({ id: `bay-${bay}`, code: `FITTING-BAY-0${bay}`, is_active: true, default_technician_id: null }));
  const snapshot = { bookings: [], admin_blocks: [], vehicles: [] };
  const context = vm.createContext({
    module: { exports: {} }, require: localRequire, Date, console,
    parseIsoTimestamp: value => { const date = new Date(value); return Number.isNaN(+date) ? null : date; },
    cleanNavisionText: value => String(value ?? '').trim(),
    normalizePmbStage: value => localRequire('./workshop-eligibility.js').canonicalWorkshopStage(value),
    pmbStageBayCount: () => bays.length,
    window: {
      addEventListener: () => {},
      PDC_VEHICLE_HANDOVER: localRequire('./pdc-vehicle-handover.js'),
      workshopSharedModeEnabled: () => true,
      __workshopDataService: { isEnabled: () => true, getTrustedSnapshot: () => snapshot, getLastSnapshot: () => snapshot },
      __workshopReferenceDataService: {
        getCachedWorkshopConfiguration: () => ({ state: 'connected_read_only', rows: config }),
        getCachedWorkshopBays: () => ({ state: 'connected_read_only', rows: bays }),
        getCachedTechnicians: () => ({ state: 'connected_read_only', rows: technicians }),
      },
    },
  });
  vm.runInContext(source, context, { filename: plannerPath });
  return { planner: context.module.exports, context, config, technicians, bays, snapshot };
}

const at = (day, hour = 7, minute = 0) => new Date(2026, 8, day, hour, minute);
const booking = (day, hour = 7, hours = 1, extra = {}) => ({
  id: 'existing', vehicleKey: 'another-vehicle', stage: 'FITTING', bay: 1,
  startAt: at(day, hour).toISOString(), hours, status: 'planned', ...extra,
});
module.exports = { createSlotRuntime, at, booking };
