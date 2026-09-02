'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
const migrationPath = 'supabase/staging_only/20260903010000_workshop_eta_plus_seven_authority_20260903.sql';

function extractFunction(name) {
  const start = plannerSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let parens = 0;
  let open = -1;
  for (let index = plannerSource.indexOf('(', start); index < plannerSource.length; index += 1) {
    if (plannerSource[index] === '(') parens += 1;
    if (plannerSource[index] === ')' && --parens === 0) {
      open = plannerSource.indexOf('{', index);
      break;
    }
  }
  assert.ok(open >= 0, `${name} body exists`);
  let depth = 0;
  for (let index = open; index < plannerSource.length; index += 1) {
    if (plannerSource[index] === '{') depth += 1;
    if (plannerSource[index] === '}' && --depth === 0) return plannerSource.slice(start, index + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const context = {
  cleanNavisionText: value => String(value || '').trim(),
  statusCategory: () => 'transit',
  workshopDateKey: value => {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  },
};
vm.createContext(context);
vm.runInContext(`${extractFunction('workshopVehiclePlanningLocation')}\n${extractFunction('workshopVehicleEtaConstraint')}\nthis.constraint = workshopVehicleEtaConstraint;`, context);

const inTransit = context.constraint({ currentLocation: 'IT', navisionKewdaleEta: '2026-09-10' });
assert.strictEqual(inTransit.earliestDateKey, '2026-09-17', 'normal IT booking starts no earlier than ETA + 7 days');
assert.strictEqual(inTransit.bestSlotEarliestDateKey, '2026-09-17');
assert.strictEqual(context.constraint({ currentLocation: 'IT', navisionKewdaleEta: '2026-12-28' }).earliestDateKey, '2027-01-04', 'ETA + 7 crosses year boundary');
assert.strictEqual(context.constraint({ currentLocation: 'IT', navisionKewdaleEta: '2028-02-23' }).earliestDateKey, '2028-03-01', 'ETA + 7 crosses leap day');
assert.strictEqual(context.constraint({ currentLocation: 'IT', navisionKewdaleEta: '' }).reason, 'missing_eta');
assert.strictEqual(context.constraint({ currentLocation: 'IT', navisionKewdaleEta: 'not-a-date' }).reason, 'invalid_eta');
const pmb = context.constraint({ currentLocation: 'PMB', navisionKewdaleEta: '2026-09-10' });
assert.strictEqual(pmb.required, false, 'manual PMB latch removes the Navision ETA scheduling constraint');

assert.ok(fs.existsSync(migrationPath), 'append-only STAGING backend ETA + 7 authority migration exists');
const sql = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  'pdc_production_environment_sentinel',
  'workshop_candidate_schedule_gate',
  "v_candidate.eta_to_kewdale+7",
  "'it_before_eta_plus_seven'",
  "'earliest_permitted_date',v_candidate.eta_to_kewdale+7",
  'REVOKE ALL ON FUNCTION public.workshop_candidate_schedule_gate',
  "'20260903010000'",
]) assert.ok(sql.includes(marker), `migration contains ${marker}`);

assert.match(plannerSource, /cannot be booked before ETA \+ 7 days/);
assert.match(plannerSource, /Earliest ETA \+ 7 booking/);
console.log('Workshop ETA + 7 authority contract passed.');
