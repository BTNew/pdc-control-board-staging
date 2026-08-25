'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');

const helperStart = source.indexOf('function workshopAdminDurationHoursValue');
const helperEnd = source.indexOf('function bindWorkshopAdminPalette', helperStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'hours formatter exists');
const context = { workshopSnapMinutes: value => Math.round(value / 15) * 15 };
vm.createContext(context);
vm.runInContext(`${source.slice(helperStart, helperEnd)} this.hoursValue = workshopAdminDurationHoursValue;`, context);
assert.strictEqual(context.hoursValue(15), '0.25');
assert.strictEqual(context.hoursValue(30), '0.5');
assert.strictEqual(context.hoursValue(60), '1');
assert.strictEqual(context.hoursValue(75), '1.25');

assert.match(source, /function workshopAdminDurationInputMinutes/);
assert.match(source, /unit === 'working_days' \? numeric \* WORKSHOP_PLANNER_CONFIG\.dayLengthMinutes/);
assert.match(source, /Admin · \$\{workshopAdminDurationHoursValue\(workshopAdminPaletteDurationMinutes\)\} h/);
assert.match(source, /data-workshop-admin-palette-unit/);
assert.match(source, /<option value="working_days">Working days<\/option>/);
assert.match(source, /<label><span>Duration unit<\/span><select name="durationUnit">/);
assert.match(source, /const durationMinutes = workshopAdminDurationInputMinutes\(form\.elements\.durationValue\.value, form\.elements\.durationUnit\.value\)/);
assert.doesNotMatch(source, /data-workshop-admin-palette-duration[^>]*max="8"/);
assert.doesNotMatch(source, /Admin · 30 min/);
assert.doesNotMatch(source, /aria-label="Admin block duration in minutes"/);

const toolbarStart = source.indexOf('<div class="workshop-date-controls">');
const toolbarEnd = source.indexOf('</header>', toolbarStart);
assert.ok(toolbarStart >= 0 && toolbarEnd > toolbarStart, 'toolbar markup exists');
const toolbar = source.slice(toolbarStart, toolbarEnd);
assert.match(toolbar, /<div class="workshop-date-nav">[\s\S]*data-workshop-date[\s\S]*<span class="workshop-date-shift-group"/);
const previous = toolbar.indexOf('data-workshop-date-shift="-1"');
const next = toolbar.indexOf('data-workshop-date-shift="1"');
const today = toolbar.indexOf('data-workshop-today');
assert.ok(previous >= 0 && next > previous && today > next, 'Previous and Next are adjacent before Today');

assert.match(css, /\.workshop-date-controls input\[data-workshop-date\]\s*\{[^}]*width:\s*160px;[^}]*flex:\s*0 0 160px;/s);
assert.match(css, /\.workshop-date-shift-group\s*\{[\s\S]*?display:\s*inline-flex;/);
assert.match(css, /\.workshop-date-shift-group button\s*\{[^}]*width:\s*auto;[^}]*min-width:\s*92px;/s);
console.log('Workshop toolbar hours and compact date navigation: PASS');
