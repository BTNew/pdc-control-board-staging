'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const context = { window: {} };
vm.createContext(context);
vm.runInContext(fs.readFileSync('data.js', 'utf8'), context, { filename: 'data.js' });
vm.runInContext(fs.readFileSync('email-board-data.js', 'utf8'), context, { filename: 'email-board-data.js' });

assert.deepStrictEqual(Array.from(context.window.VEHICLE_TRACKING_DATA.vehicles || []), [], 'Production fallback data.js must contain no vehicle rows');
assert.deepStrictEqual(Array.from(context.window.PDC_EMAIL_BOARD_DATA.vehicles || []), [], 'Static email data must contain no vehicles');
assert.deepStrictEqual(Array.from(context.window.PDC_EMAIL_BOARD_DATA.reviews || []), [], 'Static email data must contain no review proposals');
assert.match(String(context.window.VEHICLE_TRACKING_DATA.report?.source || ''), /sanitised public fallback/i, 'Sanitised data source marker is required');

console.log('Public sanitisation checks passed');
