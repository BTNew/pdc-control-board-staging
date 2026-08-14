'use strict';

const assert = require('assert');
const fs = require('fs');

const read = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const m225 = read('supabase/staging_only/225_ai_auditor_telegram_plans.sql');
const m230 = read('supabase/staging_only/230_auditor_authorization_hardening.sql');
const m253 = read('supabase/staging_only/253_ai_auditor_typed_operation_control.sql');
const m254 = read('supabase/staging_only/254_disable_ai_auditor_typed_operation_control.sql');
const fixture = read('tests/sql/ai_auditor_253/00_fixture.sql');

const canonicalKeys = [
  'service_identity_id',
  'service_user_id',
  'service_email',
  'admin_user_id',
  'admin_email',
  'dealer_code',
  'environment',
];
const canonicalArray = `array[${canonicalKeys.map(key => `'${key}'`).join(',')}]`;

const actorStart = m225.indexOf('create function public.pdc_auditor_telegram_actor_scope_225');
const actorEnd = m225.indexOf('revoke all on function public.pdc_auditor_telegram_actor_scope_225', actorStart);
assert(actorStart >= 0 && actorEnd > actorStart, 'migration 225 canonical actor function must be extractable');
const actor225 = m225.slice(actorStart, actorEnd);
const orderedReturn = [
  "'service_identity_id',v_service.service_identity_id",
  "'service_user_id',v_uid",
  "'service_email',v_email",
  "'admin_user_id',v_admin",
  "'admin_email',v_admin_email",
  "'dealer_code',v_service.dealer_code",
  "'environment','staging'",
];
let previous = -1;
for (const pair of orderedReturn) {
  const index = actor225.indexOf(pair);
  assert(index > previous, `migration 225 actor must return canonical ordered pair ${pair}`);
  previous = index;
}
assert.strictEqual((actor225.match(/return jsonb_build_object\(/g) || []).length, 1, 'migration 225 actor has one canonical object return');

const wrapperStart = m230.indexOf('create function public.pdc_auditor_telegram_actor_scope_225');
const wrapperEnd = m230.indexOf('revoke all on function public.pdc_auditor_telegram_actor_scope_225', wrapperStart);
assert(wrapperStart >= 0 && wrapperEnd > wrapperStart, 'migration 230 actor wrapper must be extractable');
const actor230 = m230.slice(wrapperStart, wrapperEnd);
assert(actor230.includes('v_actor:=public.pdc_auditor_telegram_actor_scope_base_225(p_telegram_sender_id);'), 'migration 230 must call the canonical 225 base actor');
assert(actor230.includes('return v_actor;'), 'migration 230 must preserve and return the canonical actor object unchanged');
assert(!actor230.includes('jsonb_set(') && !actor230.includes(' - '), 'migration 230 must not rewrite or remove actor keys');

assert.strictEqual((m253.match(/jsonb_object_keys\(actor\)\)<>7/g) || []).length, 2, 'migration 253 must require seven actor keys in replay and new-delivery paths');
assert.strictEqual(m253.split(canonicalArray).length - 1, 4, 'migration 253 must use the same canonical key set for existence and type checks in both paths');
assert.strictEqual((m253.match(/actor->>'environment'<>'staging'/g) || []).length, 2, 'migration 253 must require staging environment in both paths');
assert(!m253.includes('jsonb_object_keys(actor))<>6'), 'migration 253 must never retain the obsolete six-key contract');

for (const key of canonicalKeys) {
  assert(fixture.includes(`'${key}'`), `fixture actor must include canonical key ${key}`);
}
assert(fixture.includes("'environment','staging'"), 'fixture actor must carry canonical staging environment');

const ledger = 'canonical seven-field migration-225 actor contract preserved by migration-230';
assert(m253.includes(ledger), 'migration 253 self-ledger must declare the canonical actor dependency');
assert(m254.includes(ledger), 'migration 254 exact-ledger guard must match migration 253 actor dependency');

console.log('PASS canonical migration 225 -> 230 -> 253 seven-field actor contract and 254 ledger guard');
