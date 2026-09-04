'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const guard = require('./vehicle-requirements-guard.js');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const activeBooking = {
  booking_id: '11111111-1111-4111-8111-111111111111',
  stage_code: 'FITTING',
  status: 'planned',
  scheduled_start_at: '2026-09-07T00:00:00Z',
};

assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'fitting', required: true }),
  { state: 'required', marker: '•', label: 'Required' },
  'required work without an active booking stays Required',
);
assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'fitting', required: true, bookings: [activeBooking] }),
  { state: 'booked', marker: '!', label: 'Booked' },
  'an active authoritative workshop booking projects Booked',
);
assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'fitting', required: true, completed: true, bookings: [activeBooking] }),
  { state: 'completed', marker: '✓', label: 'Completed' },
  'authoritative completion takes precedence over Booked',
);
assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'parts', required: true, partsOrdered: true }),
  { state: 'booked', marker: '!', label: 'Ordered' },
  'Parts ordered uses the shared booked/ordered projection',
);
assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'sublet', required: true, subletBookings: [{ status: 'active' }] }),
  { state: 'booked', marker: '!', label: 'Booked' },
  'active Sublet work uses the shared booked projection',
);

const mapped = mapServerVehicle({
  id: '22222222-2222-4222-8222-222222222222',
  stock_number: '13000014',
  current_location: 'PMB',
  source_location_status: 'Delivered - At Body Builder',
  work_items: [{ work_key: 'fitting', required: true, completed: false }],
  workshop_bookings: [activeBooking],
});
assert.strictEqual(mapped.sourceLocationStatus, 'Delivered - At Body Builder');
assert.strictEqual(mapped.salesWorkshopBookings[0].status, 'planned');
assert.strictEqual(
  guard.projectWorkState({
    workKey: 'fitting',
    required: mapped.pdcRequiresFitting,
    completed: mapped.pdcCompleteFitting,
    bookings: mapped.salesWorkshopBookings,
  }).state,
  'booked',
  'fresh canonical service rows drive the same shared work-state projection',
);

const appSource = fs.readFileSync('app.js', 'utf8');
const checklistStart = appSource.indexOf('function incomingWorkChecklistHtml');
const checklistEnd = appSource.indexOf('\nfunction workStatusLegendHtml', checklistStart);
assert.ok(checklistStart >= 0 && checklistEnd > checklistStart, 'Incoming Board work renderer is extractable');
const checklistContext = {
  window: { VehicleRequirementsGuard: guard },
  vehicleKey: () => '13000014',
  normalizePmbStage: value => String(value || '').toUpperCase(),
  inferredPmbStage: () => '',
  vehicleWorkshopBookingProjection: () => ({ activeBookings: [{ ...activeBooking, stage: 'FITTING' }], bookingRequired: false }),
  pdcJobDefsPartsFirst: () => [{ key: 'fitting', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting', label: 'Fitting' }],
  pdcJobRequired: vehicle => vehicle.pdcRequiresFitting === true,
  pdcJobComplete: vehicle => vehicle.pdcCompleteFitting === true,
  pmbStageForPdcJob: () => 'FITTING',
  PMB_STAGE_TO_JOB_KEY: {},
  isActivePartsStoppage: () => false,
  isPdcBlocked: () => false,
  partsOrdered: () => false,
  canonicalActiveSubletBooking: () => null,
  pdcGridJobLabel: () => 'Fitting',
  pdcJobCompletionTitle: () => 'Fitting required',
  escapeHtml: value => String(value),
};
vm.createContext(checklistContext);
vm.runInContext(appSource.slice(checklistStart, checklistEnd), checklistContext);
const checklist = checklistContext.incomingWorkChecklistHtml({ pdcRequiresFitting: true });
assert.match(checklist, /is-booked/, 'Incoming Board renders active Workshop work as booked');
assert.match(checklist, /Fitting booked/, 'Incoming Board booked state is accessible by label');
assert.match(checklist, />!</, 'Incoming Board booked state has the canonical visible exclamation marker');

const css = fs.readFileSync('styles.css', 'utf8');
assert.match(css, /\.incoming-work-check\.is-booked[^}]*background:\s*#fff7ed/s, 'Booked Board work is visually orange');
assert.match(css, /\.pdc-work-state-booked[^}]*background:\s*#fff7ed/s, 'Booked vehicle-card work is visually orange');
assert.match(css, /\.vehicle-copyable-field[^}]*user-select:\s*text/s, 'Stock, VIN/chassis and Job Card fields remain copyable');
assert.ok(/data-copy-vehicle-stock/.test(appSource), 'Vehicle Detail exposes a Stock Number copy control');
assert.match(appSource, /async function copyTextToClipboard[\s\S]*navigator\.clipboard[\s\S]*execCommand\('copy'\)/, 'Stock Number copy helper supports Clipboard API and fallback');
assert.match(appSource, /aria-live="polite"[^>]*data-copy-vehicle-stock-status/, 'Stock copy feedback is announced accessibly');

const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
const summaryStart = plannerSource.indexOf('function workshopVehicleIdentitySummaryHtml');
const summaryEnd = plannerSource.indexOf('\nfunction workshopQueueEstimatedLabel', summaryStart);
assert.ok(summaryStart >= 0 && summaryEnd > summaryStart, 'Workshop summary renderer is extractable');
const summaryContext = {
  cleanNavisionText: value => String(value || '').trim(),
  escapeHtml: value => String(value),
  displayStockNumber: vehicle => vehicle.stock,
  vehicleJobcardNumber: vehicle => vehicle.jobcard,
};
vm.createContext(summaryContext);
vm.runInContext(plannerSource.slice(summaryStart, summaryEnd), summaryContext);
const summary = summaryContext.workshopVehicleIdentitySummaryHtml({ stock: '13000014', jobcard: '', currentLocation: '' });
assert.match(summary, /JC Unknown/, 'missing Job Card has an explicit Unknown fallback');
assert.match(summary, /Location: Unknown/, 'missing location has an explicit Unknown fallback');
assert.match(summary, /vehicle-copyable-field/, 'Workshop identity values are explicitly copyable');

const refreshCount = (plannerSource.match(/data-workshop-refresh-vehicle(?=[ >])/g) || []).length;
const scheduleNavCount = (plannerSource.match(/data-open-control-board-schedule>/g) || []).length;
assert.strictEqual(refreshCount, 1, 'Workshop has one obvious Refresh Vehicle control');
assert.strictEqual(scheduleNavCount, 0, 'Workshop omits the redundant Control Board Schedule navigation control');
assert.match(appSource, /Save all hours/, 'Workshop vehicle card provides one batch save action for edited hours');

const migrationFiles = fs.readdirSync('supabase/staging_only').filter(name => name.includes('pdc14_parts_coordinator_role'));
assert.strictEqual(migrationFiles.length, 1, 'PDC-14 has one append-only role assignment migration');
const roleSql = fs.readFileSync(`supabase/staging_only/${migrationFiles[0]}`, 'utf8');
for (const marker of [
  'functional@pdc.online',
  'Parts Coordinator',
  "account_status='approved'",
  'active=true',
  "role='operator'",
  'PDC_14_',
]) assert.ok(roleSql.includes(marker), `role migration missing ${marker}`);
assert.doesNotMatch(roleSql, /role='administrator'/, 'Parts account does not receive Administrator authority');
assert.match(roleSql, /pdc14_parts_coordinator_already_assigned/, 'role assignment is replay-idempotent');
for (const rollbackField of ['before_rejected_at', 'before_rejection_reason', 'before_disabled_at', 'before_disabled_reason', 'before_restored_at']) {
  assert.ok(roleSql.includes(rollbackField), `role rollback preserves ${rollbackField}`);
}

const pdc14MigrationFiles = fs.readdirSync('supabase/staging_only').filter(name => name.includes('pdc14_canonical_controls'));
assert.strictEqual(pdc14MigrationFiles.length, 1, 'PDC-14 has one canonical authority successor migration');
const pdc14Sql = fs.readFileSync(`supabase/staging_only/${pdc14MigrationFiles[0]}`, 'utf8');
for (const marker of [
  'REBHV100551477',
  'set_pdc_vehicle_location_1500',
  "PERFORM public.require_pdc_role('operator')",
  'vehicle_version_conflict',
  'pdc14_navision_body_builder_direct_pmb_v1',
  'date_to_pmb',
  'first_entered_pmb_at',
]) assert.ok(pdc14Sql.includes(marker), `canonical controls migration missing ${marker}`);
assert.match(pdc14Sql, /REVOKE ALL ON FUNCTION public\.set_pdc_vehicle_location_1500/);
assert.match(pdc14Sql, /GRANT EXECUTE ON FUNCTION public\.set_pdc_vehicle_location_1500[^;]+ TO authenticated/);

const hardenedLocationSql = fs.readFileSync(
  'supabase/staging_only/20260903180000_pdc14_location_review_hardening.sql',
  'utf8',
);
assert.match(hardenedLocationSql, /pdc_qc_complete[\s\S]*pmb_stage[\s\S]*pit_requires_pmb_unallocated/, 'server rejects PIT entry for QC-complete or actively staged PMB vehicles');
assert.match(appSource, /save other edits before changing PDC Location/, 'location action rejects mixed-form partial commits');
assert.match(appSource, /pdc-work-state-booked[\s\S]*pdc-work-state-ordered[\s\S]*pdc-work-state-complete/, 'state cycling clears stale booked and ordered classes');
assert.match(appSource, /orange booked\/ordered, green completed/, 'tooltip describes canonical booked and completed colors');

for (const valid of ['REBHV100551477', 'REBHV199999999']) {
  assert.strictEqual(guard.normalizeVehicleIdentity(valid), valid, `${valid} is accepted as a bounded electric HiLux chassis`);
}
for (const invalid of ['REBHV10055147', 'REBHV1005514777', 'REBXX100551477', 'SHORT123']) {
  assert.strictEqual(guard.normalizeVehicleIdentity(invalid), '', `${invalid} remains invalid`);
}

console.log('PDC-14 Control Board parity regression: PASS');
