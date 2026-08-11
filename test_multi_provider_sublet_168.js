'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const migration = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '168_multi_provider_sublet_bookings_and_email_contract.sql'), 'utf8');
const sql = migration.toLowerCase();
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const serviceSource = fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8');
const shells = ['index.html', 'staging.html'].map(file => fs.readFileSync(path.join(root, file), 'utf8'));

assert(sql.includes("version='167' and name='live_vehicle_alias_identity_ownership'") && sql.includes("version>'167'"), 'migration must bind exact predecessor and reject newer ledgers');
assert(sql.includes("values('168','multi_provider_sublet_bookings_and_email_contract'"), 'branch-local ledger entry missing');
assert(/booking_id uuid primary key default gen_random_uuid\(\)/i.test(migration), 'booking UUID primary key missing');
for (const column of ['vehicle_id uuid not null', 'vehicle_version bigint not null', 'provider_id uuid not null', 'provider_name text not null', 'out_date date not null', 'expected_return_date date', "status text not null default 'active'", 'returned_at timestamptz', 'returned_by uuid', 'version bigint not null']) assert(sql.includes(column), `canonical column missing: ${column}`);
assert(sql.includes('expected_return_date is null or expected_return_date>=out_date'), 'legacy rows with unknown ETA must be retained without inventing a date');
assert(sql.includes("status in ('active','returned','cancelled')"), 'booking lifecycle statuses missing');
assert(sql.includes('pdc_sublet_booking_instance_history') && sql.includes('pdc_sublet_email_update_receipts'), 'immutable history/receipt ledgers missing');
assert((sql.match(/enable row level security/g) || []).length >= 3, 'RLS must protect all canonical Sublet tables');
assert(sql.includes('pdc_reject_sublet_immutable_mutation') && sql.includes('before update or delete'), 'ledger immutability triggers missing');
assert(sql.includes("source_kind='legacy_backfill'") && sql.includes('pdc_sublet_bookings_compatibility_bridge') && sql.includes('backfill_count_mismatch'), 'singular backfill/read/count bridge missing');
assert(sql.includes("daterange(new.out_date,v_end,'[)')") && sql.includes("'sublet_booking_overlap'"), 'exact overlap policy missing');
assert(sql.includes("pg_advisory_xact_lock(hashtextextended('pdc-sublet-instance:'"), 'overlap writes must serialize per canonical vehicle');
assert(sql.includes("legacy_booking_ambiguous") && sql.includes('v_count<>1'), 'legacy writer must fail closed with multiple active bookings');
assert(sql.includes('sublet_bookings') && sql.includes('sublet_active_count'), 'snapshot multi-row/read indicator contract missing');

for (const rpc of ['create_pdc_sublet_booking', 'update_pdc_sublet_booking', 'return_pdc_sublet_booking', 'apply_pdc_sublet_email_update']) {
  assert(sql.includes(`function public.${rpc}`), `${rpc} missing`);
}
assert((sql.match(/pdc_sublet_actor_allowed\(\)/g) || []).length >= 5, 'SECURITY DEFINER RPC role checks missing');
assert(sql.includes("p_language_kind not in ('booking_confirmed','eta_confirmed')"), 'definitive booking/ETA language gate missing');
assert(sql.includes("v_provider_count<>1") && sql.includes("v_match_count<>1"), 'email provider and booking exact-one gates missing');
assert(sql.includes("lower(provider_email)=lower(btrim(p_sender_email))"), 'provider-attested sender exact match missing');
assert(sql.includes('message_id') && sql.includes('attachment_sha256') && sql.includes('replay_key text not null unique'), 'message/attachment/replay evidence binding missing');
assert(sql.includes("return public.navision_backend_response(true,'replayed'"), 'replay must be idempotent');
assert(sql.indexOf('v_match_count<>1') < sql.indexOf('update public.pdc_sublet_booking_instances set out_date=coalesce'), 'ambiguity must fail before mutation');

const service = require('./pdc-email-vehicle-location-service.js');
const mapped = service.mapServerVehicle({
  id: 'vehicle-1', version: 7, sublet_active_count: 1,
  sublet_bookings: [
    { booking_id: 'booking-lovells', vehicle_id: 'vehicle-1', vehicle_version: 7, provider_id: 'lovells', provider_name: 'Lovells', out_date: '2026-08-10', expected_return_date: '2026-08-11', status: 'returned', returned_at: '2026-08-11T01:00:00Z', version: 3 },
    { booking_id: 'booking-dobinsons', vehicle_id: 'vehicle-1', vehicle_version: 7, provider_id: 'dobinsons', provider_name: "Dobinson's", out_date: '2026-08-12', expected_return_date: '2026-08-14', status: 'active', version: 1 },
  ],
});
assert.strictEqual(mapped.pdcSubletBookings.length, 2, 'mapping must retain every independent booking');
assert.strictEqual(mapped.pmbSubletProvider, "Dobinson's", 'singular bridge must point at active booking without losing Lovells history');
assert.strictEqual(mapped.pdcCompleteSublet, false, 'one active booking keeps the green completion indicator off');

const requests = [];
const client = service.createPdcEmailVehicleLocationService({
  config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public-test-key' },
  getAccessToken: () => 'test-token',
  fetchImpl: async (url, options) => { requests.push({ url, body: JSON.parse(options.body) }); return { ok: true, status: 200, json: async () => ({ ok: true, code: 'ok', data: {} }) }; },
});
(async () => {
  await client.createSubletBooking('vehicle-1', 7, 'lovells', '2026-08-10', '2026-08-11', 'bookings@lovells.test', 'first');
  await client.updateSubletBooking('booking-lovells', 1, '2026-08-10', '2026-08-12', null);
  await client.returnSubletBooking('booking-lovells', 2, '2026-08-12T12:00:00+08:00');
  assert(requests[0].url.endsWith('/rpc/create_pdc_sublet_booking'), 'create RPC route missing');
  assert.deepStrictEqual(requests[0].body, { p_vehicle_id: 'vehicle-1', p_vehicle_version: 7, p_provider_id: 'lovells', p_out_date: '2026-08-10', p_expected_return_date: '2026-08-11', p_provider_email: 'bookings@lovells.test', p_notes: 'first' });
  assert(requests[1].url.endsWith('/rpc/update_pdc_sublet_booking'), 'date edit RPC route missing');
  assert(requests[2].url.endsWith('/rpc/return_pdc_sublet_booking'), 'return RPC route missing');

  const helperStart = app.indexOf('function plainDateValue(');
  const helperEnd = app.indexOf('function selectSubletView(', helperStart);
  const overdueStart = app.indexOf('function subletIsOverdue(');
  const overdueEnd = app.indexOf('function subletVehicleByKey(', overdueStart);
  const context = { Date, Intl, Number, String, Math, Array, Object, Map, Set, Boolean, PDC_JOB_DEFS: [], vehicleLocationBoardRows: () => [], pdcJobRequired: () => false, pdcJobComplete: () => false, inferredPmbStage: () => '', pmbBaySubletProvider: v => v.provider || '', displayStockNumber: v => v.stock || '', vehicleKey: v => v.key || '', vehicleCustomerName: () => '', displayVehicle: () => '' };
  vm.createContext(context);
  vm.runInContext(`${app.slice(helperStart, helperEnd)}\n${app.slice(overdueStart, overdueEnd)}\nthis.today=subletTodayDateKey();this.yesterday=subletShiftDate(this.today,-1);this.overdue=subletIsOverdue;`, context);
  assert.strictEqual(context.overdue({ pmbSubletExpectedReturnDate: context.today }), false, 'due today in Perth is not overdue at the now boundary');
  assert.strictEqual(context.overdue({ pmbSubletExpectedReturnDate: context.yesterday }), true, 'due before the Perth business date is overdue');
  assert.strictEqual(context.overdue({ pmbSubletExpectedReturnDate: context.yesterday, pmbSubletActualReturnDate: context.today }), false, 'returned booking is never overdue');

  for (const html of shells) {
    for (const id of ['sublet-create-open', 'sublet-create-dialog', 'sublet-create-form', 'sublet-create-vehicle-search', 'sublet-create-vehicle-id', 'sublet-create-provider', 'sublet-create-out-date', 'sublet-create-return-date', 'sublet-create-error']) assert(html.includes(`id="${id}"`), `Create Sublet shell missing ${id}`);
    assert(html.includes('aria-labelledby="sublet-create-title"') && html.includes('role="alert"'), 'dialog naming/error accessibility missing');
  }
  assert(app.includes("event.target.closest?.('[data-sublet-create-vehicle]')"), 'nested result clicks must use a safe outer/delegated handler');
  assert(app.includes('if (event.target === dialog) closeSubletCreateDialog()'), 'dialog outer click handler must not close on inner content');
  assert(app.includes("on(dialog, 'cancel'"), 'Escape/cancel lifecycle missing');
  assert(app.includes("if (exact.length !== 1)"), 'vehicle ambiguity must fail closed');
  assert(app.includes("if (subletBookingState(vehicle) !== 'booked') return false"), 'active calendar must remove only returned/cancelled booking rows');
  assert(css.includes('@keyframes sublet-overdue-flash') && css.includes('@media (prefers-reduced-motion: reduce)'), 'flashing overdue and reduced-motion fallback missing');
  assert(css.includes('.sublet-status-pill.is-overdue'), 'red overdue active tile styling missing');
  assert(serviceSource.includes('subscribeRealtime(PDC_EMAIL_VEHICLE_REVISION_TABLE'), 'Realtime revision lifecycle must remain connected');
  console.log('Multi-provider Sublet migration, service, calendar/create/return and email contracts passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
