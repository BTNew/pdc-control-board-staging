const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');

for (const marker of [
  'focusedBookingMode',
  'workshopResolveFocusedBooking',
  'pendingBookingLink.focused === true',
  "sharedBookingId || ''",
  'matches.length !== 1',
  'authenticated_operation_lines_unavailable',
  'focused-operation-lines',
  'Back to Workshop planner',
  'data-workshop-focused-back',
  'focusedPlans',
  'Exact planned hours',
  'min="1" step="any"',
  'data-workshop-detail-form',
]) assert.ok(planner.includes(marker), `planner contains ${marker}`);
assert.ok(!/data-workshop-extend-hours="0\.25"[^]*>\+15m/.test(planner), 'legacy +15m duration control removed');
assert.ok(!/data-workshop-extend-hours="0\.5"[^]*>\+30m/.test(planner), 'legacy +30m duration control removed');
assert.ok(!/data-workshop-extend-hours="1"[^]*>\+1h/.test(planner), 'legacy +1h duration control removed');
assert.match(app, /pendingWorkshopBookingLink\s*=\s*\{[^}]*focused:\s*true/);
assert.match(css, /\.is-focused-booking/);
assert.match(css, /\.workshop-focused-operation-lines/);
console.log('Focused Workshop booking contract passed.');
