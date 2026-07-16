'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const rows = {
  workshop_stages: [{ id: 'stage-1', code: 'FITTING', display_name: 'Fitting', sort_order: 4, is_physical: true, is_sublet: false, active: true, updated_at: '2026-07-16T00:00:00Z' }],
  workshop_bays: [{ id: 'bay-1', stage_id: 'stage-1', bay_number: 1, code: 'FITTING-BAY-01', display_name: 'Fitting Bay 01', is_active: true, is_sublet_row: false, default_technician_id: 'tech-1', updated_at: '2026-07-16T00:00:00Z' }],
  workshop_technicians: [{ id: 'tech-1', name: 'Alex Mechanic', role_type: 'technician', active: true, can_fit_stages: ['FITTING'], leave_calendar: [], updated_at: '2026-07-16T00:00:00Z' }],
  workshop_settings: [{ id: 'setting-1', key: 'frontend_contract_version', value: 1, scope: 'global', updated_at: '2026-07-16T00:00:00Z' }],
  workshop_bookings: [{ id: 'booking-1', vehicle_id: 'vehicle-1', stage_id: 'stage-1', bay_id: 'bay-1', status: 'planned', scheduled_start_at: '2026-07-17T00:00:00Z', scheduled_end_at: '2026-07-17T03:00:00Z', default_duration_minutes: 180, actual_start_at: null, actual_end_at: null, actual_duration_minutes: null, stoppage_reason: null, stoppage_started_at: null, stoppage_accumulated_minutes: 0, returned_to_queue_at: null, deleted_at: null, deleted_reason: null, source: 'planner', version: 1, created_at: '2026-07-16T00:00:00Z', updated_at: '2026-07-16T00:00:00Z' }],
  workshop_booking_assignments: [{ id: 'assignment-1', booking_id: 'booking-1', technician_id: 'tech-1', assignment_type: 'primary', assigned_at: '2026-07-16T00:00:00Z', scheduled_start_at: '2026-07-17T00:00:00Z', scheduled_end_at: '2026-07-17T03:00:00Z', released_at: null, notes: null, updated_at: '2026-07-16T00:00:00Z' }],
  vehicles: [{ id: 'vehicle-1', permanent_vehicle_id: 'ORDER-1', stock_number: 'S100', job_card_number: 'JC100', customer_name: 'Shared Customer', make: 'Toyota', model: 'HiLux', lifecycle_state: 'active', visible_on_board: true, current_location: 'PMB', pmb_stage: '', pmb_bay_stage: '', pmb_bay_number: '', source_payload: { pdcRequiresFitting: true }, version: 1, updated_at: '2026-07-16T00:00:00Z' }],
};

class QueryBuilder {
  constructor(table) { this.table = table; }
  select() { return this; }
  eq() { return this; }
  neq() { return this; }
  order() { return this; }
  then(resolve, reject) { return Promise.resolve({ data: rows[this.table] || [], error: null }).then(resolve, reject); }
}

const realtimeHandlers = [];
const channel = {
  on(_kind, filter, callback) { realtimeHandlers.push({ filter, callback }); return this; },
  subscribe(callback) { callback('SUBSCRIBED'); return this; },
};
const dispatched = [];
const root = {
  PDC_SUPABASE_CONFIG: { workshop: { sharedData: false, realtime: true, refreshDebounceMs: 50 } },
  PDC_AUTH_CONTEXT: { userId: 'user-1', role: 'operator' },
  PDC_SUPABASE: {
    from(table) { return new QueryBuilder(table); },
    channel() { return channel; },
    removeChannel() { return Promise.resolve(); },
    rpc() { return Promise.resolve({ data: { ok: false, error: 'not_used' }, error: null }); },
  },
  setTimeout,
  clearTimeout,
  CustomEvent: class CustomEvent { constructor(type, init) { this.type = type; this.detail = init?.detail; } },
  dispatchEvent(event) { dispatched.push(event); return true; },
};
root.window = root;

const context = vm.createContext({ window: root, console, structuredClone, setTimeout, clearTimeout });
vm.runInContext(fs.readFileSync(path.join(__dirname, 'workshop-data-service.js'), 'utf8'), context, { filename: 'workshop-data-service.js' });
const service = root.PDC_WORKSHOP_DATA;

(async () => {
  assert.ok(!service.isEnabled(), 'Shared service must stay disabled until the explicit post-migration cutover flag is enabled');
  root.PDC_SUPABASE_CONFIG.workshop.sharedData = true;
  assert.ok(service.isEnabled(), 'Shared service should enable for an authenticated Supabase user');
  await service.initialize();
  assert.ok(service.isReady(), 'Shared service should become ready after the snapshot loads');
  assert.strictEqual(service.getPlans().length, 1);
  assert.strictEqual(service.getPlans()[0].vehicleKey, 'ORDER-1');
  assert.strictEqual(service.getPlannerVehicles()[0].pdcRequiresFitting, true);
  assert.strictEqual(service.getStatus().realtimeStatus, 'subscribed');
  assert.ok(realtimeHandlers.some(item => item.filter.table === 'workshop_bookings'), 'Bookings realtime handler is missing');
  assert.ok(realtimeHandlers.some(item => item.filter.table === 'vehicles'), 'Vehicles realtime handler is missing');
  assert.ok(dispatched.some(event => event.type === 'pdc-workshop-data-changed'), 'Initial snapshot should notify the planner');

  root.PDC_AUTH_CONTEXT = { userId: 'user-2', role: 'viewer' };
  assert.ok(!service.isReady(), 'Cached data must not remain ready after the authenticated user changes');
  await service.initialize();
  assert.ok(service.isReady(), 'Service should reload safely for the new authenticated user');

  console.log('Workshop shared data runtime checks passed');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
