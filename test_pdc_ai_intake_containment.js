'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase/staging_only/065_pdc_ai_intake_admin_decisions.sql'), 'utf8').toLowerCase();

function functionSource(name, nextName) {
  const plain = appSource.indexOf(`function ${name}`);
  const asyncStart = appSource.indexOf(`async function ${name}`);
  const start = asyncStart >= 0 && (plain < 0 || asyncStart < plain) ? asyncStart : plain;
  const nextPlain = appSource.indexOf(`function ${nextName}`, start + 1);
  const nextAsync = appSource.indexOf(`async function ${nextName}`, start + 1);
  const normalizedNextPlain = nextAsync >= 0 && nextPlain === nextAsync + 6 ? -1 : nextPlain;
  const candidates = [normalizedNextPlain, nextAsync].filter(value => value > start);
  const end = Math.min(...candidates);
  assert(start >= 0 && Number.isFinite(end), `Unable to extract ${name}`);
  return appSource.slice(start, end);
}

assert(html.includes('Administrator approval') && html.includes('Email content is not operational authority'), 'UI must state the real authority boundary');
assert(html.includes('controlled board activation'), 'Staging UI must describe board-only activation');
assert(sql.includes('lock table public.vehicles, public.vehicle_aliases in share row exclusive mode'), 'Apply must serialize operational identity writers');
assert(sql.includes("'vehicle-master:stock_number:' || v_proposal.stock_number"), 'Apply must join the canonical Stock lock namespace');
assert(sql.includes('pdc_ai_intake_decision_receipts') && sql.includes('idempotency_conflict'), 'Durable receipt replay protection is required');
assert(!sql.includes('insert into public.workshop_bookings') && !sql.includes('update public.vehicles set'), 'Decision contract must remain board-activation only');

// Direct invocation of every legacy email-upload helper must fail closed for all roles.
for (const role of ['operator', 'importer', 'administrator']) {
  let activations = 0;
  const context = { window: { PDC_AUTH_CONTEXT: { role } }, activateSharedNavisionForApprovedDocumentReview() { activations += 1; } };
  vm.createContext(context);
  vm.runInContext(
    functionSource('activateSharedNavisionForApprovedDocumentReview', 'activateSharedNavisionForApprovedEmailReview')
      + functionSource('activateSharedNavisionForApprovedEmailReview', 'renderBackEndData'), context);
  const lowerResult = context.activateSharedNavisionForApprovedDocumentReview({ stock: 'QA' }, 'approved_email_build');
  assert.strictEqual(lowerResult.ok, false);
  assert.strictEqual(lowerResult.code, 'server_ai_intake_rpc_required');
  const result = context.activateSharedNavisionForApprovedEmailReview({ stock: 'QA' });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.code, 'server_ai_intake_rpc_required');
  assert.strictEqual(activations, 0);
}

// A late snapshot may not repopulate data after auth lock/token loss.
(async () => {
  let token = 'token-a';
  let resolveSnapshot;
  const state = {
    serverAiIntakeLifecycleGeneration: 1,
    serverAiIntakeGeneration: 0,
    serverAiIntakeRealtime: null,
    serverAiIntakeService: null,
    serverAiIntakeDecisionInFlight: false,
    serverAiIntakeRevision: null,
    serverAiIntakeNavisionRevision: null,
    serverAiIntakeError: '',
    serverAiIntakeState: 'idle',
    serverAiIntakeItems: [],
    serverAiIntakeHistory: [],
  };
  const service = { snapshot: () => new Promise(resolve => { resolveSnapshot = resolve; }) };
  const sessionData = new Map();
  const context = {
    app: state,
    window: { PDC_AUTH_CONTEXT: { role: 'administrator', userId: 'u1', email: 'admin@example.test' } },
    getPdcSupabaseAccessToken: () => token,
    renderServerAiIntake() {},
    serverAiIntakeService: () => service,
    $: () => null,
    sessionStorage: { getItem(key) { return sessionData.get(key) || null; }, setItem(key, value) { sessionData.set(key, value); } },
  };
  vm.createContext(context);
  vm.runInContext(
    functionSource('serverAiIntakeAuthMarker', 'resetServerAiIntakeAuthorityState')
      + functionSource('resetServerAiIntakeAuthorityState', 'serverAiIntakeService')
      + functionSource('refreshServerAiIntake', 'serverAuthoritativeAiIntakeEnabled'),
    context,
  );
  state.serverAiIntakeService = service;
  const pending = context.refreshServerAiIntake();
  token = '';
  context.resetServerAiIntakeAuthorityState({ clearData: true });
  resolveSnapshot({ ok: true, data: { revision: 9, navision_revision: 99, items: [{ proposal_id: 'late-secret' }], history: [] } });
  assert.strictEqual(await pending, false);
  assert.strictEqual(state.serverAiIntakeItems.length, 0);
  assert.strictEqual(state.serverAiIntakeRevision, null);
  assert.strictEqual(state.serverAiIntakeService, null);

  // One exact attempt retains its idempotency key and bound revisions.
  token = 'token-b';
  context.window.crypto = { randomUUID: () => '00000000-0000-4000-8000-000000000065' };
  state.serverAiIntakeDecisionAttempts = new Map();
  state.serverAiIntakeRevision = 3;
  state.serverAiIntakeNavisionRevision = 241;
  vm.runInContext(
    functionSource('persistServerAiIntakeDecisionAttempts', 'restoreServerAiIntakeDecisionAttempts')
      + functionSource('restoreServerAiIntakeDecisionAttempts', 'deleteServerAiIntakeDecisionAttempt')
      + functionSource('deleteServerAiIntakeDecisionAttempt', 'serverAiIntakeDecisionAttempt')
      + functionSource('serverAiIntakeDecisionAttempt', 'decideServerAiIntake'), context);
  const proposal = { proposal_id: 'p1', version: 1 };
  const first = context.serverAiIntakeDecisionAttempt(proposal, 'apply', 'exact reason');
  state.serverAiIntakeRevision = 4;
  state.serverAiIntakeDecisionAttempts = new Map(); // simulate a same-tab reload
  const retry = context.serverAiIntakeDecisionAttempt(proposal, 'apply', 'exact reason');
  assert.strictEqual(first.idempotencyKey, retry.idempotencyKey);
  assert.strictEqual(retry.proposal.inbox_revision, 3);
  assert.strictEqual(retry.proposal.navision_revision, 241);

  // The outer handler must retain the exact attempt when transport outcome is unknown.
  const outerProposal = {
    proposal_id: 'p-outer', version: 1, fingerprint: 'A1B2C3D4E5F60708',
    stock_number: 'QA-OUTER', action_type: 'board_activate_only', status: 'pending',
  };
  const alerts = [];
  state.serverAiIntakeItems = [outerProposal];
  state.serverAiIntakeHistory = [];
  state.serverAiIntakeRevision = 3;
  state.serverAiIntakeNavisionRevision = 241;
  state.serverAiIntakeService = service;
  state.serverAiIntakeDecisionAttempts = new Map();
  service.decide = async () => ({ ok: false, code: 'outcome_unknown', outcomeUnknown: true, status: 503 });
  service.snapshot = async () => ({ ok: true, data: { revision: 3, navision_revision: 241, items: [outerProposal], history: [] } });
  context.serverAiIntakeRoleCanApply = () => true;
  context.cleanNavisionText = value => String(value || '').trim();
  context.$ = selector => String(selector).includes('data-ai-intake-reason')
    ? { value: 'Administrator exact outcome unknown test' }
    : {};
  context.window.confirm = () => true;
  context.window.alert = message => alerts.push(String(message));
  vm.runInContext(functionSource('decideServerAiIntake', 'emailReviewItems'), context);
  assert.strictEqual(await context.decideServerAiIntake('p-outer', 'apply'), false);
  assert([...state.serverAiIntakeDecisionAttempts.values()].some(attempt => attempt?.proposal?.proposal_id === 'p-outer'), 'Outcome-unknown handler must retain the exact attempt');
  assert(alerts.at(-1).includes('outcome is not yet known') && !alerts.at(-1).includes('committed no change'), 'Outcome-unknown handler must make no false no-change claim');
  console.log('AI Intake behavioral authority, lifecycle, retry and SQL lock gates passed');
})().catch(error => { console.error(error); process.exit(1); });
