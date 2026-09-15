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
for (const name of ['parseDateAU','scotEtaOnly','parseIsoTimestamp','pmbEnteredTimestamp','daysSinceTimestamp','daysSinceDateValue','kewdaleEtaValue','onSiteDays','vehicleAgeColourBand','onSiteDaysClass','pmbAgeDays','incomingKewdaleAgeValue','incomingVehicleAge']) load(name);
const age = (v, bucket) => context.incomingVehicleAge(v,bucket);
const car = {pmbEnteredAt:'2026-09-15T08:00:00+08:00',navisionKewdaleEta:'2026-08-01'};
assert.equal(age(car,'pmb').label,'0 days');
assert.equal(age(car,'pmb').colourClass,'pmb-age-fresh');
assert.equal(age(car,'yardhold').label,'45 days');
assert.equal(age(car,'yardhold').colourClass,'pmb-age-critical');
assert.equal(age(car,'qc').label,'0 days');
for (const missing of [undefined,'','bad date']) {
  const result = age({...car,pmbEnteredAt:missing},'pmb');
  assert.equal(result.label,'—'); assert.equal(result.colourClass,'pmb-age-unknown');
}
assert.equal(age({...car,lifecycleHistory:{firstEnteredPmbAt:'2026-09-14T08:00:00+08:00'}},'pmb').label,'1 day');
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
