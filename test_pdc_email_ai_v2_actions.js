'use strict';

const assert = require('assert');
const {
  ACTION_RPC,
  SNAPSHOT_RPC,
  ACTION_TYPES,
  createPdcEmailAiV2Actions,
  validatePdcEmailAiV2Plan,
} = require('./pdc-email-ai-v2-actions.js');
const fs = require('fs');
const path = require('path');

const STAGING_CONFIG = {
  projectRef: 'cdsmnqxtyyoeoznmbidd',
  url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co',
};
const UUID = '483fc596-ebe2-5c89-870b-ccf375e076f5';
const DIGEST = 'a'.repeat(64);

function planFor(actionType = 'location_set', payload = { location: 'PMB', reason: 'approved staging test' }) {
  return {
    schema_version: 'pdc-email-ai-plan-v1',
    source: {
      receipt_id: UUID,
      source_digest: DIGEST,
      evidence_digest: 'b'.repeat(64),
      thread_id: 'thread-staging-test',
      message_id: 'message-staging-test',
      attachment_digests: [],
    },
    versions: {
      model: 'model-test',
      prompt: 'prompt-test',
      taxonomy: 'pdc-operation-taxonomy-proposed/v1',
      rules: 'rules-test',
      action_contract: 'pdc-email-ai-actions-v1',
      supabase_actions: '20260901020000',
    },
    instructions: [{
      instruction_id: 'instruction-1',
      vehicle_id: UUID,
      identity: {
        stock_number: '13070395',
        vin: null,
        backend_record_id: UUID,
      },
      expected_vehicle_version: 5,
      action_type: actionType,
      payload,
      evidence_refs: ['source:message-staging-test'],
    }],
  };
}

assert.ok(ACTION_TYPES.includes('activate_vehicle'));
assert.ok(ACTION_TYPES.includes('operation_add'));
assert.ok(ACTION_TYPES.includes('operation_update'));
assert.ok(ACTION_TYPES.includes('booking_cancel'));
assert.ok(ACTION_TYPES.includes('work_complete'));
assert.ok(ACTION_TYPES.includes('rft_collect'));
assert.strictEqual(require('./pdc-email-ai-v2-actions.js').isStagingConfig(STAGING_CONFIG), true);
assert.strictEqual(require('./pdc-email-ai-v2-actions.js').isStagingConfig({
  projectRef: 'vjdtsswhroyguxyfjdkt',
  url: 'https://vjdtsswhroyguxyfjdkt.supabase.co',
}), false);

const htmlEntries = ['index.html', 'staging.html']
  .map(name => ({ name, html: fs.readFileSync(path.join(__dirname, name), 'utf8') }));
const actionEntries = htmlEntries.filter(entry => entry.html.includes('pdc-email-ai-v2-actions.js'));
assert.ok(actionEntries.length >= 1, 'a staging entry must load the v2 action surface');
actionEntries.forEach(entry => {
  assert.ok(entry.html.includes('pdc-supabase-config.staging.js'), `${entry.name} must bind the action surface to staging config`);
  assert.ok(entry.html.indexOf('pdc-email-ai-v2-actions.js') < entry.html.lastIndexOf('<script src="app.js?v='), `${entry.name} must load the action surface before the app`);
});
assert.strictEqual(fs.readFileSync(path.join(__dirname, 'pdc-email-ai-v2-actions.js'), 'utf8').includes('.from('), false, 'action surface must not expose direct table DML');

const valid = validatePdcEmailAiV2Plan(planFor());
assert.strictEqual(valid.schema_version, 'pdc-email-ai-plan-v1');
assert.notStrictEqual(valid, planFor(), 'validation returns a detached plan');

assert.throws(
  () => validatePdcEmailAiV2Plan({ ...planFor(), hostile: true }),
  /keys do not match/,
  'extra top-level scope must fail closed',
);
assert.throws(
  () => validatePdcEmailAiV2Plan(planFor('location_set', { location: 'PMB', reason: 'approved staging test', table: 'vehicles' })),
  /(?:keys do not match|forbidden)/,
  'extra payload scope must fail closed',
);
assert.throws(
  () => validatePdcEmailAiV2Plan(planFor('location_set', { location: 'PMB', reason: 'approved staging test', sql: 'update public.vehicles' })),
  /forbidden/,
  'SQL-shaped payload must fail closed',
);

(async () => {
  const calls = [];
  const actions = createPdcEmailAiV2Actions({
    config: STAGING_CONFIG,
    getAccessToken: () => 'authenticated-test-token',
    rpc: async (name, params) => {
      calls.push({ name, params });
      if (name === ACTION_RPC) return { data: { ok: true, code: 'verified', actions: [] }, error: null };
      if (name === SNAPSHOT_RPC) return { data: { ok: true, code: 'ok', data: { vehicles: [] }, revision: 9 }, error: null };
      throw new Error(`unexpected RPC ${name}`);
    },
  });
  const result = await actions.applyPlan(planFor());
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.code, 'verified');
  assert.deepStrictEqual(calls.map(call => call.name), [ACTION_RPC, SNAPSHOT_RPC]);
  assert.deepStrictEqual(Object.keys(calls[0].params), ['p_plan']);
  assert.strictEqual(calls[0].params.p_plan.schema_version, 'pdc-email-ai-plan-v1');
  assert.ok(result.authoritative_readback);

  let deniedCalls = 0;
  const productionActions = createPdcEmailAiV2Actions({
    config: { projectRef: 'vjdtsswhroyguxyfjdkt', url: 'https://vjdtsswhroyguxyfjdkt.supabase.co' },
    getAccessToken: () => 'authenticated-test-token',
    rpc: async () => { deniedCalls += 1; return { data: null, error: null }; },
  });
  const productionResult = await productionActions.applyPlan(planFor());
  assert.strictEqual(productionResult.ok, false);
  assert.strictEqual(productionResult.code, 'production_target_rejected');
  assert.strictEqual(deniedCalls, 0);

  const unauthenticated = createPdcEmailAiV2Actions({
    config: STAGING_CONFIG,
    getAccessToken: () => null,
    rpc: async () => { throw new Error('must not call RPC'); },
  });
  const unauthenticatedResult = await unauthenticated.applyPlan(planFor());
  assert.strictEqual(unauthenticatedResult.ok, false);
  assert.strictEqual(unauthenticatedResult.code, 'authenticated_session_required');

  console.log('PASS: PDC Email AI v2 browser action boundary is typed, staging-only, and readback-bound');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
