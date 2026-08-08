'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = process.env.PDC_TEST_ROOT ? path.resolve(process.env.PDC_TEST_ROOT) : __dirname;
const shellNames = fs.existsSync(path.join(root, 'staging.html')) ? ['index.html', 'staging.html'] : ['index.html'];
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const shells = shellNames.map(name => fs.readFileSync(path.join(root, name), 'utf8'));

const start = app.indexOf('function plainDateValue(');
const end = app.indexOf('function renderSubletSummary(', start);
assert(start >= 0 && end > start, 'Sublet calendar helper block must remain extractable');
const context = {
  Date,
  Intl,
  Number,
  String,
  Math,
  Array,
  Object,
  Map,
  Set,
  Boolean,
  PDC_JOB_DEFS: [],
  vehicleLocationBoardRows: () => [],
  pdcJobRequired: () => false,
  pdcJobComplete: () => false,
  inferredPmbStage: () => '',
  pmbBaySubletProvider: vehicle => vehicle.provider || '',
  displayStockNumber: vehicle => vehicle.stock || '',
  vehicleKey: vehicle => vehicle.key || vehicle.stock || '',
  vehicleCustomerName: vehicle => vehicle.customer || '',
  displayVehicle: vehicle => vehicle.vehicle || '',
};
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)}
this.calendarRange = subletCalendarRange;
this.calendarEvents = subletCalendarEvents;
this.dateChangeError = subletDateChangeError;`, context);

const week = context.calendarRange('week', '2026-08-08');
assert.strictEqual(week.start, '2026-08-03', 'Week view must start on Monday');
assert.strictEqual(week.end, '2026-08-09', 'Week view must end on Sunday');
assert.strictEqual(Array.from(week.days).length, 7, 'Week view must contain seven days');

const month = context.calendarRange('month', '2026-08-08');
assert.strictEqual(month.start, '2026-07-27', 'Month view must begin on the Monday containing the first of the month');
assert.strictEqual(month.end, '2026-09-06', 'Month view must end on the Sunday containing the last of the month');
assert.strictEqual(Array.from(month.days).length, 42, 'August 2026 month view must render six complete weeks');

const fixtures = [
  { key: 'A', stock: '1300001', customer: 'Alpha', provider: 'Techfire', vehicle: 'Hilux', pmbSubletBookingDate: '2026-08-04', pmbSubletExpectedReturnDate: '2026-08-06' },
  { key: 'B', stock: '1300002', customer: 'Bravo', provider: 'HDD', vehicle: 'Prado', pmbSubletBookingDate: '2026-08-05', pmbSubletExpectedReturnDate: '2026-08-08', pmbSubletActualReturnDate: '2026-08-07' },
  { key: 'C', stock: '1300003', pmbSubletBookingDate: '' },
];
const events = Array.from(context.calendarEvents(fixtures), event => ({ key: event.key, date: event.date, type: event.type }));
assert.deepStrictEqual(events, [
  { key: 'A', date: '2026-08-04', type: 'outgoing' },
  { key: 'B', date: '2026-08-05', type: 'outgoing' },
  { key: 'A', date: '2026-08-06', type: 'due-back' },
  { key: 'B', date: '2026-08-07', type: 'returned' },
], 'Calendar must show outgoing, due-back and actual-return events in date order without leaving returned vehicles marked due');

assert.strictEqual(context.dateChangeError(fixtures[0], 'pmbSubletExpectedReturnDate', '2026-08-03'), 'Expected return date cannot be before the booking date.', 'Due-back date before outgoing date must fail closed');
assert.strictEqual(context.dateChangeError(fixtures[0], 'pmbSubletBookingDate', '2026-08-07'), 'Booking date cannot be after the expected return date.', 'Moving booking after due-back must fail closed');
assert.strictEqual(context.dateChangeError(fixtures[0], 'pmbSubletExpectedReturnDate', '2026-08-06'), '', 'A valid due-back date must be accepted');

for (const html of shells) {
  for (const id of ['sublet-list-view', 'sublet-calendar-view', 'sublet-calendar-controls', 'sublet-calendar-previous', 'sublet-calendar-today', 'sublet-calendar-next', 'sublet-calendar-week', 'sublet-calendar-month', 'sublet-calendar-range-label']) {
    assert(html.includes(`id="${id}"`), `Sublet shell is missing ${id}`);
  }
  assert(html.includes('aria-label="Sublet display view"'), 'List/calendar view switch must be accessible');
  assert(html.includes('aria-label="Sublet calendar period"'), 'Week/month switch must be accessible');
}

assert(app.includes('data-sublet-field="pmbSubletExpectedReturnDate"'), 'Booked rows must expose the expected return date');
assert(app.includes('data-sublet-field="pmbSubletActualReturnDate"'), 'Expanded details must expose the actual return date');
assert(app.includes('data-sublet-calendar-event'), 'Calendar cards must expose stable event hooks');
assert(app.includes('role="columnheader"'), 'Calendar weekday headings must be exposed to assistive technology');
assert(app.includes('role="gridcell" aria-label="${escapeHtml(fullDate)}"'), 'Every calendar date, including empty dates, must have an accessible full-date label');
assert(app.includes('role="grid" aria-label="${escapeHtml(`Sublet ${range.mode} calendar, ${subletCalendarRangeLabel(range)}`)}"'), 'Calendar grid must expose its view mode and visible range');
assert(!app.includes('sublet-calendar-weekdays" aria-hidden="true"'), 'Calendar weekday headings must not be hidden from assistive technology');
assert(app.includes("openVehicleModal(button.dataset.openStock)"), 'Calendar events must reuse the existing vehicle opener');
assert(app.includes("on($('#sublet-calendar-view'), 'click'"), 'Calendar view control must be wired');
assert(css.includes('.sublet-calendar-grid') && css.includes('.sublet-calendar-event.is-due-back') && css.includes('.sublet-calendar-event.is-returned'), 'Calendar must style its grid and event meanings');
assert(css.includes('.sublet-compact-toolbar label[hidden] { display: none !important; }'), 'Calendar mode must be able to hide the irrelevant booked-row sort control');
assert(css.includes('@media (max-width: 760px)') && css.includes('.sublet-calendar-grid'), 'Calendar must define a compact responsive presentation');

console.log('Sublet calendar view contract passed');
