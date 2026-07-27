'use strict';

const {
  NAVISION_STAGING_PROJECT_REF,
  NAVISION_REVISION_TABLE,
  createNavisionRpcClient,
  createNavisionBackendService,
} = require('./navision-backend-service.js');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

(async () => {
  let productionBlocked = false;
  try {
    createNavisionRpcClient({ url: 'https://vjdtsswhroyguxyfjdkt.supabase.co', publishableKey: 'test' }, async () => null);
  } catch (error) {
    productionBlocked = /staging-only/.test(error.message);
  }
  assert(productionBlocked, 'Exact project guard must block production');
  let injectedClientBlocked = false;
  try {
    createNavisionBackendService({
      projectRef: NAVISION_STAGING_PROJECT_REF,
      client: { projectRef: 'vjdtsswhroyguxyfjdkt', rpc: async () => ({}) },
    });
  } catch (error) {
    injectedClientBlocked = /staging-only/.test(error.message);
  }
  assert(injectedClientBlocked, 'A production-tagged injected client must not bypass the staging guard');

  const calls = [];
  const receipt = { ok: true, data: { receipt_id: 'receipt-1', batch_id: 'batch-1', result_revision: 2 } };
  const client = {
    projectRef: NAVISION_STAGING_PROJECT_REF,
    async rpc(token, name, params) {
      calls.push({ token, name, params: JSON.parse(JSON.stringify(params)) });
      if (name === 'preview_navision_backend_import') {
        return { ok: true, status: 200, body: { ok: true, data: {
          base_revision: 1,
          source_hash: 'a'.repeat(64),
          preview_hash: 'b'.repeat(64),
          blocking: false,
          counts: { total: 2, new: 2, changed: 0, unchanged: 0, missing: 0, invalid: 0, conflict: 0 },
          operational_mutations: 0,
        } } };
      }
      if (name === 'apply_navision_backend_import') return { ok: true, status: 200, body: receipt };
      return { ok: true, status: 200, body: { ok: true, data: { rows: [], revision: 2 } } };
    },
  };
  const subscribers = [];
  const subscribeRealtime = (table, handlers) => {
    assert(table === NAVISION_REVISION_TABLE, 'Realtime must subscribe only to the revision signal');
    subscribers.push(handlers);
    return { unsubscribe() {} };
  };
  const first = createNavisionBackendService({ client, projectRef: NAVISION_STAGING_PROJECT_REF, getAccessToken: () => 'token-a', subscribeRealtime });
  const second = createNavisionBackendService({ client, projectRef: NAVISION_STAGING_PROJECT_REF, getAccessToken: () => 'token-b', subscribeRealtime });
  assert(first.browserLocalAuthorityCutover === false, 'Service must declare no browser-local authority cutover');

  const rows = [{ id: 'SYN-1' }, { id: 'SYN-2' }];
  const missingDealer = await first.preview(rows, { sourceName: 'synthetic.json' });
  assert(!missingDealer.ok && missingDealer.error === 'invalid_dealer_code', 'Missing dealer scope must fail closed before RPC');
  const preview = await first.preview(rows, { sourceName: 'synthetic.json', dealerCode: '14450' });
  assert(preview.ok && preview.data.data.operational_mutations === 0, 'Preview must be read-only and report zero operational mutations');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_dealer_code', 'p_rows', 'p_source_name', 'p_source_system', 'p_source_timestamp']), 'Preview parameter keys must exactly match its scoped SQL signature');
  const initialScopeApproval = await first.approveInitialScope(rows, { dealerCode: '14450' });
  assert(initialScopeApproval.ok && calls.at(-1).name === 'approve_navision_initial_scope', 'First dealer baseline review must use the protected approval RPC');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_dealer_code', 'p_rows', 'p_source_system']), 'Initial scope approval must be bound to the exact rows and dealer scope');
  const unconfirmed = await first.apply(rows, preview, { idempotencyKey: 'apply-1' });
  assert(!unconfirmed.ok && unconfirmed.error === 'explicit_confirmation_required', 'Apply must require explicit confirmation');
  const truthyButNotExplicit = await first.apply(rows, preview, { idempotencyKey: 'apply-1', confirmed: 'yes' });
  assert(!truthyButNotExplicit.ok && truthyButNotExplicit.error === 'explicit_confirmation_required', 'Apply confirmation must be the boolean true, not a truthy substitute');

  const options = { idempotencyKey: 'apply-1', sourceName: 'synthetic.json', sourceSystem: 'microsoft_navision', dealerCode: '14450', confirmed: true };
  const applied = await first.apply(rows, preview, options);
  const replayed = await first.apply(rows, preview, options);
  assert(applied.data.data.batch_id === 'batch-1' && JSON.stringify(applied.data) === JSON.stringify(replayed.data), 'Identical replay must return the same durable receipt');
  const applyCalls = calls.filter(call => call.name === 'apply_navision_backend_import');
  assert(JSON.stringify(Object.keys(applyCalls[0].params).sort()) === JSON.stringify(['p_dealer_code', 'p_expected_revision', 'p_idempotency_key', 'p_preview_hash', 'p_rows', 'p_source_hash', 'p_source_name', 'p_source_system', 'p_source_timestamp']), 'Apply parameter keys must exactly match its scoped SQL signature');
  assert(JSON.stringify(applyCalls[0].params) === JSON.stringify(applyCalls[1].params), 'Response-loss retry must send the identical request contract');

  const contradictoryPreview = JSON.parse(JSON.stringify(preview));
  contradictoryPreview.data.data.blocking = true;
  contradictoryPreview.data.data.counts = { ...contradictoryPreview.data.data.counts, invalid: 0, conflict: 0 };
  contradictoryPreview.data.data.items = [{ classification: 'changed' }, { classification: 'unchanged' }];
  const reconciled = await first.apply(rows, contradictoryPreview, { ...options, idempotencyKey: 'apply-reconciled' });
  assert(reconciled.ok, 'A stale blocking flag must not prevent server revalidation when exact counts and items contain zero blocking rows');
  const safetyBlockedPreview = JSON.parse(JSON.stringify(contradictoryPreview));
  safetyBlockedPreview.data.data.safety = { blocking: true, reason: 'suspicious_partial_snapshot' };
  const callsBeforeSafetyBlock = calls.length;
  const safetyBlocked = await first.apply(rows, safetyBlockedPreview, { ...options, idempotencyKey: 'apply-safety-blocked' });
  assert(!safetyBlocked.ok && safetyBlocked.error === 'preview_has_blocking_issues' && safetyBlocked.data.safetyReason === 'suspicious_partial_snapshot' && calls.length === callsBeforeSafetyBlock, 'A structured server safety block must never be reconciled away as a stale top-level flag');
  const trulyBlockedPreview = JSON.parse(JSON.stringify(preview));
  trulyBlockedPreview.data.data.blocking = false;
  trulyBlockedPreview.data.data.counts = { ...trulyBlockedPreview.data.data.counts, invalid: 1, conflict: 0 };
  trulyBlockedPreview.data.data.items = [{ classification: 'invalid' }];
  const callsBeforeBlocked = calls.length;
  const trulyBlocked = await first.apply(rows, trulyBlockedPreview, { ...options, idempotencyKey: 'apply-blocked' });
  assert(!trulyBlocked.ok && trulyBlocked.error === 'preview_has_blocking_issues' && calls.length === callsBeforeBlocked, 'Invalid/conflicting rows must still fail closed before the apply RPC');

  let firstRevision = null;
  let secondRevision = null;
  first.subscribe(revision => { firstRevision = revision; });
  second.subscribe(revision => { secondRevision = revision; });
  subscribers.forEach(handler => handler.onChange({ new: { revision: 3 } }));
  assert(firstRevision === 3 && secondRevision === 3, 'Two browser clients must observe the same revision signal');

  await first.snapshot({ sourceSystem: 'microsoft_navision', dealerCode: '14450' }, {}, 9999, 3);
  const snapshotCall = calls.at(-1);
  assert(snapshotCall.name === 'get_navision_backend_snapshot' && JSON.stringify(Object.keys(snapshotCall.params).sort()) === JSON.stringify(['p_after_record_id', 'p_after_source_record_id', 'p_dealer_code', 'p_expected_revision', 'p_page_size', 'p_source_system']), 'Snapshot parameter keys must exactly match its dealer-scoped composite-cursor SQL signature');
  assert(snapshotCall.params.p_page_size === 500, 'Read contracts must cap export/snapshot pages at 500');
  await first.visibleSnapshot({ sourceSystem: 'microsoft_navision', dealerCode: '14450' }, { recordId: '00000000-0000-4000-8000-000000000008' }, 9999, 3);
  const visibleSnapshotCall = calls.at(-1);
  assert(visibleSnapshotCall.name === 'get_navision_visible_snapshot' && JSON.stringify(Object.keys(visibleSnapshotCall.params).sort()) === JSON.stringify(['p_after_record_id', 'p_dealer_code', 'p_expected_revision', 'p_page_size', 'p_source_system']), 'Approved-user visible snapshot must use the restricted opaque UUID cursor contract');
  assert(visibleSnapshotCall.params.p_page_size === 500 && visibleSnapshotCall.params.p_after_record_id, 'Visible snapshot must cap pages and preserve its opaque cursor');
  await first.exportRecords({ sourceSystem: 'microsoft_navision', dealerCode: '37047' }, { sourceRecordId: 'NAV-9', recordId: '00000000-0000-0000-0000-000000000009' }, 9999, 3);
  const exportCall = calls.at(-1);
  assert(exportCall.name === 'export_navision_backend_records' && JSON.stringify(Object.keys(exportCall.params).sort()) === JSON.stringify(['p_after_record_id', 'p_after_source_record_id', 'p_dealer_code', 'p_expected_revision', 'p_page_size', 'p_source_system']), 'Export parameter keys must exactly match its dealer-scoped composite-cursor SQL signature');
  assert(exportCall.params.p_dealer_code === '37047' && exportCall.params.p_after_record_id, 'Export must preserve exact dealer scope and both cursor components');
  await first.reconciliation('batch-1', 12, 9999);
  const reconciliationCall = calls.at(-1);
  assert(JSON.stringify(Object.keys(reconciliationCall.params).sort()) === JSON.stringify(['p_after_row_index', 'p_batch_id', 'p_page_size']) && reconciliationCall.params.p_after_row_index === 12 && reconciliationCall.params.p_page_size === 500, 'Reconciliation parameters must exactly match the SQL RPC contract');
  await first.link('record-1', 'vehicle-1', 3, 'link-1');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_backend_record_id', 'p_canonical_vehicle_id', 'p_expected_revision', 'p_idempotency_key']) && calls.at(-1).params.p_backend_record_id === 'record-1', 'Link parameters must exactly match the protected SQL RPC contract');
  await first.activate('record-1', 3, 'activate-1', 'manual');
  assert(calls.at(-1).name === 'activate_navision_backend_record' && JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_activation_source', 'p_backend_record_id', 'p_expected_revision', 'p_idempotency_key']), 'Activation parameters must exactly match the protected SQL RPC contract');
  await first.rollback('batch-1', 3, 'rollback-1');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_expected_revision', 'p_idempotency_key', 'p_target_batch_id']) && calls.at(-1).params.p_target_batch_id === 'batch-1', 'Rollback parameters must exactly match the SQL RPC contract');

  console.log('Shared Navision staging guard, preview/apply confirmation, exact replay and two-browser contract checks passed');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
