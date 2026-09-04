'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const source = fs.readFileSync('app.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
assert.match(indexSource, /explicit-sublet-operation=2026\.09\.04\.01/, 'changed vehicle read-model asset must be cache-busted');
const start = source.indexOf('function vehicleWorkshopGroups(');
const end = source.indexOf('\nfunction vehicleWorkshopJobCardValue', start);
assert.ok(start >= 0 && end > start, 'vehicleWorkshopGroups must be extractable');

const context = {
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: {
    BUS_4X4: 'planner-bus-4x4', TINT: 'planner-tint', FITTING: 'planner-fitting',
    FABRICATION: 'planner-fab', ELECTRICAL: 'planner-elec', TYRE: 'planner-tyre',
  },
  VEHICLE_WORKSHOP_STATION_PRESENTATION: {
    BUS_4X4: { label: 'Bus 4x4' }, TINT: { label: 'Tint' }, FITTING: { label: 'Fitting' },
    FABRICATION: { label: 'Fabrication' }, ELECTRICAL: { label: 'Electrical' },
    TYRE: { label: 'Tyre' }, SUBLET: { label: 'Sublet' },
  },
  vehicleWorkshopLocalRequirements: vehicle => [{ required: vehicle.pdcRequiresSublet, completed: vehicle.pdcCompleteSublet, work_key: 'sublet' }],
  vehicleWorkshopBookingsForStage: () => [],
  vehiclePdcJobLines: () => [],
  authenticatedOperationLineValid: value => /^OP\d+$/.test(String(value || '')),
  authenticatedOperationLineSortValue: value => [Number(String(value).replace(/\D/g, '')) || 0, 0, String(value)],
  vehicleWorkshopStageCode: value => ({ bus4x4: 'BUS_4X4', tint: 'TINT', fitting: 'FITTING', fabrication: 'FABRICATION', electrical: 'ELECTRICAL', tyre: 'TYRE', sublet: 'SUBLET' }[String(value)] || String(value || '').toUpperCase()),
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  vehicleWorkshopLineDescription: (line, fallback = '') => String(line?.description || fallback),
  pdcJobLineStage: line => line?.stage || '',
  authenticatedOperationLineLabel: value => String(value || ''),
  vehicleWorkshopLineIdentity: (_stage, line) => line.operation_line_id ? `source:${line.operation_line_id}` : `display:${_stage}:${line.description}`,
  vehicleWorkshopAdjustedSourceHours: value => value == null || value === '' ? null : Number(value),
  vehicleWorkshopAdjustedSourceDescription: (line, adjustment) => String(adjustment?.description || line?.description || ''),
  vehicleWorkshopStationPresentation: stage => ({ label: String(stage || '').replace(/_/g, ' ') }),
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);

const operationLines = Array.from({ length: 18 }, (_, index) => ({
  operation_line_id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
  operation_no: `OP${index + 1}`,
  work_key: index === 13 ? 'sublet' : ['bus4x4', 'tyre', 'fitting', 'electrical', 'fabrication', 'tint'][index % 6],
  job_card_number: 'J138000812',
  description: index === 13 ? 'SUB REFLECTIVE STRIPING YELLOW' : `Retained operation ${index + 1}`,
  estimated_hours: index === 13 || index === 14 ? 0 : 1,
  estimated_hours_source: 'job_card',
}));

const vehicle = mapServerVehicle({
  id: 'e49685ca-c9b7-448d-9b45-1aba97d6d3b4',
  permanent_vehicle_id: 'EMAIL-test-u158318',
  stock_number: 'U158318',
  job_card_number: 'J138000812',
  current_location: 'YH',
  work_items: [{ work_key: 'sublet', required: true, completed: false }],
  operation_lines: operationLines,
  sublet_booking: {},
  sublet_bookings: [],
});

assert.strictEqual(vehicle.pdcEmailOperationLines.length, 18, 'all explicit Job Card operations reach the vehicle-detail read model');
const explicitSublet = vehicle.pdcEmailOperationLines.find(line => line.operation_no === 'OP14');
assert.ok(explicitSublet, 'OP14 explicit Sublet Job Card row remains visible');
assert.strictEqual(explicitSublet.work_key, 'sublet');
assert.strictEqual(explicitSublet.estimatedHours, 0, 'explicit Sublet zero hours remain immutable evidence');
assert.deepStrictEqual(vehicle.pdcSubletBookings, [], 'an explicit Sublet operation must not invent a provider or booking');
assert.strictEqual(vehicle.pdcRequiresSublet, true);
assert.strictEqual(vehicle.pdcCompleteSublet, false);

const groups = context.vehicleWorkshopGroups(vehicle, null);
const projected = groups.flatMap(group => group.lines);
assert.strictEqual(projected.length, 18, 'Vehicle detail projects all 18 operation rows');
assert.ok(groups.find(group => group.stage === 'SUBLET')?.lines.some(line => line.operation_no === 'OP14'), 'Vehicle detail renders OP14 in the Sublet group');
const displayedOperationCount = projected.filter(line => /^[0-9a-f-]{36}$/i.test(String(line.operation_line_id || line.source_operation_line_id || '')) && !line.fallback && !line.workshopManualLine).length;
assert.strictEqual(displayedOperationCount, 18, 'displayed operation count includes explicit Sublet rows');

console.log('Vehicle detail explicit Sublet operation regression: PASS');
