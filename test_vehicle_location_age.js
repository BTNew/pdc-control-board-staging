/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const context = { Date: class extends Date {
  constructor(...args) { super(...(args.length ? args : ['2026-09-15T12:00:00+08:00'])); }
}, locationAgeLabel: v => v.navisionKewdaleEta || 'No ETA' };
vm.createContext(context);
function load(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  const end = source.indexOf('\nfunction ', start + 1);
  vm.runInContext(source.slice(start, end), context);
}
for (const name of ['parseDateAU','scotEtaOnly','parseIsoTimestamp','pmbEnteredTimestamp','daysSinceTimestamp','daysSinceDateValue','kewdaleEtaValue','onSiteDays','vehicleAgeColourBand','onSiteDaysClass','pmbVehicleHasKey','pmbKeyAssignedRow','pmbKeyAssignedTimestamp','pmbArrivalAgeRow','pmbTuneImportedTimestamp','pmbArrivalAgeBasis','pmbArrivalAgeTimestamp','pmbAgeDays','incomingKewdaleAgeValue','incomingVehicleAge']) load(name);
const age = (v, bucket) => context.incomingVehicleAge(v,bucket);
const car = {pmbEnteredAt:'2026-09-15T08:00:00+08:00',navisionKewdaleEta:'2026-08-01'};
assert.equal(age(car,'pmb').label,'0 days');
assert.equal(age(car,'pmb').colourClass,'pmb-age-fresh');
assert.equal(age(car,'pmb').title,'Days since the board arrival. No key history and no Tune import.');
assert.equal(age(car,'yardhold').label,'45 days');
assert.equal(age(car,'yardhold').colourClass,'pmb-age-critical');
assert.equal(age(car,'qc').label,'0 days');
assert.equal(age(car,'newpmb').label,'0 days');
const keyedToday = {...car, keyNumber: '205', keyAssignedAt: '2026-09-15T08:00:00+08:00', lifecycleHistory: {firstEnteredPmbAt: '2026-08-01T08:00:00+08:00'}};
assert.equal(age(keyedToday,'pmb').label,'0 days');
assert.equal(age(keyedToday,'pmb').colourClass,'pmb-age-fresh');
assert.equal(age(keyedToday,'pmb').title,'Days since the key number was assigned');
assert.equal(age({...car, keyNumber: '205', keyAssignedAt: '2026-09-14T08:00:00+08:00'},'qc').label,'1 day');
assert.equal(age({...car, keyNumber: '205'},'pmb').label,'0 days');
assert.equal(age({...car, keyNumber: '205'},'pmb').title,'Days since the board arrival. No key history and no Tune import.');
const bareKey = {keyNumber: '205', navisionKewdaleEta:'2026-08-01'};
assert.equal(age(bareKey,'pmb').label,'—');
assert.equal(age(bareKey,'pmb').colourClass,'pmb-age-unknown');
assert.equal(age(bareKey,'pmb').title,'No key history and no Tune import, so there is no PMB age');
const bare = {navisionKewdaleEta:'2026-08-01'};
assert.equal(age(bare,'pmb').label,'No key');
assert.equal(age(bare,'pmb').title,'No key history and no Tune import, so there is no PMB age');
assert.equal(age({...bare, tuneImportedAt: '2026-09-14T08:00:00+08:00'},'pmb').label,'1 day');
assert.equal(age({...bare, tuneImportedAt: '2026-09-14T08:00:00+08:00'},'pmb').title,'Days since this vehicle first appeared in a Tune import');
assert.equal(age({...bare, keyAssignedAt: '2026-09-15T08:00:00+08:00', tuneImportedAt: '2026-09-01T08:00:00+08:00'},'pmb').label,'14 days');
assert.equal(age({...bare, keyAssignedAt: '2026-09-15T08:00:00+08:00', tuneImportedAt: '2026-09-01T08:00:00+08:00'},'pmb').title,'Days since this vehicle first appeared in a Tune import');
for (const missing of [undefined,'','bad date']) {
  const result = age({keyNumber: '205', keyAssignedAt: missing},'pmb');
  assert.equal(result.label,'—'); assert.equal(result.colourClass,'pmb-age-unknown');
}
assert.equal(age({keyNumber: '205', pmbEnteredAt:'2026-09-15T08:00:00+08:00', lifecycleHistory:{firstEnteredPmbAt:'2026-09-14T08:00:00+08:00'}},'pmb').label,'1 day');
assert.equal(age({...car,navisionKewdaleEta:''},'yardhold').label,'—');
assert.equal(age({...car,navisionKewdaleEta:'2026-09-17'},'yardhold').label,'Due in 2 days');
assert.equal(age({...car,navisionKewdaleEta:'2026-09-17'},'yardhold').colourClass,'pmb-age-future');
assert.equal(age({...car,navisionKewdaleEta:'14/09/2026'},'yardhold').label,'1 day');
for (const [days,band] of [[null,'unknown'],[-1,'future'],[0,'fresh'],[5,'fresh'],[6,'watch'],[10,'watch'],[11,'warning'],[21,'warning'],[22,'critical']]) assert.equal(context.vehicleAgeColourBand(days),band);
for (const bucket of ['transit','other','pit','nonnavision']) assert.equal(age(car,bucket).colourClass,'');
assert.equal(age(car,'nonnavision').label,'Unconfirmed');
assert.match(source,/incoming-card-age \$\{escapeHtml\(locationAge.colourClass\)\}/);
assert.match(source,/escapeHtml\(locationAge.label\)/);
console.log('Vehicle location age and colour sources: PASS');
