'use strict';
// r417 (F32): a bay rule that does not match warns; the planner confirms; the override is logged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { workshopConfirmBayRuleWarning, workshopBayRuleQuestion } = require('./workshop-shared-actions.js');
const layout = require('./pdc-workshop-departments.js');
const read = f => fs.readFileSync(path.join(__dirname, f), 'utf8');
const planner = read('workshop-planner.js');
const mig = read('supabase/migrations/20261020233617_r417_bay_rule_warn_confirm.sql');
const down = read('supabase/rollbacks/20261020233617_r417_bay_rule_warn_confirm.down.sql');

const warning = { ok: false, warning: true, requires_confirmation: true, error: 'bay_rule_warning',
  rules: [{ rule: 'category_bay_mismatch', message: 'Bay 8 is set up for Electrical work, and this booking is Mechanical work.' }] };

test('a warning is shown and a confirmed change is sent once more, confirmed, with a new request ID', async () => {
  const calls = [];
  const mutate = async (name, params) => { calls.push({ name, params }); return calls.length === 1 ? warning : { ok: true }; };
  const asked = [];
  const result = await workshopConfirmBayRuleWarning(mutate, 'administrator_move_workshop_booking',
    { p_booking_id: 'b1', p_metadata: { source: 'drag' }, p_request_id: 'r1' }, question => { asked.push(question); return true; });
  assert.equal(result.ok, true);
  assert.equal(calls.length, 2);
  assert.match(asked[0], /Bay 8 is set up for Electrical work/);
  assert.match(asked[0], /override is logged/);
  assert.deepEqual(calls[1].params.p_metadata, { source: 'drag', bay_rule_confirm: { rules: ['category_bay_mismatch'] } });
  assert.notEqual(calls[1].params.p_request_id, 'r1');
  assert.match(calls[1].params.p_request_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('Cancel leaves everything as it is', async () => {
  let n = 0;
  const result = await workshopConfirmBayRuleWarning(async () => { n += 1; return warning; }, 'administrator_schedule_workshop_vehicle', { p_metadata: {} }, () => false);
  assert.equal(n, 1);
  assert.equal(result.error, 'bay_rule_not_confirmed');
});

test('errors and successes pass straight through', async () => {
  for (const body of [{ ok: true }, { ok: false, error: 'bay_overlap' }, { ok: false, error: 'protected_booking' }]) {
    let n = 0;
    const result = await workshopConfirmBayRuleWarning(async () => { n += 1; return body; }, 'x', {}, () => { throw new Error('must not ask'); });
    assert.equal(n, 1); assert.deepEqual(result, body);
  }
  assert.match(workshopBayRuleQuestion(warning), /^This bay's rule does not match:/);
});

function extract(name) {
  const start = planner.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  const open = planner.indexOf(') {', start) + 2;
  let depth = 0;
  for (let i = open; i < planner.length; i += 1) {
    if (planner[i] === '{') depth += 1;
    if (planner[i] === '}') { depth -= 1; if (depth === 0) return planner.slice(start, i + 1); }
  }
  throw new Error(name);
}
const ctx = { workshopDepartmentLayout: () => layout };
vm.createContext(ctx);
vm.runInContext(extract('workshopBayAwareCategory') + '\nthis.pick=workshopBayAwareCategory;', ctx);
const cats = [
  { work_category: 'BUS_MECHANICAL', estimated_hours: 54.7, schedule_enabled: true, existing_booking: false, completed: false },
  { work_category: 'BUS_ELECTRICAL', estimated_hours: 6.2, schedule_enabled: true, existing_booking: false, completed: false },
];

test('dropping on Bay 8 books the outstanding Electrical work instead of warning (Key 509)', () => {
  const pick = ctx.pick({ workCategory: 'BUS_MECHANICAL', workCategories: cats }, 'BUS_4X4', 8);
  assert.equal(pick.code, 'BUS_ELECTRICAL');
  assert.equal(pick.minutes, 372);
  assert.equal(ctx.pick({ workCategory: 'BUS_MECHANICAL', workCategories: cats }, 'BUS_4X4', 2), null, 'Bay 2 takes Mechanical');
  assert.equal(ctx.pick({ workCategory: 'BUS_MECHANICAL', workCategories: [cats[0], { ...cats[1], existing_booking: true }] }, 'BUS_4X4', 8), null, 'already booked: the server warns');
  assert.equal(ctx.pick({ workCategory: 'BUS_MECHANICAL', workCategories: cats }, 'HOIST', 8), null);
});

test('Schedule offers the category bays first, then every other visible bay with a confirm note', () => {
  assert.match(planner, /const otherBays = workshopVisibleBays\(normalizedStage\)\.filter\(number => !categoryBays\.includes\(number\)\);/);
  assert.match(planner, /\(other work – asks to confirm\)/);
});

test('migration is staging only, keeps the rules, and logs overrides', () => {
  assert.match(mig, /project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.equal(/vjdtsswhroyguxyfjdkt/.test(mig), false);
  assert.match(mig, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.match(mig, /'requires_confirmation',true,'error','bay_rule_warning'/);
  assert.match(mig, /CREATE TABLE pdc_bay_rules_private\.overrides/);
  assert.match(mig, /REVOKE ALL ON pdc_bay_rules_private\.overrides FROM PUBLIC, anon, authenticated/);
  assert.match(mig, /coalesce\(jsonb_typeof\(p_metadata->'bay_rule_confirm'->'rules'\)='array'/, 'no confirmation means not confirmed');
  assert.equal(/CREATE OR REPLACE FUNCTION pdc_work_categories_private\.(allowed_bay|preferred_bay)/.test(mig), false, 'rules unchanged');
  assert.match(down, /DROP SCHEMA pdc_bay_rules_private CASCADE/);
  assert.match(down, /55e1810fd2a47a29c9608a55ae292741/, 'undo asserts the original Bay 3 rule');
});
