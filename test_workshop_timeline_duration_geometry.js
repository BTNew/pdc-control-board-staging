'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

const start = planner.indexOf('function workshopTimelineCssVariables');
const end = planner.indexOf('\nfunction workshopDropPreviewHtml', start);
assert.ok(start > 0 && end > start);
const context = { WORKSHOP_PLANNER_CONFIG: { dayLengthMinutes: 600 } };
vm.createContext(context);
vm.runInContext(planner.slice(start, end), context);
assert.equal(context.workshopTimelineCssVariables(), '--workshop-half-hour-width:5.000000%;--workshop-hour-width:10.000000%;');
context.WORKSHOP_PLANNER_CONFIG.dayLengthMinutes = 540;
assert.equal(context.workshopTimelineCssVariables(), '--workshop-half-hour-width:5.555556%;--workshop-hour-width:11.111111%;');

assert.match(planner, /const width = \(\(segment\.end - segment\.start\) \/ WORKSHOP_PLANNER_CONFIG\.dayLengthMinutes\) \* 100/);
assert.equal((120 / 600) * 100, 20, 'a 120-minute booking occupies exactly 20% of a 10-hour board');
assert.match(planner, /class="workshop-timeline" style="\$\{workshopTimelineCssVariables\(\)\}"/);
assert.match(planner, /class="workshop-plan-time"/);
assert.match(planner, /workshopEntryTimeLabel\(entry\).*workshopDurationInputValue\(entry\.hours\).* h/);
assert.match(css, /var\(--workshop-half-hour-width/);
assert.match(css, /var\(--workshop-hour-width/);
const dailyTimelineCss = css.slice(css.indexOf('.workshop-time-axis'), css.indexOf('.workshop-drop-preview'));
assert.doesNotMatch(dailyTimelineCss, /6\.25%|12\.5%/);
assert.match(css, /\.workshop-plan-chip \{[\s\S]*height: 96px/);
assert.match(css, /\.workshop-plan-chip strong \{ font-size: \.74rem; font-weight: 950/);
assert.match(css, /\.workshop-plan-chip \.workshop-plan-time,[\s\S]*font-weight: 950/);
assert.match(index, /workshop-planner\.css\?v=2026\.08\.30\.1000-771-admin-block-audit-continuations-successor/);

console.log('Workshop timeline duration geometry and bold aligned typography: PASS');
