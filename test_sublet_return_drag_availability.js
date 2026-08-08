'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

const start = app.indexOf('function plainDateValue(');
const end = app.indexOf('function selectSubletView(', start);
assert(start >= 0 && end > start, 'Sublet date/lifecycle helpers must remain extractable');
const context = { Date };
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)}\nthis.eventField = subletCalendarEventField; this.awayOnDate = subletAwayOnDate; this.bookingState = subletBookingState;`, context);

assert.strictEqual(context.eventField('outgoing'), 'pmbSubletBookingDate', 'Going-out drag must move the outgoing date');
assert.strictEqual(context.eventField('due-back'), 'pmbSubletExpectedReturnDate', 'Due-back drag must move only the expected return plan');
assert.strictEqual(context.eventField('returned'), 'pmbSubletActualReturnDate', 'Returned drag must move the actual return date');
assert.strictEqual(context.eventField('unknown'), '', 'Unknown calendar event types must fail closed');

const away = { pmbSubletBookingDate: '2026-08-10', pmbSubletExpectedReturnDate: '2026-08-12' };
assert.strictEqual(context.awayOnDate(away, '2026-08-09'), false, 'Vehicle is available before outgoing date');
assert.strictEqual(context.awayOnDate(away, '2026-08-10'), true, 'Outgoing date is unavailable');
assert.strictEqual(context.awayOnDate(away, '2026-08-12'), true, 'Expected return is planning only and must not reopen availability');
assert.strictEqual(context.awayOnDate(away, '2026-08-20'), true, 'No actual return means the vehicle remains away after becoming overdue');
const returned = { ...away, pmbSubletActualReturnDate: '2026-08-13' };
assert.strictEqual(context.awayOnDate(returned, '2026-08-12'), true, 'Day before actual return remains unavailable');
assert.strictEqual(context.awayOnDate(returned, '2026-08-13'), false, 'Actual return date reopens workshop availability');
assert.strictEqual(context.bookingState(returned), 'returned', 'Actual return must have an explicit returned state');

assert(app.includes('data-sublet-returned='), 'Sublet list must expose a visible Returned checkbox');
assert(app.includes('function setSubletReturned('), 'Returned checkbox must use a dedicated persistence action');
assert(app.includes("updateSubletField(key, 'pmbSubletActualReturnDate'"), 'Returned action must persist the actual return date through the authoritative queue');
assert(app.includes('data-sublet-calendar-drag-type='), 'Calendar events must expose their draggable lifecycle type');
assert(app.includes('draggable="true"'), 'Calendar lifecycle events must be draggable');
assert(app.includes('data-sublet-calendar-drop-date='), 'Calendar days must expose authoritative drop targets');
assert(app.includes('function bindSubletCalendarInteractions('), 'Calendar drag/drop handlers must be bound after rendering');
assert(app.includes('app.subletCalendarDragData = payload;'), 'Drag payload must be retained because browsers hide DataTransfer data during dragover');
assert(app.includes('raw ? JSON.parse(raw) : retained'), 'Dragover must fall back to retained in-memory drag data');
assert(app.includes('dropSubletCalendarEvent('), 'Calendar drops must route through one controlled mutation path');
assert(css.includes('.sublet-calendar-day.is-drag-target'), 'Calendar must visibly identify a valid drag target');
assert(service.includes('sublet_away'), 'Workshop/Sublet conflict responses must be preserved as a canonical client error');

console.log('Sublet returned, calendar drag and away-interval frontend contract passed');
