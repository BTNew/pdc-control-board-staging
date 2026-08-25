const assert = require('assert');
const fs = require('fs');
const path = require('path');

const planner = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const start = planner.indexOf('function openWorkshopAdminBlockModal');
const end = planner.indexOf('\nfunction renderWorkshopPlanner', start);
assert.ok(start >= 0 && end > start, 'Admin block modal implementation is present');
const modal = planner.slice(start, end);
assert.match(modal, /const opener = document\.activeElement/);
assert.match(modal, /overlay\.addEventListener\('keydown'/);
assert.match(modal, /event\.key !== 'Escape'/);
assert.match(modal, /event\.preventDefault\(\)/);
assert.match(modal, /opener\?\.isConnected[\s\S]*opener\.focus\(\)/);
assert.ok(modal.indexOf("overlay.addEventListener('keydown'") < modal.indexOf('document.body.appendChild(overlay)'), 'Escape handling is bound before the dialog is displayed');
console.log('Workshop Admin modal Escape/focus-return contract passed.');
