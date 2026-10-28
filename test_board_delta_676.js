'use strict';
// r676 (F285): the board sends only changed vehicles; the browser rebuilds the full board in the server's order.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const api = require('./pdc-email-vehicle-location-service');
const reply = (body, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body });
const v = (id, x) => ({ id, x, operation_lines: [{ description: 'Synthetic ' + id }] });
const full = (token, vehicles) => ({ ok: true, code: 'board', snapshot_token: token, data: { revision: 1, vehicles } });
function runtime(responses) {
  const calls = [];
  const service = api.createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, getAccessToken: () => 'A',
    fetchImpl: async (url, options) => { calls.push({ url, body: JSON.parse(options.body || '{}') }); return responses.shift(); } });
  return { service, calls };
}
test('delta rebuilds the same board as a full read, in server order', async () => {
  const r = runtime([reply(full('h:1', [v('a', 1), v('b', 1), v('c', 1)])),
    reply({ ok: true, code: 'board', delta: true, snapshot_token: 'h:2', base_token: 'h:1', data: { revision: 2 }, vehicle_ids: ['c', 'a', 'd'], changed: [v('a', 2), v('d', 1)] })]);
  await r.service.snapshot();
  const second = await r.service.snapshot();
  assert.deepEqual(r.calls[1].body, { p_snapshot_token: 'h:1', p_accept_delta: true });
  assert.deepEqual(second, { ok: true, code: 'board', data: { revision: 2, vehicles: [v('c', 1), v('a', 2), v('d', 1)] } });
});
test('a delta for another base, or with a missing vehicle, fails closed and clears the copy', async () => {
  const r = runtime([reply(full('h:1', [v('a', 1)])),
    reply({ ok: true, delta: true, snapshot_token: 'h:2', base_token: 'h:0', data: {}, vehicle_ids: ['a'], changed: [] }),
    reply(full('h:3', [v('a', 3)])),
    reply({ ok: true, delta: true, snapshot_token: 'h:4', base_token: 'h:3', data: {}, vehicle_ids: ['a', 'zz'], changed: [] })]);
  await r.service.snapshot();
  assert.equal((await r.service.snapshot()).code, 'snapshot_protocol_error');
  await r.service.snapshot();
  assert.equal(r.calls[2].body.p_snapshot_token, null);
  assert.equal((await r.service.snapshot()).code, 'snapshot_protocol_error');
});
test('server function: opt-in overload, history kept small, token from content', () => {
  const sql = fs.readFileSync('supabase/migrations/20261028280000_r676_board_delta.sql', 'utf8');
  assert.match(sql, /get_pdc_email_vehicle_board_snapshot_conditional\(p_snapshot_token text, p_accept_delta boolean\)/);
  assert.match(sql, /jsonb_hash_extended\(v_base, 676\)/);
  assert.match(sql, /LIMIT 6/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.get_pdc_email_vehicle_board_snapshot_conditional\(text, boolean\) TO authenticated/);
});
