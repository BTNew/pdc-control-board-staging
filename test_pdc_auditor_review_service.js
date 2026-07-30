'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const start = app.indexOf('function createPdcAuditorSnapshotService');
const end = app.indexOf('function pdcAuditorCategory', start);
assert.ok(start >= 0 && end > start, 'snapshot service implementation missing');

function response(body, ok = true, status = 200) {
  return { ok, status, json: async () => body };
}

(async () => {
  let authority = 'reviewer-1';
  let token = 'token-1';
  const calls = [];
  const findingId = '11111111-1111-4111-8111-111111111111';
  const runId = '22222222-2222-4222-8222-222222222222';
  const evidence = 'a'.repeat(64);
  const queue = {
    ok: true,
    code: 'pdc_auditor_review_queue',
    environment: 'staging',
    dealer_code: '14450',
    can_decide: true,
    items: [{ finding_id: findingId, last_seen_run_id: runId, evidence_fingerprint: evidence, lifecycle_status: 'current' }],
  };
  const responses = [
    response({ response_revision: 'b'.repeat(64), generated_at: '2026-07-30T00:00:00Z', environment: 'staging', dealer_code: '14450', page_size: 100, has_more: false, next_vehicle_id: null, items: [] }),
    response(queue),
    response({ ok: true, idempotent: false, decision_id: '33333333-3333-4333-8333-333333333333', status: 'approved', operational_change: false, execution_reference: null }),
  ];
  const context = vm.createContext({
    window: {},
    auditorAuthorityIdentity: () => authority,
  });
  vm.runInContext(app.slice(start, end), context);
  const service = context.createPdcAuditorSnapshotService({
    config: { url: 'https://staging.invalid', publishableKey: 'public-key' },
    getAccessToken: () => token,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      const next = responses.shift();
      if (!next) throw new Error('unexpected fetch');
      return next;
    },
  });

  const snapshotResult = await service.getAuditorSnapshot();
  assert.strictEqual(snapshotResult.ok, true);
  assert.strictEqual(snapshotResult.snapshot.reviewCanDecide, true);
  assert.strictEqual(snapshotResult.snapshot.reviewQueue.length, 1);
  assert.ok(calls[0].url.endsWith('/rpc/get_pdc_auditor_snapshot'));
  assert.ok(calls[1].url.endsWith('/rpc/get_pdc_auditor_review_queue'));
  assert.deepStrictEqual(JSON.parse(calls[1].options.body), { p_limit: 200 });

  const decisionResult = await service.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(decisionResult.ok, true);
  assert.ok(calls[2].url.endsWith('/rpc/record_pdc_auditor_decision'));
  assert.deepStrictEqual(JSON.parse(calls[2].options.body), {
    p_finding_id: findingId,
    p_evidence_fingerprint: evidence,
    p_last_seen_run_id: runId,
    p_decision: 'approved',
    p_reason: null,
  });
  assert.strictEqual(service.getTrustedSnapshot(), null, 'a decision must invalidate the retained snapshot');

  const invalid = await service.decideFinding({ findingId: 'bad', evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(invalid.code, 'invalid_decision');
  const badReason = await service.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'denied', reason: 'x' });
  assert.strictEqual(badReason.code, 'invalid_reason');

  const unsafeService = context.createPdcAuditorSnapshotService({
    config: { url: 'https://staging.invalid', publishableKey: 'public-key' },
    getAccessToken: () => token,
    fetchImpl: async () => response({ ok: true, status: 'approved', operational_change: true, execution_reference: 'forbidden' }),
  });
  const unsafe = await unsafeService.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(unsafe.code, 'invalid_decision_receipt', 'the browser must reject an execution-bearing receipt');

  const staleService = context.createPdcAuditorSnapshotService({
    config: { url: 'https://staging.invalid', publishableKey: 'public-key' },
    getAccessToken: () => token,
    fetchImpl: async () => response({ message: 'pdc_auditor_finding_stale' }, false, 409),
  });
  const stale = await staleService.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(stale.code, 'stale');

  const committedQueue = { ...queue, items: [{ ...queue.items[0], decision: {
    decision_id: '33333333-3333-4333-8333-333333333333', status: 'approved', reason: null, operational_change: false,
  } }] };
  const reconciledResponses = [
    response({ response_revision: 'b'.repeat(64), generated_at: '2026-07-30T00:00:00Z', environment: 'staging', dealer_code: '14450', page_size: 100, has_more: false, next_vehicle_id: null, items: [] }),
    response(committedQueue),
  ];
  let dispatched = false;
  const reconciledService = context.createPdcAuditorSnapshotService({
    config: { url: 'https://staging.invalid', publishableKey: 'public-key' },
    getAccessToken: () => token,
    fetchImpl: async () => {
      if (!dispatched) { dispatched = true; throw new Error('transport lost after dispatch'); }
      return reconciledResponses.shift();
    },
  });
  const reconciled = await reconciledService.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(reconciled.ok, true, 'authoritative queue must reconcile a post-dispatch transport loss');
  assert.strictEqual(reconciled.reconciled, true);

  const unknownResponses = [
    response({ response_revision: 'b'.repeat(64), generated_at: '2026-07-30T00:00:00Z', environment: 'staging', dealer_code: '14450', page_size: 100, has_more: false, next_vehicle_id: null, items: [] }),
    response(queue),
  ];
  dispatched = false;
  const unknownService = context.createPdcAuditorSnapshotService({
    config: { url: 'https://staging.invalid', publishableKey: 'public-key' },
    getAccessToken: () => token,
    fetchImpl: async () => {
      if (!dispatched) { dispatched = true; throw new Error('transport lost after dispatch'); }
      return unknownResponses.shift();
    },
  });
  const unknown = await unknownService.decideFinding({ findingId, evidenceFingerprint: evidence, lastSeenRunId: runId, decision: 'approved' });
  assert.strictEqual(unknown.code, 'decision_outcome_unknown', 'absence after an ambiguous response must not be reported as definitive non-recording');

  authority = '';
  const unavailable = await service.getAuditorSnapshot();
  assert.strictEqual(unavailable.code, 'unavailable');
  token = '';
  service.destroy();

  console.log('AI Auditor snapshot/review service passed: queue binding, exact decision payload, stale handling and execution-bearing receipt rejection');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
