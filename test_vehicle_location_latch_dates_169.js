'use strict';
const assert = require('assert');
const fs = require('fs');
const {
  normalizeLifecycleStatus,
  businessDateInTimeZone,
  resolveVehicleLifecycleLocation,
  applyFirstLifecycleMilestones,
} = require('./vehicle-location-lifecycle.js');

const statuses = ['Waiting PD2', 'Vehicle Delayed', 'Awaiting Tray Fit', 'Vehicle Waiting Wholesale', 'Vehicle Waiting For Wholesale'];
for (const status of statuses) {
  assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: status, etaAtDealer: '10/08/2026' }, { businessDate: '2026-08-11' }).location, 'YH', `${status} with past ETA maps to YH`);
  assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: status, etaAtDealer: '11/08/2026' }, { businessDate: '2026-08-11' }).location, 'YH', `${status} on boundary date is not yet YH`);
  assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: status, etaAtDealer: '12/08/2026' }, { businessDate: '2026-08-11' }).location, 'YH', `${status} future ETA is not YH`);
  assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: status }, { businessDate: '2026-08-11' }).location, 'YH', `${status} without ETA is not YH`);
}
assert.strictEqual(normalizeLifecycleStatus('  DELIVERED—AT   BODY BUILDER '), 'delivered - at body builder');
assert.strictEqual(businessDateInTimeZone(new Date('2026-08-10T16:00:00.000Z')), '2026-08-11', 'Perth date boundary is explicit');

for (const nearMiss of ['Waiting PD20', 'Vehicle Delayed Awaiting Review', 'Awaiting Tray Fitment', 'Wholesale Vehicle Waiting']) {
  assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: nearMiss, etaAtDealer: '10/08/2026' }, { businessDate: '2026-08-11' }).location, 'YH', `${nearMiss} must not fuzzy-match YH`);
}
assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'Delivered - At Body Builder' }, { businessDate: '2026-08-11' }).location, 'PMB');
for (const nearMiss of ['At Body Builder', 'Delivered To Body Builder', 'Delivered - At Body Builders']) {
  assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: nearMiss }, { businessDate: '2026-08-11' }).location, 'PMB', `${nearMiss} must not release to PMB`);
}
assert.notStrictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'Delivered - At Dealer' }, { businessDate: '2026-08-11' }).location, 'Completed', 'dealer before PMB is ignored');
assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'Delivered - At Dealer', pdcLocation: 'PMB', dateToPmb: '2026-08-01' }, { businessDate: '2026-08-11' }).location, 'Completed');
for (const nearMiss of ['At Dealer', 'Delivered To Dealer', 'Delivered - At Dealership']) {
  assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: nearMiss, pdcLocation: 'PMB', dateToPmb: '2026-08-01' }, { businessDate: '2026-08-11' }).location, 'PMB', `${nearMiss} must not complete`);
}

assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'Waiting PD2', etaAtDealer: '01/01/2020', pdcLocation: 'QC', dateToPmb: '2026-08-01' }, { businessDate: '2026-08-11' }).location, 'QC');
assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'Vehicle Delayed', etaAtDealer: '01/01/2020', pdcLocation: 'RFT', dateToPmb: '2026-08-01' }, { businessDate: '2026-08-11' }).location, 'RFT');
assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'From TWA - Despatched', etaAtDealer: '12/08/2026', pdcLocation: 'YH' }, { businessDate: '2026-08-11' }).location, 'YH', 'TWA/ETA cannot move a YH-latched vehicle back to IT');
assert.strictEqual(resolveVehicleLifecycleLocation({ toyotaStatus: 'From TWA - Despatched', etaAtDealer: '12/08/2026' }, { businessDate: '2026-08-11' }).location, 'IT', 'TWA/ETA applies only pre-YH');

let milestone = applyFirstLifecycleMilestones({}, { location: 'PMB', businessDate: '2026-08-01' });
milestone = applyFirstLifecycleMilestones(milestone, { location: 'PMB', businessDate: '2026-08-09' });
assert.strictEqual(milestone.dateToPmb, '2026-08-01', 'Date to PMB is immutable across replay');
milestone = applyFirstLifecycleMilestones(milestone, { location: 'RFT', businessDate: '2026-08-10' });
milestone = applyFirstLifecycleMilestones(milestone, { location: 'RFT', businessDate: '2026-08-11' });
assert.strictEqual(milestone.dateToRft, '2026-08-10', 'Date to RFT is immutable across replay');
milestone = applyFirstLifecycleMilestones(milestone, { location: 'Completed', businessDate: '2026-08-12' });
milestone = applyFirstLifecycleMilestones(milestone, { location: 'Completed', businessDate: '2026-08-13' });
assert.strictEqual(milestone.deliveredToDealerDate, '2026-08-12', 'Delivered-to-Dealer date is immutable across replay');

const sql = fs.readFileSync('supabase/staging_only/169_vehicle_location_latches_and_milestones.sql', 'utf8').toLowerCase();
assert(sql.includes("version='168' and name='multi_provider_sublet_bookings_and_email_contract'") && sql.includes("version>'168'"));
assert(sql.includes("values('169','vehicle_location_latches_and_milestones'"));
assert(sql.includes("at time zone 'australia/perth'"), 'SQL lifecycle dates must use the Perth business date');
assert(sql.includes('v_eta is not null and v_eta < v_business_date'), 'YH must require a parsed ETA strictly before the Perth business date');
for (const column of ['date_to_pmb', 'date_to_rft', 'delivered_to_dealer_date']) assert(sql.includes(`add column if not exists ${column} date`));
assert(/v_status\s*=\s*any\s*\(\s*array\s*\[\s*'waitingpd2'\s*,\s*'vehicledelayed'\s*,\s*'awaitingtrayfit'\s*,\s*'vehiclewaitingwholesale'\s*,\s*'vehiclewaitingforwholesale'\s*\]\s*\)/.test(sql), 'SQL must match only the five exact normalized YH statuses');
assert(sql.includes("v_status='deliveredatbodybuilder'") && sql.includes("v_status='deliveredatdealer'"));
assert(sql.includes('coalesce(old.date_to_pmb,new.date_to_pmb') && sql.includes('coalesce(old.date_to_rft,new.date_to_rft') && sql.includes('coalesce(old.delivered_to_dealer_date,new.delivered_to_dealer_date'));
assert(sql.includes("lifecycle_state='completed',visible_on_board=false,current_location='completed'"));
assert(sql.includes("upper(btrim(coalesce(v_vehicle.current_location,''))) in ('pmb','pit','qc','rft','completed')") || sql.includes("in ('pmb','pit','qc','rft','completed')"));
assert(sql.includes("'date_to_pmb',v.date_to_pmb") && sql.includes("'date_to_rft',v.date_to_rft") && sql.includes("'delivered_to_dealer_date',v.delivered_to_dealer_date"));
assert(!/create or replace function public\.schedule_vehicle_work[\s\S]*?current_location\s*=/.test(sql), 'scheduling must never mutate location');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
assert(app.includes("label: 'Released to PMB'"), 'PMB state displays as Released to PMB');
assert(app.includes('dateToPmb: item.date_to_pmb') && app.includes('dateToRft: item.date_to_rft') && app.includes('deliveredToDealerDate: item.delivered_to_dealer_date'));
assert(app.includes('Date to PMB') && app.includes('Date to RFT') && app.includes('Delivered to Dealer'));
assert(service.includes('dateToPmb: row.date_to_pmb') && service.includes('dateToRft: row.date_to_rft') && service.includes('deliveredToDealerDate: row.delivered_to_dealer_date'));
assert(app.includes('ensureDashboardWorkshopProjectionReady()') && app.includes('service?.getTrustedSnapshot?.()'), 'Vehicle Locations booking projection remains authoritative');
assert(css.includes('.incoming-work-checks[data-workshop-booking-required="true"]') && css.includes('border: 2px solid #f59e0b'), 'orange Workshop booking border remains');

console.log('Vehicle location latch/milestone 169 regression passed');
