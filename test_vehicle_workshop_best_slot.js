'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('async function scheduleVehicleWorkshopNextAvailable');
const end = app.indexOf('function beginVehicleWorkshopLineDrag', start);
assert(start >= 0 && end > start, 'Vehicle-detail Best slot handler must remain extractable');
const source = app.slice(start, end);

const inputs = [{ value: '1.9' }, { value: '2' }];
const station = {
  querySelectorAll(selector) {
    assert.strictEqual(selector, '[data-vehicle-workshop-hours-input]');
    return inputs;
  },
};
const button = {
  dataset: {
    vehicleId: 'vehicle-12704377',
    vehicleKey: '12704377',
    stage: 'FITTING',
    hours: '1.9',
  },
  closest(selector) {
    if (selector === '[data-vehicle-workshop-stage]') return station;
    throw new Error(`Best slot must not inspect or save an individual operation row (${selector})`);
  },
};

const calls = [];
const context = {
  closeVehicleModal: () => calls.push({ type: 'close' }),
  openWorkshopPlannerForStage: stage => calls.push({ type: 'open', stage }),
  workshopScheduleVehicleNextAvailable: async payload => {
    calls.push({ type: 'schedule', payload });
    return true;
  },
};
vm.createContext(context);
vm.runInContext(`${source}\nthis.runBestSlot = scheduleVehicleWorkshopNextAvailable;`, context);

(async () => {
  const result = await context.runBestSlot(button);
  assert.strictEqual(result, true, 'Best slot must continue to the planner authority');
  const schedule = calls.find(call => call.type === 'schedule');
  assert.ok(schedule, 'Best slot must invoke authoritative planner scheduling');
  assert.strictEqual(schedule.payload.hours, 3.9, 'Best slot must total all displayed station operation estimates');
  assert.strictEqual(schedule.payload.stage, 'FITTING');
  assert.deepStrictEqual(calls.map(call => call.type), ['close', 'open', 'schedule'], 'Best slot must open the station planner and schedule without an operation-line Save mutation');
  console.log('Vehicle-detail Best slot regression passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
