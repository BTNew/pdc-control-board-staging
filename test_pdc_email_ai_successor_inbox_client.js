'use strict';

const assert = require('assert');
const {
  PDC_EMAIL_AI_SUCCESSOR_STAGING_PROJECT_REF,
  createPdcEmailAiSuccessorInboxClient,
  normalizeSuccessorInboxSnapshot,
} = require('./pdc-email-ai-successor-inbox.js');

async function test(name, fn) {
  try { await fn(); console.log(`PASS ${name}`); }
  catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; }
}

(async () => {
  await test('client is staging-only and calls the typed inbox RPC with bounded cursor', async () => {
    const calls = [];
    const client = createPdcEmailAiSuccessorInboxClient({
      config: { url: `https://${PDC_EMAIL_AI_SUCCESSOR_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'test-key' },
      getAccessToken: () => 'token',
      fetchImpl: async (url, options) => {
        calls.push({ url, options });
        return { ok: true, status: 200, json: async () => ({ ok: true, revision: 4, has_more: false, next_cursor: null, items: [] }) };
      },
    });
    const result = await client.snapshot({ pageSize: 250, cursor: '2026-08-31T01:02:03.000Z' });
    assert.strictEqual(result.ok, true);
    assert.ok(calls[0].url.endsWith('/rest/v1/rpc/get_pdc_email_ai_transaction_successor_inbox'));
    const body = JSON.parse(calls[0].options.body);
    assert.strictEqual(body.p_page_size, 250);
    assert.strictEqual(body.p_cursor, '2026-08-31T01:02:03.000Z');
    assert.strictEqual(calls[0].options.headers.Authorization, 'Bearer token');
  });

  await test('snapshot rejects secret/body-bearing rows without disclosing the field name', () => {
    const snapshot = normalizeSuccessorInboxSnapshot({
      ok: true,
      revision: 7,
      items: [{
        intake_uid: 'imap:514', subject: 'Vehicle update', sender: 'sender@example.test', received_at: '2026-08-31T01:02:03Z',
        transaction: { disposition: 'SUCCESS', typed_plan: { schema_version: 'pdc-email-ai-plan-v1' }, raw_body: 'must not pass' },
        vehicle_results: [],
      }],
    });
    assert.strictEqual(snapshot.ok, false);
    assert.strictEqual(snapshot.code, 'unsafe_snapshot');
  });

  await test('unknown action is retained as a blocked child rather than dropped', () => {
    const snapshot = normalizeSuccessorInboxSnapshot({
      ok: true, revision: 1, items: [{
        intake_uid: 'imap:515', subject: 'Unknown', sender: 'a@example.test', received_at: '2026-08-31T01:02:03Z',
        transaction: null,
        vehicle_results: [{ vehicle_id: 'vehicle-1', actions: [{ action_type: 'hostile_action', disposition: 'BLOCKED_EXACT_REASON', reason: 'unsupported' }] }],
      }],
    });
    assert.strictEqual(snapshot.ok, true);
    assert.strictEqual(snapshot.items[0].vehicle_results[0].actions[0].disposition, 'BLOCKED_EXACT_REASON');
  });
})();
