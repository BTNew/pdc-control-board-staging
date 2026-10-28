/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r616 (F231): a Fitters bay session never sends board RPCs the database would refuse.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const auth = fs.readFileSync('./pdc-auth.js', 'utf8');
const start = auth.indexOf('  const FITTER_RPC_ALLOWLIST');
const end = auth.indexOf('  async function initialize()');
const guardSource = auth.slice(start, end);

function harness(role) {
  const sent = [];
  const context = { window: { PDC_AUTH_CONTEXT: { role } }, Proxy, Promise, Object, Set, String };
  vm.createContext(context);
  vm.runInContext(`${guardSource}\nthis.install = installFitterRpcGuard; this.allow = FITTER_RPC_ALLOWLIST;`, context);
  const client = { rpc(name, args) { sent.push(name); return Promise.resolve({ data: { ok: name }, error: null, status: 200 }); } };
  context.install(client);
  return { client, sent, allow: context.allow };
}

// Must match public.pdc_check_fitter_request in the database.
const DB_ALLOWLIST = ['get_fitter_roster', 'get_fitter_jobs', 'get_fitter_job', 'get_fitter_refresh', 'fitter_job_command',
  'record_pdc_usage_20260914', 'handoff_operation_line_583', 'undo_line_handoff_583', 'list_line_handoffs_583'];

test('fitter allowlist matches the database request hook', () => {
  assert.deepEqual([...harness('fitter').allow].sort(), [...DB_ALLOWLIST].sort());
});

test('fitter session: board RPCs are refused locally and never sent', async () => {
  const { client, sent } = harness('fitter');
  for (const name of ['get_pdc_parts_eta_board_v2', 'get_pdc_sublet_po_board_439', 'get_pdc_sublet_po_attach_pilot_445',
    'get_pdc_parts_stoppage_board_564', 'get_pdc_vehicle_key_number_460', 'list_workshop_bay_hours_570', 'get_pdc_pit_board_604']) {
    const res = await client.rpc(name, {}).abortSignal({}).single();
    assert.equal(res.status, 403);
    assert.equal(res.error.code, '42501');
    assert.equal(res.data, null);
  }
  assert.deepEqual(sent, []);
});

test('fitter session: Fitters bay RPCs still go to the server', async () => {
  const { client, sent } = harness('fitter');
  for (const name of DB_ALLOWLIST) assert.equal((await client.rpc(name, {})).status, 200);
  assert.deepEqual(sent, DB_ALLOWLIST);
});

test('other roles are not affected', async () => {
  for (const role of ['viewer', 'operator', 'administrator', 'importer', 'salesperson', undefined]) {
    const { client, sent } = harness(role);
    assert.equal((await client.rpc('get_pdc_parts_eta_board_v2', {})).status, 200);
    assert.deepEqual(sent, ['get_pdc_parts_eta_board_v2']);
  }
});

test('board modules do not load for a fitter session', () => {
  for (const file of ['pdc-parts-eta.js', 'pdc-sublet-po.js', 'pdc-sublet-po-attach.js', 'pdc-parts-stoppage.js',
    'pdc-key-number.js', 'pdc-bay-manager.js', 'pdc-pit-bookings.js']) {
    assert.match(fs.readFileSync(`./${file}`, 'utf8'), /=== 'fitter'\) return; \/\/ r616 \(F231\)/, file);
  }
});
