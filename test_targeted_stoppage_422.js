'use strict';
const assert = require('assert');
const fs = require('fs');
const serviceModule = require('./pdc-email-vehicle-location-service.js');
const sql = fs.readFileSync('supabase/staging_only/20260826193000_422_targeted_stoppage_paths.sql', 'utf8');
const repair = fs.readFileSync('supabase/staging_only/20260826194000_423_stoppage_actor_email_qualification.sql', 'utf8');
const acceptance = fs.readFileSync('supabase/staging_only/20260826195000_424_hidden_targeted_stoppage_acceptance.sql', 'utf8');
const acceptanceRepair = fs.readFileSync('supabase/staging_only/20260826200000_425_hidden_acceptance_actor_email_qualification.sql', 'utf8');
const partsRepair = fs.readFileSync('supabase/staging_only/20260826201000_426_parts_stoppage_notification_delta_containment.sql', 'utf8');
const partsAcceptance = fs.readFileSync('supabase/staging_only/20260826202000_427_hidden_parts_stoppage_acceptance.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

assert.match(sql, /clear_vehicle_stoppage_422\(p_vehicle_id uuid,p_expected_vehicle_version integer,p_stoppage_kind text,p_booking_id uuid,p_expected_booking_version integer/);
assert.match(sql, /kind NOT IN\('booking','parts','pmb'\)/);
assert.match(sql, /WHERE id=p_booking_id AND vehicle_id=v\.id FOR UPDATE/);
assert.match(sql, /b\.version<>p_expected_booking_version/);
assert.match(sql, /b\.status::text<>'stoppage'/);
assert.match(sql, /return_work_to_queue\(b\.id,b\.version,NULL/);
assert.match(sql, /set_pdc_parts_stoppage_376\(v\.id,v\.version,child_key,'clear',note\)/);
assert.match(sql, /set_pmb_stoppage_422\(v\.id,v\.version,'clear',note,child_key\)/);
assert.match(sql, /target_required_use_clear_vehicle_stoppage_422/);
assert.match(sql, /pdc_pmb_stoppage_receipts_422_append_only/);
assert.match(sql, /pmb_stoppage_started_at/);
assert.match(sql, /pmb_stoppage_cleared_at/);
assert.match(sql, /'workshop_bookings'.*jsonb_build_object\('version',b\.version\)/s);
assert.match(sql, /REVOKE ALL ON TABLE public\.pdc_pmb_stoppage_receipts_422 FROM public,anon,authenticated,service_role/);
assert.match(sql, /has_function_privilege\('authenticated','public\.clear_vehicle_stoppage_422/);
assert.match(sql, /has_function_privilege\('anon','public\.clear_vehicle_stoppage_422/);
assert.match(repair, /5e9d050b428b5299fc480fbbbe247f6db47d0ca3e382267e8a06efda46fa546d/);
assert.match(repair, /9c92e37350156a9c69f0ad4f51f1f8be89305d2b474f243c8d431cf6b8cbf70d/);
assert.match(repair, /lower\(r\.email\)=actor_email/);
assert.match(acceptance, /pdc_hermes_test_clear_booking_stoppage_424/);
assert.match(acceptance, /pdc_overnight_synthetic_fleet_registry_363/);
assert.match(acceptance, /IF NOT was_visible THEN UPDATE public\.vehicles SET visible_on_board=false/);
assert.match(acceptance, /has_function_privilege\('anon'.*pdc_hermes_test_clear_booking_stoppage_424/s);
assert.match(acceptanceRepair, /86abe658b113bf2942fc47166857179e54135a448e190aff017a2878e2b32299/);
assert.match(acceptanceRepair, /r\.actor_email=v_actor_email/);
assert.match(partsRepair, /bf9b4fac69363cb1121d65023dd0b6151ea361b048c73c9c5f08f755e1f0df3c/);
assert.match(partsRepair, /v_notifications_after<>v_notifications_before/);
assert.match(partsRepair, /Monitor guard, inactive writers\/mailboxes/);
assert.match(partsAcceptance, /pdc_hermes_test_parts_stoppage_427/);
assert.match(partsAcceptance, /set_pdc_parts_stoppage_376/);
assert.match(partsAcceptance, /clear_vehicle_stoppage_422/);
assert.match(partsAcceptance, /synthetic_visibility_restored/);

assert.match(service, /PDC_STOPPAGE_CLEAR_RPC = 'clear_vehicle_stoppage_422'/);
assert.match(service, /PDC_PMB_STOPPAGE_RPC = 'set_pmb_stoppage_422'/);
assert.match(service, /p_stoppage_kind:/);
assert.match(service, /p_booking_id:/);
assert.match(service, /p_expected_booking_version:/);
assert.match(service, /mapped\.pdcBlocked = Boolean\(row\.pmb_stoppage_started_at\)/);
assert.match(service, /version: Number\(booking\?\.version \|\| 0\)/);

const mapped = serviceModule.mapServerVehicle({
  id: '00000000-0000-4000-8000-000000000001', permanent_vehicle_id: 'PERM-1', stock_number: 'HERMES-TEST-422', version: 7,
  pmb_stoppage_reason: 'Tyre station unavailable', pmb_stoppage_started_at: '2026-08-25T09:00:00Z', pmb_stoppage_started_by: '00000000-0000-4000-8000-000000000002',
  workshop_bookings: [{ booking_id: '00000000-0000-4000-8000-000000000003', version: 12, status: 'stoppage' }],
});
assert.strictEqual(mapped.pdcBlocked, true);
assert.strictEqual(mapped.pdcBlockReason, 'Tyre station unavailable');
assert.strictEqual(mapped.salesWorkshopBookings[0].version, 12);

assert.match(app, /stoppageKind: 'booking'/);
assert.match(app, /stoppageKind: 'parts'/);
assert.match(app, /stoppageKind: 'pmb'/);
assert.match(app, /data-stoppage-kind=/);
assert.match(app, /data-booking-version=/);
assert.match(app, /service\.clearVehicleStoppage\(vehicle\.__emailVehicleId, Number\(vehicle\.__emailVehicleVersion\), stoppageKind, bookingId, Number\(bookingVersion/);
console.log('targeted Workshop, Parts and PMB STOPPAGE contract passed');
