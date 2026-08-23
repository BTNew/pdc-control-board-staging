'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const start = source.indexOf('function startWorkshopResize');
const end = source.indexOf('\nfunction ', start + 10);
assert(start >= 0, 'chip resize handler is missing');
assert(end > start, 'chip resize handler boundary is missing');
const handler = source.slice(start, end);

assert(handler.includes("workshopDispatchSharedAction('resizeBooking'"),
  'shortening must use the ordinary resize RPC');
assert(handler.includes("workshopDispatchSharedAction('cascadeSchedule'"),
  'lengthening must retain the atomic extend cascade');
assert(handler.includes('nextDurationMinutes < currentDurationMinutes'),
  'shortening branch must be explicit');
assert(handler.includes('shiftMinutes: nextDurationMinutes - currentDurationMinutes'),
  'extend cascade shift must equal the positive duration increase');
assert(!handler.includes('Math.max(0, Math.round((nextHours - workshopClampDurationHours(entry.hours)) * 60))'),
  'resize must not clamp a shortening delta to zero and send it as extend');

console.log('workshop_chip_resize_routing: PASS');
