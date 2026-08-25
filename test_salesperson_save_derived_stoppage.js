'use strict';
const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

assert.match(app, /data-pdc-location-baseline=/, 'shared detail renders raw lifecycle baseline');
assert.match(app, /data-pdc-blocked-baseline=/, 'shared detail renders raw block baseline');
assert.match(app, /data-pdc-block-reason-baseline=/, 'shared detail renders raw reason baseline');
assert.match(app, /data-pdc-work-state-baseline=/, 'shared detail renders raw work-state baseline');
assert.match(app, /const rawPdcBlocked = v\.pdcBlocked === true \|\| v\.pdcWorkshopBlocked === true/);
assert.match(app, /const workStateChangedByUser = rawWorkStateBaseline && PDC_JOB_DEFS\.some/);
assert.match(app, /saveAuthoritativeVehicleSalesperson\(current, requestedCode\)/);
assert.match(app, /updateSalespersonAssignment\(canonicalId, Number\(vehicle\.__emailVehicleVersion \|\| 0\), String\(requestedCode \|\| ''\)\.trim\(\)\.toUpperCase\(\), salespersonAssignmentIdempotencyKey\(\)\)/);
assert.match(app, /Error: lifecycle or stoppage fields use their dedicated shared action/);
assert.match(app, /if \(msg\) msg\.textContent = 'Saved'/);
assert.doesNotMatch(app, /pdcBlockReasonValue !== \(pdcBlockReason\(v\) \|\| ''\)/,
  'derived Parts/stoppage text cannot reject salesperson-only save');
assert.match(app, /if \(!serverAuthoritative \|\| workStateChangedByUser\) PDC_JOB_DEFS\.forEach/);
console.log('Salesperson derived-stoppage save contract passed.');
