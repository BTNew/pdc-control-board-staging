'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mapServerVehicle, createPdcEmailVehicleLocationService } = require('./pdc-email-vehicle-location-service');

test('compact board keeps operation, QC, booking and parts job projections', () => {
  const operation = { operation_line_id: 'line-1', operation_no: 'PD001-ABCDEF12', work_key: 'fitting', description: 'Fit bull bar', estimated_hours: 2, source_uid: 'pilbara_service_open_jobcards_v1:12345678:J123:1' };
  const parts = { colour: 'green', label: 'Parts ready', parts_complete: true, jobs: { J123: { colour: 'green', parts_complete: true, confirmed_by: 'operator' } } };
  const compact = { id: 'vehicle-1', stock_number: '12345678', version: 8, customer_name: 'Test customer', vehicle_description: 'Hilux', current_location: 'PMB', operation_lines: [operation], qc_operation_lines: [operation], work_items: [], workshop_bookings: [{ id: 'booking-1', stage_code: 'FITTING' }], parts_flags: parts };
  const full = { ...compact, pilbara_service_operations: [operation], parts_flags: { ...parts, operations: { 'line-1': parts.jobs.J123 } } };
  const fullMapped = mapServerVehicle(full);
  const compactMapped = mapServerVehicle(compact);
  delete fullMapped.pdcPartsFlags.operations;
  assert.deepEqual(compactMapped, fullMapped);
  assert.equal(compactMapped.pilbaraServiceOperations.length, 1);
  assert.deepEqual(compactMapped.pdcPartsFlags.jobs, parts.jobs);
});

test('board uses compact authenticated endpoint and preserves response and errors', async () => {
  const calls = [];
  let body = { ok: true, data: { vehicles: [{ id: 'first' }, { id: 'second' }], revision: 12 } };
  const service = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-public-key' },
    getAccessToken: () => 'test-session',
    fetchImpl: async (url, options) => { calls.push({ url, options }); return { ok: true, json: async () => body }; },
  });
  assert.deepEqual((await service.snapshot()).data, body.data);
  assert.equal(calls[0].url, 'https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/get_pdc_email_vehicle_board_snapshot');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer test-session');
  body = { ok: false, code: 'permission_denied' };
  assert.deepEqual(await service.snapshot(), { ok: false, code: 'permission_denied', data: null });
});
