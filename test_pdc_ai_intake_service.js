'use strict';
const {
  PDC_AI_INTAKE_STAGING_PROJECT_REF,
  PDC_AI_INTAKE_REVISION_TABLE,
  createPdcAiIntakeRpcClient,
  createPdcAiIntakeService,
} = require('./pdc-ai-intake-service.js');

function assert(value, message) { if (!value) throw new Error(message); }

(async () => {
  let blocked = false;
  try { createPdcAiIntakeRpcClient({ url: 'https://vjdtsswhroyguxyfjdkt.supabase.co', publishableKey: 'x' }, async () => null); }
  catch (error) { blocked = /staging-only/.test(error.message); }
  assert(blocked, 'Production project must be blocked');

  const stagingConfig = { url: `https://${PDC_AI_INTAKE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'x' };
  const thrownClient = createPdcAiIntakeRpcClient(stagingConfig, async () => { throw new Error('connection reset'); });
  const thrown = await thrownClient.rpc('token', 'decision', {});
  assert(thrown.ambiguous === true && thrown.status === 0, 'Thrown transport must be outcome-ambiguous');
  const emptyClient = createPdcAiIntakeRpcClient(stagingConfig, async () => ({ ok: true, status: 200, async json() { throw new Error('empty'); } }));
  const empty = await emptyClient.rpc('token', 'decision', {});
  assert(empty.ambiguous === true, 'Unreadable successful response must be outcome-ambiguous');
  for (const status of [408, 425, 429, 500, 502, 503, 504, 599]) {
    const gatewayClient = createPdcAiIntakeRpcClient(stagingConfig, async () => ({
      ok: false,
      status,
      async json() { return { message: 'gateway response is not commit evidence' }; },
    }));
    const gateway = await gatewayClient.rpc('token', 'decision', {});
    assert(gateway.ambiguous === true, `HTTP ${status} must be outcome-ambiguous`);
    const gatewayService = createPdcAiIntakeService({
      config: stagingConfig,
      client: gatewayClient,
      getAccessToken: () => 'staff-token',
    });
    const gatewayOutcome = await gatewayService.decide(
      { proposal_id: '00000000-0000-4000-8000-000000000001', version: 1, inbox_revision: 3, navision_revision: 241, action_type: 'board_activate_only', fingerprint: 'A1B2C3D4E5F60708' },
      'apply',
      'Administrator independently approved exact live activation',
      'pdc-ai-intake-00000000-0000-4000-8000-000000000009',
    );
    assert(gatewayOutcome.outcomeUnknown === true && gatewayOutcome.code === 'outcome_unknown', `HTTP ${status} must retain same-key reconciliation`);
  }
  const unreadableGatewayClient = createPdcAiIntakeRpcClient(stagingConfig, async () => ({ ok: false, status: 504, async json() { throw new Error('unreadable'); } }));
  assert((await unreadableGatewayClient.rpc('token', 'decision', {})).ambiguous === true, 'Unreadable HTTP 504 must be outcome-ambiguous');

  const calls = [];
  const client = {
    projectRef: PDC_AI_INTAKE_STAGING_PROJECT_REF,
    async rpc(token, name, params) {
      calls.push({ token, name, params });
      if (name === 'get_pdc_ai_intake_snapshot') return { ok: true, status: 200, body: { ok: true, data: { revision: 3, items: [], history: [] } } };
      return { ok: true, status: 200, body: { ok: true, code: 'board_activated', data: { activated: true } } };
    },
  };
  let subscribed = null;
  const service = createPdcAiIntakeService({
    config: { url: `https://${PDC_AI_INTAKE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'x' },
    client,
    getAccessToken: () => 'staff-token',
    subscribeRealtime(table, callback) { subscribed = { table, callback }; return { unsubscribe() {} }; },
  });
  assert(service.authority === 'supabase_staging_ai_intake_only', 'Authority marker must be server-only staging');
  assert((await service.snapshot('pending', 999)).ok, 'Snapshot should succeed');
  assert(calls[0].name === 'get_pdc_ai_intake_snapshot' && calls[0].params.p_page_size === 250, 'Snapshot must call exact bounded RPC');
  assert((await service.monitorStatus()).ok, 'Authenticated Monitor status should succeed');
  assert(calls[1].name === 'get_pdc_email_monitor_status' && Object.keys(calls[1].params).length === 0, 'Monitor status must call exact zero-argument staging RPC');
  const proposal = { proposal_id: '00000000-0000-4000-8000-000000000001', version: 1, inbox_revision: 3, navision_revision: 241, action_type: 'board_activate_only', fingerprint: 'A1B2C3D4E5F60708' };
  const key = 'pdc-ai-intake-00000000-0000-4000-8000-000000000009';
  const shortReason = await service.decide(proposal, 'apply', 'short', key);
  assert(!shortReason.ok && shortReason.code === 'decision_reason_required', 'Decision reason must fail closed locally');
  const decision = await service.decide(proposal, 'apply', 'Administrator independently approved exact live activation', key);
  assert(decision.ok && calls.at(-1).name === 'decide_pdc_ai_intake_proposal', 'Apply must use the protected decision RPC');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_idempotency_key','p_proposal_id','p_expected_version','p_expected_inbox_revision','p_expected_action','p_decision','p_fingerprint','p_expected_navision_revision','p_reason'].sort()), 'Decision RPC shape must remain exact');
  assert(calls.at(-1).params.p_expected_navision_revision === 241 && calls.at(-1).params.p_expected_inbox_revision === 3, 'Decision must bind exact inbox and Navision revisions');
  client.rpc = async () => ({ ok: false, status: 0, ambiguous: true, body: null });
  const unknown = await service.decide(proposal, 'apply', 'Administrator independently approved exact live activation', key);
  assert(!unknown.ok && unknown.outcomeUnknown === true && unknown.code === 'outcome_unknown', 'Ambiguous transport must never be reported as a definitive rejection');
  let revision = null;
  service.subscribe(value => { revision = value; });
  assert(subscribed.table === PDC_AI_INTAKE_REVISION_TABLE, 'Realtime must subscribe only to AI Intake revision');
  subscribed.callback({ new: { revision: 4 } });
  assert(revision === 4, 'Realtime revision must propagate');
  console.log('AI Intake staging guard, snapshot, exact decision and realtime checks passed');
})().catch(error => { console.error(error); process.exit(1); });
