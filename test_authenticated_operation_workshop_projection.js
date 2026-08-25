'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function vehicleWorkshopGroups(');
const end = source.indexOf('\nfunction vehicleWorkshopJobCardValue', start);
assert.ok(start >= 0 && end > start, 'vehicleWorkshopGroups must be extractable');

const context = {
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FITTING: 'planner-fitting', FABRICATION: 'planner-fab' },
  vehicleWorkshopLocalRequirements: () => [],
  vehicleWorkshopBookingsForStage: () => [],
  vehiclePdcJobLines: () => [],
  authenticatedOperationLineValid: value => /^OP\d+$/.test(String(value || '')),
  authenticatedOperationLineSortValue: value => [Number(String(value).replace(/\D/g, '')) || 0, 0, String(value)],
  vehicleWorkshopStageCode: value => ({ fitting: 'FITTING', fabrication: 'FABRICATION', FITTING: 'FITTING', FABRICATION: 'FABRICATION' }[String(value)] || ''),
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  vehicleWorkshopLineDescription: (line, fallback = '') => String(line?.description || fallback),
  pdcJobLineStage: line => line?.stage || '',
  authenticatedOperationLineLabel: value => String(value || ''),
  vehicleWorkshopLineIdentity: (_stage, line) => line.operation_line_id ? `source:${line.operation_line_id}` : `display:${_stage}:${line.description}`,
  vehicleWorkshopAdjustedSourceHours: value => value == null || value === '' ? null : Number(value),
  vehicleWorkshopAdjustedSourceDescription: (line, adjustment) => String(adjustment?.description || line?.description || ''),
  vehicleWorkshopStationPresentation: stage => ({ label: stage === 'FITTING' ? 'Fitting' : 'Fabrication' }),
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);

const vehicle = {
  pdcEmailOperationLines: [{
    operation_line_id: '000569ea-d945-4280-be80-5a60d98615e1',
    operation_no: 'OP4',
    work_key: 'fabrication',
    description: '1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Board',
    estimated_hours: 0.30,
    estimatedHoursSource: 'job_card',
    job_card_number: 'HERMES-TEST-JC-PROJECTION',
  }],
};
const detail = {
  requirements: [{ required: true, completed: false, work_key: 'fitting', stage_code: 'FITTING' }],
  bookings: [],
  job_card_lines: null,
  operation_lines: null,
  work_lines: null,
  line_adjustments: [{
    source_kind: 'source',
    line_key: 'source:000569ea-d945-4280-be80-5a60d98615e1',
    stage_code: 'FITTING',
    description: '1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Board',
    estimated_hours: 0.30,
    adjustment_id: 'hermes-test-adjustment',
    version: 1,
  }],
};

for (let pass = 0; pass < 2; pass += 1) {
  const groups = context.vehicleWorkshopGroups(vehicle, detail);
  assert.strictEqual(groups.length, 1, 'one required Fitting group survives initial and refreshed detail projection');
  assert.strictEqual(groups[0].stage, 'FITTING');
  assert.strictEqual(groups[0].lines.length, 1, 'authoritative operation appears once without duplicate or fallback');
  const [line] = groups[0].lines;
  assert.strictEqual(line.fallback, undefined, 'generic fallback must not replace authoritative operation evidence');
  assert.match(line.description, /1\.5 KG FIRE EXT TO CARGO BARRIER or L\/H Tray Head Board/);
  assert.strictEqual(Number(line.estimatedHours), 0.30, 'exact authenticated 0.30 h survives projection');
  assert.strictEqual(line.workshopLineKey, 'source:000569ea-d945-4280-be80-5a60d98615e1');
}

console.log('authenticated operation Workshop projection: PASS');
