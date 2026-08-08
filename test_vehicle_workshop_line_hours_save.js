'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('async function saveVehicleWorkshopLineHours');
const end = app.indexOf('async function scheduleVehicleWorkshopNextAvailable', start);
assert(start >= 0 && end > start, 'saveVehicleWorkshopLineHours must remain extractable');
const source = app.slice(start, end);

function makeRow(value, lineKey) {
  const input = {
    value: String(value),
    disabled: false,
    focusCount: 0,
    focus() { this.focusCount += 1; },
  };
  const save = {
    disabled: false,
    dataset: {
      stage: 'FITTING',
      lineKey,
      adjustmentId: '',
      adjustmentVersion: '0',
      description: `Line ${lineKey}`,
    },
    closest(selector) {
      if (selector === '.vehicle-workshop-line') return row;
      if (selector === '[data-vehicle-workshop-page]') return page;
      return null;
    },
  };
  const row = {
    querySelector(selector) {
      if (selector === '[data-vehicle-workshop-hours-save]') return save;
      if (selector === '[data-vehicle-workshop-hours-input]') return input;
      return null;
    },
  };
  let page = null;
  return { row, input, save, setPage(value) { page = value; } };
}

async function runSave(targetValue, unrelatedValue) {
  const target = makeRow(targetValue, 'target');
  const unrelated = makeRow(unrelatedValue, 'unrelated');
  const page = {
    querySelectorAll(selector) {
      assert.strictEqual(selector, '.vehicle-workshop-line');
      return [target.row, unrelated.row];
    },
  };
  target.setPage(page);
  unrelated.setPage(page);
  const calls = [];
  const alerts = [];
  const context = {
    saveVehicleWorkshopLine: async payload => { calls.push(payload); return true; },
    selectedVehicle: () => ({ id: 'vehicle-1' }),
    loadVehicleWorkshopDetail: async () => true,
    window: { alert: message => alerts.push(message) },
  };
  vm.createContext(context);
  vm.runInContext(`${source}\nthis.saveHours = saveVehicleWorkshopLineHours;`, context);
  const result = await context.saveHours(target.save);
  return { result, calls, alerts, target, unrelated };
}

(async () => {
  const valid = await runSave('3', '1.1');
  assert.strictEqual(valid.result, true, 'A valid 3-hour target row must save');
  assert.strictEqual(valid.calls.length, 1, 'Row Save must dispatch exactly one authoritative update');
  assert.strictEqual(valid.calls[0].lineKey, 'target', 'Row Save must update only the clicked row');
  assert.strictEqual(valid.calls[0].hours, '3', 'Exact 3-hour input must reach persistence unchanged');
  assert.deepStrictEqual(valid.alerts, [], 'An unrelated legacy decimal row must not block a valid target row');

  const invalid = await runSave('1.1', '3');
  assert.strictEqual(invalid.result, false, 'The clicked row must still enforce quarter-hour increments');
  assert.strictEqual(invalid.calls.length, 0, 'Invalid clicked-row hours must not dispatch');
  assert.strictEqual(invalid.target.input.focusCount, 1, 'Invalid clicked-row input must receive focus');

  console.log('Vehicle workshop row-hours save regression passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
