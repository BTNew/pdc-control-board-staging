'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

function between(source, start, end) {
  const startAt = source.indexOf(start);
  const endAt = source.indexOf(end, startAt + start.length);
  assert.ok(startAt >= 0 && endAt > startAt, `expected ${start} section`);
  return source.slice(startAt, endAt);
}

const state = between(app, 'const app = {', '};\n\n\nwindow.PDC_APP');
const showView = between(app, 'function showView(', 'const HEAVY_VIEW_HOSTS');
const subletRows = between(app, 'function subletRows()', 'function subletDateOrdinal');
const calendar = between(app, 'function subletCalendarEvents(', 'function subletCalendarEventField');
const calendarDateHelpers = between(app, 'function subletDateOrdinal(', 'function subletCalendarEvents(');
const render = between(app, 'function renderSubletHome()', 'function getNotes');

assert.match(state, /subletViewMode:\s*'calendar'/, 'clean app state defaults Sublet to Calendar view');
assert.match(state, /subletCalendarMode:\s*'month'/, 'clean app state defaults Sublet to Month mode');
assert.match(showView, /app\.currentRequestedView\s*=\s*requestedView/, 'direct Sublet navigation records the requested route');
assert.match(showView, /renderActiveView\(\)/, 'direct Sublet navigation renders the requested view');
assert.match(render, /renderSubletCalendar\(rows\)/, 'Sublet renders calendar content when Calendar is selected');
assert.match(render, /if \(app\.subletViewMode === 'calendar'\) app\.subletOperationalFilter = 'booked'/, 'calendar selection keeps the booked operational projection');
assert.match(app, /function selectSubletView\(mode = 'list'\)[\s\S]*?app\.subletViewMode = mode === 'calendar' \? 'calendar' : 'list'/, 'explicit view switching remains available');
assert.match(app, /function selectSubletCalendarMode\(mode = 'week'\)[\s\S]*?app\.subletCalendarMode = mode === 'month' \? 'month' : 'week'/, 'explicit week/month switching remains available');
assert.match(app, /function moveSubletCalendar\([\s\S]*?mode === 'week'[\s\S]*?Number\(direction\) \* 7[\s\S]*?Date\.UTC\(year, month - 1 \+ Number\(direction\), 1\)/, 'week and month navigation retain their distinct increments');
assert.match(calendar, /pmbSubletBookingDate/);
assert.match(calendar, /pmbSubletExpectedReturnDate/);
assert.match(calendar, /pmbSubletActualReturnDate/);
assert.match(calendar, /vehicleCustomerName\(vehicle\)/, 'calendar events include authoritative customer information');
assert.match(calendar, /pmbBaySubletProvider\(vehicle\)/, 'calendar events include authoritative provider information');
assert.match(subletRows, /return vehicleLocationBoardRows\(\)\.flatMap/, 'Sublet rows originate from the authoritative board snapshot');
assert.doesNotMatch(subletRows, /localStorage|loadJson\(/, 'Sublet row projection does not use browser-local operational authority');
assert.match(app, /case 'dashboard':[\s\S]*?case 'sublet':[\s\S]*?renderSubletHome\(\)/, 'dashboard and Sublet routes remain explicitly dispatched');
assert.match(app, /case 'workflow':[\s\S]*?case 'workshop':[\s\S]*?case 'parts'/, 'unrelated route dispatch remains intact');
assert.match(index, /id="sublet-list-view"/);
assert.match(index, /id="sublet-calendar-view"/);
assert.match(index, /id="sublet-calendar-week"/);
assert.match(index, /id="sublet-calendar-month"/);
assert.match(index, /class="small-button is-active" id="sublet-calendar-view"[^>]*aria-pressed="true"/);
assert.match(index, /class="small-button is-active" id="sublet-calendar-month"[^>]*aria-pressed="true"/);
assert.match(index, /id="sublet-list-view"[^>]*aria-pressed="false"/);
assert.match(index, /id="sublet-calendar-week"[^>]*aria-pressed="false"/);
assert.match(index, /sublet-calendar-default=2026\.08\.30\.772/);

const dateContext = { plainDateValue: value => String(value || '').match(/^(\d{4}-\d{2}-\d{2})/)?.[1] || '' };
vm.createContext(dateContext);
vm.runInContext(`${calendarDateHelpers}\nthis.range = subletCalendarRange;`, dateContext);
const currentMonth = dateContext.range('month', '2026-08-29');
assert.strictEqual(currentMonth.mode, 'month', 'month mode is selected for the current-month range');
assert.strictEqual(currentMonth.month, '2026-08', 'month mode anchors to the selected current month');
assert.ok(currentMonth.days.includes('2026-08-29'), 'current month range includes the selected date');

const eventContext = {
  vehicleKey: vehicle => vehicle.id,
  vehicleKeyNumber: vehicle => vehicle.keyNumber || '',
  displayStockNumber: vehicle => vehicle.stock,
  pmbBaySubletProvider: vehicle => vehicle.provider,
  vehicleCustomerName: vehicle => vehicle.customer,
  displayVehicle: vehicle => vehicle.vehicle,
  plainDateValue: value => String(value || '').match(/^(\d{4}-\d{2}-\d{2})/)?.[1] || '',
  subletTodayDateKey: () => '2026-08-29',
};
vm.createContext(eventContext);
vm.runInContext(`${calendar}\nthis.events = subletCalendarEvents;`, eventContext);
const authoritativeEvents = eventContext.events([{
  id: 'canonical-vehicle-uuid',
  stock: '13000769',
  provider: 'Lovells',
  customer: 'Authoritative Customer',
  vehicle: 'Toyota Hilux',
  pmbSubletBookingDate: '2026-08-20',
  pmbSubletExpectedReturnDate: '2026-08-30',
  pmbSubletActualReturnDate: '',
}]);
assert.deepStrictEqual(Array.from(authoritativeEvents, event => event.date), ['2026-08-20', '2026-08-30'], 'calendar places outgoing and due-back events from canonical booking dates');
assert.strictEqual(authoritativeEvents[0].provider, 'Lovells');
assert.strictEqual(authoritativeEvents[0].customer, 'Authoritative Customer');
assert.strictEqual(authoritativeEvents[0].key, 'canonical-vehicle-uuid');

console.log('Sublet Calendar Month default regression contract passed.');
