const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

assert.ok(app.includes('function focusVehiclesAfterWorkImport'), 'Shared post-import focus helper is missing');
assert.ok(app.includes("$$('details', host).forEach(details => { details.open = false; });"), 'Post-import focus must collapse all rows first');
assert.ok(app.includes("primary.classList.add('vehicle-search-highlight', 'vehicle-import-highlight')"), 'Imported vehicle must be highlighted');
assert.ok(app.includes('primary.open = true;'), 'Imported vehicle row must be opened');
assert.ok(app.includes('if (bucket) bucket.open = true;'), 'Imported vehicle bucket must be opened');
assert.ok(app.includes('focusVehiclesAfterWorkImport(results.filter(result => result.ok).map(result => result.vehicleKey))'), 'PO upload must focus successful imported vehicles');
assert.ok(app.includes(".filter(vehicle => vehicle.pdcImportMode === 'work-file')"), 'Job-card/work-file upload must identify imported vehicles for focus');
assert.ok(app.includes('if (workFileKeys.length) focusVehiclesAfterWorkImport(workFileKeys);'), 'Job-card/work-file upload must run post-import focus');

console.log('Post-import collapse, reveal and highlight checks passed');
