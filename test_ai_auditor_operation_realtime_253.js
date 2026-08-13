'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const helperStart = source.indexOf('function pdcAuditorRealtimeRevisionId');
const helperEnd = source.indexOf('async function loadPdcAuditorSnapshot', helperStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'operation Realtime helper and subscriber must be independently executable');
const realtimeSource = source.slice(helperStart, helperEnd);
const LEGACY_RUN = '11111111-1111-4111-8111-111111111111';
const TYPED_RUN = '22222222-2222-4222-8222-222222222222';
const tick = () => new Promise(resolve => setImmediate(resolve));

function createConsumer(outcomes = []) {
  let changeHandler;
  let statusHandler;
  let registration;
  let channelName;
  let active = true;
  let authority = 'user-1|Administrator';
  let refetches = 0;
  let invalidations = 0;
  const completions = [];
  const removed = [];
  const channel = {
    on(type, options, handler) { assert.strictEqual(type, 'postgres_changes'); registration = options; changeHandler = handler; return this; },
    subscribe(handler) { statusHandler = handler; return this; },
  };
  const app = {
    pdcAuditorRealtime: null, pdcAuditorRealtimeDealer: '', pdcAuditorRealtimeGeneration: 0,
    pdcAuditorRevisionCursor: null, pdcAuditorPendingRevision: null,
    pdcAuditorRealtimePendingGeneration: 0, pdcAuditorRealtimeCoveredGeneration: 0,
    pdcAuditorRealtimePendingKeys: new Map(),
    pdcAuditorRealtimeRefreshInFlight: false, pdcAuditorRealtimeRefreshGeneration: 0, pdcAuditorGeneration: 7,
    pdcAuditorService: { invalidate() { invalidations += 1; } },
  };
  const context = vm.createContext({
    app,
    window: { PDC_SUPABASE: {
      channel(name) { channelName = name; return channel; },
      removeChannel(value) { removed.push(value); },
    } },
    document: { getElementById: id => id === 'ai-auditor' ? { classList: { contains: value => value === 'active' && active } } : null },
    auditorAuthorityIdentity: () => authority,
    loadPdcAuditorSnapshot: ({ force }) => {
      assert.strictEqual(force, true); refetches += 1;
      if (outcomes.length) return outcomes.shift();
      return new Promise(resolve => completions.push(resolve));
    },
  });
  vm.runInContext(realtimeSource, context);
  vm.runInContext("subscribePdcAuditorRealtime('14450')", context);
  return {
    app, registration: () => registration, channelName: () => channelName,
    emit: payload => changeHandler(payload), refetches: () => refetches,
    status: value => statusHandler(value), setActive: value => { active = value; },
    setAuthority: value => { authority = value; },
    invalidations: () => invalidations, completions, removed,
    reset: () => vm.runInContext('resetPdcAuditorRealtimeSubscription()', context),
    refresh: () => vm.runInContext("refreshPdcAuditorAfterRealtimeInvalidation(app.pdcAuditorRealtimeGeneration, auditorAuthorityIdentity(), app.pdcAuditorRealtimeDealer)", context),
  };
}

function event(revision, eventType, options = {}) {
  const typed = eventType.startsWith('typed_');
  return { eventType: options.transportEvent || 'INSERT', new: {
    revision_id: revision, dealer_code: options.dealer || '14450',
    environment: options.environment || 'staging', event_type: eventType,
    run_id: typed ? null : (options.runId === undefined ? LEGACY_RUN : options.runId),
    rollback_receipt_id: eventType === 'telegram_run_rolled_back_226'
      ? (options.rollbackReceiptId === undefined ? '33333333-3333-4333-8333-333333333333' : options.rollbackReceiptId)
      : null,
    typed_run_id_253: typed ? (options.typedRunId === undefined ? TYPED_RUN : options.typedRunId) : null,
  } };
}

(async () => {
  const first = createConsumer();
  const second = createConsumer();
  for (const consumer of [first, second]) {
    assert.strictEqual(consumer.channelName(), 'pdc_auditor_workshop_revisions_read_only');
    assert.deepStrictEqual(JSON.parse(JSON.stringify(consumer.registration())), {
      event: 'INSERT', schema: 'public', table: 'pdc_auditor_workshop_revisions', filter: 'dealer_code=eq.14450',
    });
  }

  first.emit(event(101, 'typed_plan_applied_253'));
  second.emit(event(101, 'typed_plan_applied_253'));
  await tick();
  assert.strictEqual(first.refetches(), 1);
  assert.strictEqual(second.refetches(), 1);
  first.emit(event(102, 'typed_run_undone_253'));
  first.emit(event(103, 'telegram_plan_applied_226'));
  first.emit(event(99, 'typed_plan_applied_253'));
  assert.strictEqual(first.refetches(), 1, 'overlapping invalidations must coalesce while fetch is active');
  first.completions.shift()(true);
  await tick();
  assert.strictEqual(first.app.pdcAuditorRevisionCursor, '101');
  assert.strictEqual(first.refetches(), 2, 'one trailing authoritative refresh must cover coalesced events');
  first.completions.shift()(true);
  await tick();
  assert.strictEqual(first.app.pdcAuditorRevisionCursor, '103');
  first.emit(event(103, 'telegram_plan_applied_226'));
  await tick();
  assert.strictEqual(first.refetches(), 2, 'duplicate revision must not refetch');

  const failure = createConsumer([Promise.resolve(false), Promise.resolve(true)]);
  failure.emit(event(201, 'typed_plan_applied_253'));
  await tick();
  assert.strictEqual(failure.app.pdcAuditorRevisionCursor, null, 'failed refetch must never advance cursor');
  assert.strictEqual(failure.app.pdcAuditorPendingRevision, '201', 'failed refetch must retain invalidation');
  assert.strictEqual(failure.refetches(), 1, 'failure must not recursively spin');
  failure.emit(event(202, 'typed_run_undone_253'));
  await tick();
  assert.strictEqual(failure.app.pdcAuditorRevisionCursor, '202', 'later successful authoritative refresh advances through pending head');

  const sameRun = createConsumer([Promise.resolve(true), Promise.resolve(true)]);
  sameRun.emit(event(211, 'typed_plan_applied_253'));
  await tick();
  sameRun.emit(event(212, 'typed_run_undone_253'));
  await tick();
  assert.strictEqual(sameRun.refetches(), 2, 'apply and undo for the same typed run are distinct invalidations');

  const acceptedTypes = ['telegram_plan_applied_226', 'telegram_run_rolled_back_226', 'typed_plan_applied_253', 'typed_run_undone_253'];
  for (const [index, type] of acceptedTypes.entries()) {
    const consumer = createConsumer([Promise.resolve(true)]);
    consumer.emit(event(300 + index, type));
    await tick();
    assert.strictEqual(consumer.refetches(), 1, `${type} must invalidate`);
  }

  const ignored = createConsumer([]);
  ignored.emit(event(401, 'typed_plan_applied_253', { environment: 'production' }));
  ignored.emit(event(402, 'typed_plan_applied_253', { typedRunId: 'not-a-uuid' }));
  ignored.emit(event(403, 'telegram_plan_applied_226', { runId: null }));
  ignored.emit(event(404, 'typed_run_undone_253', { dealer: '37047' }));
  ignored.emit(event(405, 'typed_run_undone_253', { transportEvent: 'UPDATE' }));
  await tick();
  assert.strictEqual(ignored.refetches(), 0, 'wrong environment/dealer/event and malformed run identities must fail closed');

  const hidden = createConsumer([Promise.resolve(true)]);
  hidden.setActive(false);
  hidden.emit(event(501, 'typed_plan_applied_253'));
  await tick();
  assert.strictEqual(hidden.refetches(), 0, 'hidden view invalidates without fetching');
  assert.strictEqual(hidden.invalidations(), 1);
  assert.strictEqual(hidden.app.pdcAuditorRevisionCursor, null, 'hidden invalidation must not silently advance cursor');
  hidden.setActive(true);
  hidden.refresh();
  await tick();
  assert.strictEqual(hidden.refetches(), 1, 'pending hidden invalidation refreshes when shown');

  const reconciliation = createConsumer([Promise.resolve(true)]);
  reconciliation.status('SUBSCRIBED');
  await tick();
  assert.strictEqual(reconciliation.refetches(), 1, 'SUBSCRIBED must reconcile the snapshot/subscription race once');
  reconciliation.status('SUBSCRIBED');
  await tick();
  assert.strictEqual(reconciliation.refetches(), 1, 'duplicate status acknowledgement must not reconcile twice');

  const channelFailure = createConsumer([Promise.resolve(true)]);
  channelFailure.status('CHANNEL_ERROR');
  await tick();
  assert.strictEqual(channelFailure.removed.length, 1, 'channel failure tears down the failed channel');
  assert.strictEqual(channelFailure.refetches(), 1, 'active channel failure reconciles authoritatively');

  const stale = createConsumer([]);
  stale.reset();
  stale.emit(event(601, 'typed_plan_applied_253'));
  stale.status('SUBSCRIBED');
  await tick();
  assert.strictEqual(stale.refetches(), 0, 'teardown generation-guards stale data and status callbacks');

  for (const consumer of [first, second]) {
    consumer.reset();
    assert.strictEqual(consumer.app.pdcAuditorRevisionCursor, null);
    assert.strictEqual(consumer.app.pdcAuditorPendingRevision, null);
    assert.strictEqual(consumer.removed.length, 1);
  }
  console.log('AI Auditor migration-253 serialized two-consumer Realtime contracts passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
