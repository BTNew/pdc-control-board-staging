'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const read = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const planner = read('workshop-planner.js');
const app = read('app.js');
const css = read('styles.css');
const index = read('index.html');
const staging = read('staging.html');
const migration = read('supabase/migrations/048_staging_blocker_closure.sql');

assert(!planner.includes('Live editing unlocks after the approved legacy data migration runs'));
assert(planner.includes('Connected · shared workshop data · live editing enabled'));
assert(planner.includes('Blocked legacy Workshop serializer in shared mode; use a protected shared action.'));
assert(planner.includes('workshopAnnotateLegacyAmbiguity'));
assert(planner.includes('Legacy review required · editing blocked'));
assert(planner.includes("const draggable = entry.status !== 'completed' && !entry.legacyAmbiguityReason"));

for (const action of ['scheduleVehicleWork', 'moveBooking', 'cascadeSchedule', 'startWork', 'stopWork', 'resumeWork', 'completeWork']) {
  assert(planner.includes(`'${action}'`) || planner.includes(`.${action}(`), `missing protected action ${action}`);
}

assert(migration.includes('vehicles_toyota_order_normalized_idx'));
assert(migration.includes('union select v.id'));
assert(migration.includes("b.status in('started','stoppage') and b.scheduled_start_at<v_to"));
assert(migration.includes("set local lock_timeout = '3s'"), 'staging index build must fail fast instead of blocking live writes');
assert(!/set\s+(local\s+)?statement_timeout/i.test(migration), 'runtime performance fix must not increase the statement timeout');
assert(migration.includes('workshop_booking_048_legacy_ambiguity_guard'));
assert(migration.includes("raise exception 'legacy_ambiguity_blocked'"));

for (const label of ['Parts required', 'Parts ordered', 'Parts received', 'JITA ordered', 'Parts stoppage', 'Ready for workshop']) {
  assert(app.includes(label), `missing filter ${label}`);
}
for (const action of ['Mark ordered', 'Mark received', 'Add stoppage', 'Remove stoppage', 'Open vehicle']) {
  assert(app.includes(action), `missing visible action ${action}`);
}
for (const field of ['Key</th>', 'Stock</th>', 'JC</th>', 'Vehicle / customer', 'Outstanding station work', 'Stoppage reason']) {
  assert(app.includes(field), `missing Parts field ${field}`);
}
assert(app.includes('toggleVehiclePartsJita'));
assert(css.includes('overflow-x: hidden'));
assert(css.includes('.parts-visible-actions'));
assert(!index.includes('id="parts-status-filter"'));
assert(!staging.includes('id="parts-status-filter"'));
assert(index.includes('parts-operational-filters'));
assert(staging.includes('parts-operational-filters'));

console.log('Staging blocker closure source, migration and Parts UI checks passed');
