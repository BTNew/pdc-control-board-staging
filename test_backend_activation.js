const assert = require('assert');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');

assert.ok(html.includes('id="backend-data-search"'), 'Back End Data search input is missing');
assert.ok(html.includes('id="backend-data-state-filter"'), 'Back End Data state filter is missing');
assert.ok(html.includes('Stock, VIN, customer or vehicle'), 'Back End Data search must describe supported identities without Toyota order');
assert.ok(app.includes('function filteredBackEndDataRows'), 'Back End Data filtering function is missing');
assert.ok(app.includes('function transferBackEndVehicleToActive'), 'Back-end activation action is missing');
assert.ok(app.includes("pdcVisibilityPromotionUpdates(vehicle, 'Operator transfer from Back End Data')"), 'Activation must use durable PDC Sheet promotion');
assert.ok(app.includes('navisionDerivedLocationUpdates(vehicle, vehicle)'), 'Activation must use the latest Navision location');
assert.ok(app.includes("if (location === 'PMB') return 'PMB - Unallocated'"), 'Body Builder / PMB activation must land in PMB Unallocated');
assert.ok(app.includes('data-backend-activate'), 'Back-end-only rows must render an activation button');
assert.ok(css.includes('Back End Data — 11 explicit columns'), 'Back End Data action and requested Navision-field styling is missing');

console.log('Back End Data search and activation regression checks passed');
