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
  const preview = await first.preview(rows, { sourceName: 'synthetic.json' });
  assert(preview.ok && preview.data.data.operational_mutations === 0, 'Preview must be read-only and report zero operational mutations');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_rows', 'p_source_name', 'p_source_timestamp']), 'Preview parameter keys must exactly match its SQL signature');
  const unconfirmed = await first.apply(rows, preview, { idempotencyKey: 'apply-1' });
  assert(!unconfirmed.ok && unconfirmed.error === 'explicit_confirmation_required', 'Apply must require explicit confirmation');

  const options = { idempotencyKey: 'apply-1', sourceName: 'synthetic.json', confirmed: true };
  const applied = await first.apply(rows, preview, options);
  const replayed = await first.apply(rows, preview, options);
  assert(applied.data.data.batch_id === 'batch-1' && JSON.stringify(applied.data) === JSON.stringify(replayed.data), 'Identical replay must return the same durable receipt');
  const applyCalls = calls.filter(call => call.name === 'apply_navision_backend_import');
  assert(JSON.stringify(Object.keys(applyCalls[0].params).sort()) === JSON.stringify(['p_expected_revision', 'p_idempotency_key', 'p_preview_hash', 'p_rows', 'p_source_hash', 'p_source_name', 'p_source_timestamp']), 'Apply parameter keys must exactly match its SQL signature');
  assert(JSON.stringify(applyCalls[0].params) === JSON.stringify(applyCalls[1].params), 'Response-loss retry must send the identical request contract');

  let firstRevision = null;
  let secondRevision = null;
  first.subscribe(revision => { firstRevision = revision; });
  second.subscribe(revision => { secondRevision = revision; });
  subscribers.forEach(handler => handler.onChange({ new: { revision: 3 } }));
  assert(firstRevision === 3 && secondRevision === 3, 'Two browser clients must observe the same revision signal');

  await first.snapshot('', 9999, 3);
  const snapshotCall = calls.at(-1);
  assert(snapshotCall.name === 'get_navision_backend_snapshot' && JSON.stringify(Object.keys(snapshotCall.params).sort()) === JSON.stringify(['p_after_source_record_id', 'p_expected_revision', 'p_page_size']), 'Snapshot parameter keys must exactly match its SQL signature');
  assert(snapshotCall.params.p_page_size === 500, 'Read contracts must cap export/snapshot pages at 500');
  await first.exportRecords('NAV-9', 9999, 3);
  const exportCall = calls.at(-1);
  assert(exportCall.name === 'export_navision_backend_records' && JSON.stringify(Object.keys(exportCall.params).sort()) === JSON.stringify(['p_after_source_record_id', 'p_expected_revision', 'p_page_size']), 'Export parameter keys must exactly match its SQL signature');
  await first.reconciliation('batch-1', 12, 9999);
  const reconciliationCall = calls.at(-1);
  assert(JSON.stringify(Object.keys(reconciliationCall.params).sort()) === JSON.stringify(['p_after_row_index', 'p_batch_id', 'p_page_size']) && reconciliationCall.params.p_after_row_index === 12 && reconciliationCall.params.p_page_size === 500, 'Reconciliation parameters must exactly match the SQL RPC contract');
  await first.link('record-1', 'vehicle-1', 3, 'link-1');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_backend_record_id', 'p_canonical_vehicle_id', 'p_expected_revision', 'p_idempotency_key']) && calls.at(-1).params.p_backend_record_id === 'record-1', 'Link parameters must exactly match the protected SQL RPC contract');
  await first.rollback('batch-1', 3, 'rollback-1');
  assert(JSON.stringify(Object.keys(calls.at(-1).params).sort()) === JSON.stringify(['p_expected_revision', 'p_idempotency_key', 'p_target_batch_id']) && calls.at(-1).params.p_target_batch_id === 'batch-1', 'Rollback parameters must exactly match the SQL RPC contract');

  console.log('Shared Navision staging guard, preview/apply confirmation, exact replay and two-browser contract checks passed');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
