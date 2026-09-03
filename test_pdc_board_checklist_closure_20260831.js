'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const guard = require('./vehicle-requirements-guard.js');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const sql772 = fs.readFileSync('supabase/staging_only/20260830080000_stock_13017855_integrity_and_lifecycle_guards.sql', 'utf8');
const completionSql = fs.readFileSync('supabase/staging_only/20260831280000_pdc_checklist_completion_booking_preservation.sql', 'utf8');
const historySql = fs.readFileSync('supabase/staging_only/20260831310000_pdc_checklist_completion_history_preservation.sql', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const identity = fs.readFileSync('deployment-identity.json', 'utf8');
const refreshLoader = app.slice(app.indexOf('function operationalRefreshCommonLoaders'), app.indexOf('function getOperationalRefreshCoordinator'));
const workOperationLoader = refreshLoader.slice(refreshLoader.indexOf('workOperationStates:'), refreshLoader.indexOf('routeAuthority:'));
const lineHandle = app.slice(app.indexOf('function activateVehicleWorkshopLineHandle'), app.indexOf('function bindVehicleDetailTabs'));
const pmbCardDetail = app.slice(app.indexOf('function pmbCardDetailHtml'), app.indexOf('\nfunction ', app.indexOf('function pmbCardDetailHtml') + 10));

function extractFunction(name) {
  const start = app.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let parens = 0;
  let open = -1;
  for (let i = app.indexOf('(', start); i < app.length; i += 1) {
    if (app[i] === '(') parens += 1;
    if (app[i] === ')' && --parens === 0) {
      open = app.indexOf('{', i);
      break;
    }
  }
  assert.ok(open >= 0, `body for ${name} exists`);
  let depth = 0;
  for (let i = open; i < app.length; i += 1) {
    if (app[i] === '{') depth += 1;
    if (app[i] === '}' && --depth === 0) return app.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const lifecycleFunctions = [
  extractFunction('parseIsoTimestamp'),
  extractFunction('daysSinceTimestamp'),
  extractFunction('lifecycleHistoryForVehicle'),
  extractFunction('lifecycleTimestamp'),
  extractFunction('pmbAgeDays'),
  extractFunction('pmbAgeLabel'),
  extractFunction('lifecycleAgeDays'),
  extractFunction('lifecycleAgeDaysLabel'),
  extractFunction('pmbLifecycleAgeLabel'),
  extractFunction('yardHoldLifecycleAgeLabel'),
  extractFunction('locationAgeLabel'),
];
const context = {
  statusCategory: vehicle => vehicle.statusCategory || '',
  navisionEtaForVehicle: vehicle => vehicle.eta || 'No ETA',
  onSiteDaysLabel: () => '0d at PMB',
};
vm.createContext(context);
vm.runInContext(`${lifecycleFunctions.join('\n')} this.locationAgeLabel = locationAgeLabel;`, context);

const vehicle = {
  statusCategory: 'pmb',
  eta: '2026-01-01',
  lifecycleHistory: {
    firstReachedYardHoldAt: '2026-08-20T00:00:00+08:00',
    firstEnteredPmbAt: '2026-08-28T00:00:00+08:00',
  },
};
const pmbAge = context.locationAgeLabel(vehicle);
assert.match(pmbAge, /^\d+ days?$/);
assert.doesNotMatch(pmbAge, /2026-01-01|No ETA/, 'PMB must not display Kewdale ETA');
const yhAge = context.locationAgeLabel({ ...vehicle, statusCategory: 'yardhold' });
assert.strictEqual(yhAge, '—');
assert.strictEqual(context.locationAgeLabel({ statusCategory: 'pmb', lifecycleHistory: {} }), '—');
const itEta = context.locationAgeLabel({ statusCategory: 'transit', eta: '2026-09-04' });
assert.strictEqual(itEta, '2026-09-04', 'IT keeps ETA-only display');

assert.doesNotMatch(app, /Parts ETA[^`\n]*later than Kewdale ETA/, 'Parts Risk copy must not compare against Kewdale ETA');
assert.doesNotMatch(app, /PARTS RISK[^`\n]*Kewdale ETA/, 'Parts Risk detail must not mention Kewdale ETA');
assert.strictEqual(guard.partsRiskState({
  partsEta: '2026-09-11',
  vehicle: { navisionKewdaleEta: '2026-01-01' },
  bookings: [{ status: 'planned', scheduled_start_at: '2026-09-10T01:00:00Z' }],
}).risk, true);
assert.strictEqual(guard.partsRiskState({
  partsEta: '2026-09-11',
  vehicle: { navisionKewdaleEta: '2026-09-01' },
}).reason, 'booking_date_missing');
assert.strictEqual(guard.partsRiskState({
  partsEta: '2026-09-11', partsComplete: true,
  bookings: [{ status: 'planned', scheduled_start_at: '2026-09-10T01:00:00Z' }],
}).risk, false, 'Parts complete suppresses risk');

assert.match(sql772, /Partial\/upsert semantics: omitted departments are deliberately untouched/);
assert.match(sql772, /pdc_772_source_operation_immutable/);
assert.match(sql772, /pdc_772_work_item_no_delete/);
assert.match(sql772, /pdc_772_source_projection_guard/);
assert.match(sql772, /pdc_operation_line_delete_receipts_772/);
assert.match(sql772, /before_work_item/);
assert.match(sql772, /after_work_item/);
assert.match(sql772, /before_booking/);
assert.match(sql772, /after_booking/);
assert.match(sql772, /actual_elapsed_work_preserved/);
assert.match(completionSql, /ba:=b; b:=ba;/,
  'the completion successor leaves the planner booking unchanged');
assert.match(completionSql, /booking_preserved/,
  'the completion receipt reports that the planner booking was preserved');
assert.match(completionSql, /state IN\(''none''\)'/,
  'the requirement successor allows completion while retaining an active booking');
assert.match(historySql, /purged_booking_id NULL/);
assert.match(historySql, /booking_preserved/);
assert.match(historySql, /actor,email,v\.id,NULL\)/);
assert.match(historySql, /PDC_CHECKLIST_3100_EXACT_STAGING_3000_PREDECESSOR_REQUIRED/);
assert.match(planner, /workshopExactDurationHours/);
assert.match(planner, /workshopAdminBlockSegments/);
assert.match(index, /vehicle-locations-refresh\.js/);
assert.match(index, /checklist-closure=2026\.08\.31\.2800/);
assert.match(identity, /20260831280000/);
assert.match(workOperationLoader, /if \(route === 'dashboard'\) return \{ ok: true, skipped: true \};/);
assert.match(lineHandle, /openVehicleWorkshopBooking\([\s\S]*handle\.dataset\.vehicleId[\s\S]*displayStockNumber/,
  'vehicle-card booking navigation passes the canonical vehicle and Stock identity');
assert.match(pmbCardDetail, /pmbLifecycleAgeLabel\(vehicle\)/,
  'PMB planner cards use actual PMB-arrival age only');
assert.doesNotMatch(pmbCardDetail, /onSiteDaysLabel\(vehicle\)/,
  'PMB planner cards do not derive age from Kewdale ETA');
assert.doesNotMatch(app, /(?:window\.)?location\.reload\s*\(/);
assert.match(service, /sublet_bookings/);

console.log('PDC Board checklist closure hostile contract: PASS');
