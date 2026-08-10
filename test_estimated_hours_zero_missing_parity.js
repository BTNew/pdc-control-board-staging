'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');

function functionSource(name, nextName) {
  const start = app.indexOf(`function ${name}`);
  const end = app.indexOf(`function ${nextName}`, start);
  assert(start >= 0 && end > start, `Could not extract ${name}`);
  return app.slice(start, end);
}

const context = {
  cleanNavisionText(value) { return String(value ?? '').trim(); },
  escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  },
  vehicleWorkshopStationPresentation(stage) { return { label: stage === 'FITTING' ? 'Fitting' : stage, colour: '#123456', tint: '#eeeeee' }; },
  vehicleWorkshopLineDescription(line, fallback) { return String(line.description || fallback || '').trim(); },
  vehicleWorkshopCanEditLines() { return context.canEdit; },
  vehicleWorkshopDetailCanonicalId() { return '11111111-1111-4111-8111-111111111111'; },
  vehicleKey() { return 'VEH-1'; },
  vehicleWorkshopLineIdentity(_stage, line) { return line.operation_line_id || 'line-1'; },
  vehicleWorkshopBookingsForLine() { return []; },
  vehicleWorkshopBookingRowsHtml() { return ''; },
  vehicleWorkshopJobCardBookedActual() { return 'Not recorded'; },
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FITTING: 'workshop-fitting' },
  canEdit: false,
};
vm.createContext(context);
vm.runInContext([
  functionSource('vehicleWorkshopLineHours', 'vehicleWorkshopLineIdentity'),
  functionSource('vehicleWorkshopHoursLabel', 'vehicleWorkshopPerthDateKey'),
  functionSource('vehicleWorkshopHoursClass', 'vehicleWorkshopCompactLinesHtml'),
  functionSource('vehicleWorkshopCompactLinesHtml', 'vehicleWorkshopStationHtml'),
  functionSource('vehicleWorkshopStationHtml', 'renderVehicleWorkshopWorkPage'),
].join('\n'), context);

assert.strictEqual(context.vehicleWorkshopLineHours({ confirmedHours: 0 }), 0, 'Explicit confirmed zero must remain an explicit value');
assert.strictEqual(context.vehicleWorkshopLineHours({ estimated_hours: 0 }), 0, 'Explicit source zero must remain an explicit value');
assert.strictEqual(context.vehicleWorkshopLineHours({ estimated_hours: null }), null, 'Missing source hours must remain missing');
assert.strictEqual(context.vehicleWorkshopLineHours({ estimated_hours: '' }), null, 'Blank source hours must remain missing rather than becoming zero');
assert.strictEqual(context.vehicleWorkshopHoursLabel(0), '0 hrs', 'Explicit zero must have a visible zero label');
assert.strictEqual(context.vehicleWorkshopHoursLabel(null), 'Estimate not set', 'Missing hours must retain the missing label');
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(context.vehicleWorkshopHoursClass({ confirmedHours: 0 }, 0))),
  { label: 'Confirmed hours', value: 0 },
  'Confirmed zero must not be classified as unknown/missing',
);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(context.vehicleWorkshopHoursClass({ estimatedHours: 0, estimatedHoursSource: 'job_card' }, 0))),
  { label: 'Confirmed hours', value: 0 },
  'Authenticated job-card provenance must remain attached to an explicit zero estimate',
);

const baseGroup = {
  stage: 'FITTING',
  requirements: [{ required: true, completed: false }],
  bookings: [],
};
const zeroGroup = { ...baseGroup, lines: [{ operation_line_id: 'zero-line', description: 'Zero-hour inspection', confirmedHours: 0 }] };
const missingGroup = { ...baseGroup, lines: [{ operation_line_id: 'missing-line', description: 'Unestimated fitting', estimated_hours: null }] };
const positiveGroup = { ...baseGroup, lines: [{ operation_line_id: 'positive-line', description: 'Fit accessory', estimated_hours: 1.5 }] };

const zeroReadOnlyHtml = context.vehicleWorkshopStationHtml(zeroGroup, 'Not booked', {}, ['FITTING']);
const missingReadOnlyHtml = context.vehicleWorkshopStationHtml(missingGroup, 'Not booked', {}, ['FITTING']);
assert(zeroReadOnlyHtml.includes('Confirmed hours: 0 hrs'), 'Vehicle Detail line must render explicit zero');
assert(zeroReadOnlyHtml.includes('vehicle-workshop-station-total">0 hrs'), 'Station total must retain explicit zero');
assert(missingReadOnlyHtml.includes('Unknown hours'), 'Missing line hours must render as unknown');
assert(missingReadOnlyHtml.includes('vehicle-workshop-station-total">Estimate not set'), 'Missing station total must remain unset');

context.canEdit = true;
const zeroEditableHtml = context.vehicleWorkshopStationHtml(zeroGroup, 'Not booked', {}, ['FITTING']);
const missingEditableHtml = context.vehicleWorkshopStationHtml(missingGroup, 'Not booked', {}, ['FITTING']);
const positiveEditableHtml = context.vehicleWorkshopStationHtml(positiveGroup, 'Not booked', {}, ['FITTING']);
assert(!zeroEditableHtml.includes('data-vehicle-workshop-schedule-next'), 'Explicit zero must fail closed instead of silently creating a default-duration booking');
assert(!zeroEditableHtml.includes('draggable="true"'), 'Explicit zero must not enter Planner drag handoff');
assert(!missingEditableHtml.includes('data-vehicle-workshop-schedule-next'), 'Missing hours must fail closed before Planner scheduling');
assert(!missingEditableHtml.includes('draggable="true"'), 'Missing hours must not enter Planner drag handoff');
assert(positiveEditableHtml.includes('data-vehicle-workshop-schedule-next'), 'A positive explicit estimate must retain Best slot');
assert(positiveEditableHtml.includes('draggable="true"'), 'A positive explicit estimate must retain Planner drag handoff');
assert(positiveEditableHtml.includes('data-hours="1.5"'), 'Planner handoff must use the same station total shown in Vehicle Detail');

console.log('Estimated-hours explicit zero/missing parity passed');
