'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { createWorkshopDataService } = require('./workshop-data-service.js');
const vehicleId = '11111111-1111-4111-8111-111111111111';
const bookingId = '22222222-2222-4222-8222-222222222222';
const booking = () => ({ booking_id: bookingId, booking_version: 3, stage_code: 'FITTING', stage_name: 'Fitting',
  bay_number: 2, status: 'planned', scheduled_start_at: '2026-09-16T00:00:00Z', scheduled_end_at: '2026-09-16T02:00:00Z',
  default_duration_minutes: 120, unexpected_detail: 'Must not escape the metadata projection' });
const detail = () => ({ vehicle_id: vehicleId, bookings: [booking()], line_adjustments: [{ description: 'Not search data' }] });
function setup(respond, options = {}) {
  let token = 'session-one';
  const calls = [];
  const service = createWorkshopDataService({ config: { workshop: { sharedData: true } }, getAccessToken: () => token,
    getRole: () => options.role || 'operator', client: { rpc: async (auth, name, params) => {
      calls.push({ auth, name, params }); return respond(name, params);
    } } });
  return { service, calls, setToken: value => { token = value; } };
}
test('lookup uses canonical dealer-scoped read without changing the station snapshot', async () => {
  const { service, calls } = setup(async () => ({ ok: true, body: detail() }), { role: 'viewer' });
  const result = await service.lookupVehicleBookings(vehicleId, 'PMG');
  assert.equal(result.ok, true); assert.equal(result.vehicleId, vehicleId);
  assert.equal(result.bookings[0].booking_id, bookingId);
  assert.equal(result.bookings[0].unexpected_detail, undefined); assert.equal(result.line_adjustments, undefined);
  assert.deepEqual(calls, [{ auth: 'session-one', name: 'get_vehicle_workshop_detail_scoped', params: { p_vehicle_id: vehicleId, p_dealer_code: 'PMG' } }]);
  assert.equal(service.getLastSnapshot(), null); assert.equal(service.getTrustedSnapshot(), null);
});
test('authoritative empty bookings can identify an unbooked vehicle', async () => {
  const { service } = setup(async () => ({ ok: true, body: { vehicle_id: vehicleId, bookings: [] } }));
  assert.deepEqual(await service.lookupVehicleBookings(vehicleId, 'PMG'), { ok: true, vehicleId, bookings: [] });
});
test('an unallocated STOPPAGE does not hide another valid booking', async () => {
  const body = detail();
  body.bookings.push({ ...booking(), booking_id: '33333333-3333-4333-8333-333333333333', status: 'stoppage', bay_number: null });
  const { service } = setup(async () => ({ ok: true, body }));
  const result = await service.lookupVehicleBookings(vehicleId, 'PMG');
  assert.equal(result.ok, true); assert.equal(result.bookings.length, 2);
  assert.equal(result.bookings[0].bay_number, 2); assert.equal(result.bookings[1].bay_number, null);
});
test('completed work with a released bay does not hide a valid future booking', async () => {
  const body=detail();
  body.bookings.push({...booking(),booking_id:'33333333-3333-4333-8333-333333333333',status:'completed',bay_number:null,
    scheduled_start_at:'2026-09-01T00:00:00Z',scheduled_end_at:'2026-09-01T02:00:00Z'});
  const {service}=setup(async()=>({ok:true,body}));
  const result=await service.lookupVehicleBookings(vehicleId,'PMG');
  assert.equal(result.ok,true);assert.equal(result.bookings.length,2);
  assert.equal(result.bookings[0].booking_id,bookingId);
  assert.equal(result.bookings[1].status,'completed');assert.equal(result.bookings[1].bay_number,null);
});
test('missing dealer or non-UUID identity cannot fall back to stock', async () => {
  const { service, calls } = setup(async () => { throw Error('must not call'); });
  assert.equal((await service.lookupVehicleBookings('88001038', 'PMG')).error, 'invalid_identity');
  assert.equal((await service.lookupVehicleBookings(vehicleId, '')).error, 'invalid_identity');
  assert.equal(calls.length, 0);
});
test('null or partly dated bookings violate the deployed non-null schedule contract', async () => {
  for (const row of [
    {...booking(),status:'queued',bay_number:null,scheduled_start_at:null,scheduled_end_at:null},
    {...booking(),status:'queued',scheduled_start_at:null,scheduled_end_at:null},
    {...booking(),status:'queued',bay_number:null,scheduled_start_at:null},
    {...booking(),status:'stoppage',bay_number:null,scheduled_end_at:null},
    {...booking(),status:'planned',bay_number:null,scheduled_start_at:null,scheduled_end_at:null},
    {...booking(),status:'started',scheduled_start_at:null,scheduled_end_at:null},
  ]) {
    const {service}=setup(async()=>({ok:true,body:{...detail(),bookings:[row]}}));
    assert.equal((await service.lookupVehicleBookings(vehicleId,'PMG')).error,'invalid_response');
  }
});
test('all-unallocated queued or STOPPAGE metadata remains distinguishable from failure', async () => {
  for (const status of ['queued', 'stoppage']) {
    const { service } = setup(async () => ({ ok: true, body: { ...detail(), bookings: [{ ...booking(), status, bay_number: null }] } }));
    const result = await service.lookupVehicleBookings(vehicleId, 'PMG');
    assert.equal(result.ok, true); assert.equal(result.bookings[0].bay_number, null);
  }
});
test('HTTP and dealer permission failures are not treated as unbooked', async () => {
  for (const response of [{ ok: false, status: 403 }, { ok: true, body: { ok: false, code: 'dealer_scope_denied' } }]) {
    const { service } = setup(async () => response);
    const result = await service.lookupVehicleBookings(vehicleId, 'PMG');
    assert.equal(result.ok, false); assert.equal(result.bookings, undefined);
  }
});
test('foreign identity, duplicate booking and malformed bay/time are rejected', async () => {
  for (const body of [{ ...detail(), vehicle_id: bookingId }, { ...detail(), bookings: [booking(), booking()] },
    { ...detail(), bookings: [{ ...booking(), bay_number: 0 }] },
    { ...detail(), bookings: [{ ...booking(), scheduled_end_at: 'bad-time' }] }]) {
    const { service } = setup(async () => ({ ok: true, body }));
    assert.equal((await service.lookupVehicleBookings(vehicleId, 'PMG')).error, 'invalid_response');
  }
});
test('session changes discard a late search response', async () => {
  let release; const { service, setToken } = setup(() => new Promise(resolve => { release = resolve; }));
  const pending = service.lookupVehicleBookings(vehicleId, 'PMG'); setToken('session-two');
  release({ ok: true, body: detail() }); assert.equal((await pending).error, 'authority_superseded');
});
test('authority loss and destroy discard late reads', async () => {
  for (const action of ['onAuthorityLost', 'destroy']) {
    let release; const { service } = setup(() => new Promise(resolve => { release = resolve; }));
    const pending = service.lookupVehicleBookings(vehicleId, 'PMG'); service[action]();
    release({ ok: true, body: detail() }); assert.equal((await pending).error, 'authority_superseded');
  }
});
test('navigation scope changes discard a late lookup', async () => {
  let release; const { service } = setup(name => name === 'get_vehicle_workshop_detail_scoped'
    ? new Promise(resolve => { release = resolve; }) : Promise.resolve({ ok: true, body: { revision: 1, bookings: [] } }));
  const pending = service.lookupVehicleBookings(vehicleId, 'PMG');
  await service.setScope({ stageCode: 'FITTING', dateFrom: '2026-09-16', dateTo: '2026-09-16' });
  release({ ok: true, body: detail() }); assert.equal((await pending).error, 'authority_superseded');
});
test('network failure and signed-out state return no guessed result', async () => {
  const { service, setToken, calls } = setup(async () => { throw Error('offline'); });
  assert.equal((await service.lookupVehicleBookings(vehicleId, 'PMG')).error, 'request_failed');
  setToken(null); assert.equal((await service.lookupVehicleBookings(vehicleId, 'PMG')).error, 'permission_denied');
  assert.equal(calls.length, 1);
});
