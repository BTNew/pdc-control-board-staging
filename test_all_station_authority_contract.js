'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const app = read('app.js');
const planner = read('workshop-planner.js');
const moduleSource = read('workshop-eligibility.js');
const migration = read('supabase/migrations/042_all_station_eligibility_and_sublet_planner_removal.sql');
const closure = read('supabase/migrations/044_blocker_only_all_station_release_closure.sql');
const corrective = read('supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql');
const rejected = read('supabase/obsolete_migrations/043_all_station_review_closure_REJECTED_NEVER_APPLY.sql');
const backup = read('scripts/pdc_backup.py');
const effectiveMigration = `${migration}\n${closure}\n${corrective}`;
const index = read('index.html');
const eligibility = require('./workshop-eligibility.js');

const stations = ['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION'];
for (const stage of stations) {
  assert(moduleSource.includes(`code: '${stage}'`), `canonical frontend mapping missing ${stage}`);
  assert(effectiveMigration.includes(`'${stage}'`), `canonical database mapping missing ${stage}`);
}
for (const alias of ['Bus 4x4','BUS4X4','Fabrication','Fab','Electrical','Elec','Tyre Bay','Tyre','Pit Inspection','Pit','Pits']) {
  assert(moduleSource.toLowerCase().includes(alias.toLowerCase()), `frontend aliases missing ${alias}`);
  assert(effectiveMigration.toLowerCase().includes(alias.toLowerCase()), `database aliases missing ${alias}`);
}
const normalizeAlias = value => String(value).toUpperCase().replace(/[^A-Z0-9]+/g, '');
for (const def of eligibility.stationDefinitions) {
  for (const alias of [def.code, def.workKey, def.jobKey, def.label, ...def.aliases]) {
    const normalized = normalizeAlias(alias);
    assert(closure.includes(`('${normalized}'`) || migration.includes(`('${normalized}'`), `SQL alias corpus missing ${alias} -> ${def.code}`);
  }
}
assert(closure.includes("('PITSHOIST','Pits Hoist','HOIST')"), 'Pits Hoist must map to Hoist at every authority boundary');
assert(!fs.existsSync(path.join(root,'supabase/migrations/043_all_station_review_closure.sql')) && rejected.includes('Corrective closure'), 'rejected 043 must be formally outside the active migration sequence');

assert(index.indexOf('workshop-eligibility.js') < index.indexOf('app.js'), 'canonical mapping must load before app routing/counts');
assert(app.includes('return authoritativeWorkshopVehiclesForStage(normalizedStage)'), 'shared Control Board counts must fail over to authoritative candidates, not browser-local filtering');
assert(app.includes("get_workshop_eligibility_snapshot"), 'Control Board must load canonical aggregate RPC');
assert(app.includes("{ allStations: true }"), 'Control Board must subscribe to all station revision signals');
assert(app.includes("table = stageCode || allStations ? 'workshop_station_revision'"), 'all-station Realtime must use station revision authority');
assert(app.includes("return loadWorkshopEligibilitySnapshot('subscribed')") && app.includes('workshopEligibilityReconnectTimer = setTimeout'), 'Realtime trust must resync after SUBSCRIBED and replace a closed channel');
assert(app.includes('workshopEligibilityRevisionPending = true') && app.includes("loadWorkshopEligibilitySnapshot('realtime_pending')"), 'Realtime revisions received during resync must force a trailing fetch');
assert(app.includes("if (app.workshopEligibilityState !== 'connected') return []"), 'disconnected Control Board must not consume stale candidates');
assert(planner.includes('WORKSHOP_ELIGIBILITY_RUNTIME.workshopCanonicalEligibility'), 'planner must apply the canonical candidate contract');
assert(planner.includes("stock: vehicle.stock_number || ''") && planner.includes("client: vehicle.customer_name || ''"), 'shared snapshot candidates must populate the planner identity fields used by the queue renderer');
assert(corrective.match(/get_station_workshop_snapshot[\s\S]*workshop_station_eligibility\(v_stage\)/), 'station RPC must use canonical eligibility');
assert(corrective.match(/get_workshop_eligibility_snapshot[\s\S]*workshop_station_eligibility\(s\.code\)/), 'Control Board RPC must use canonical eligibility');
assert(migration.includes("in('PMB','YH')") && migration.includes("='IT'"), 'database eligibility must implement PMB/YH/IT rules');
assert(migration.includes("'missing_eta'"), 'missing IT ETA must remain visible and disabled');
assert(!/(update\s+public\.vehicles|insert\s+into\s+public\.vehicle_movements)/i.test(migration), 'eligibility migration must never change location/workflow state');
assert(migration.includes('workshop_station_revision_from_vehicle') && migration.includes('vehicle_work_items'), 'location changes must invalidate every outstanding requirement station');
assert(closure.includes("array['workshop_stages','workshop_stage_aliases','workshop_bays','workshop_technicians','workshop_settings']"), 'configuration dependencies must invalidate all station revisions');
assert(closure.includes("in ('operator','administrator')") && closure.includes('workshop_require_planner_operator'), 'planner snapshots must exclude importer/viewer roles');
assert(closure.includes('workshop_bookings_require_planner_operator') && closure.includes('before insert or update or delete on public.workshop_bookings'), 'all direct and RPC booking mutations must enforce the exact planner operator boundary');
assert(closure.includes("new.status='completed'") && closure.includes("raise exception 'planner_disabled stage=%'"), 'disabled planner lifecycle mutations must fail while historical completion remains narrowly allowed');
assert(closure.includes('revoke execute on function public.workshop_start_booking') && closure.includes('revoke execute on function public.workshop_restore_booking'), 'obsolete low-level lifecycle RPCs must not remain browser-callable');
assert(closure.includes('pg_trigger_depth()>1') && closure.includes("array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by']"), 'nested importer ETA-risk maintenance must remain allowed without widening direct booking writes');
assert(closure.match(/update public\.workshop_station_revision set revision=revision\+1/), 'disabled/deleted station subscribers must receive a final invalidation');
const etaGuard = effectiveMigration.slice(effectiveMigration.indexOf('create or replace function public.workshop_enforce_vehicle_eta'), effectiveMigration.indexOf('drop trigger if exists workshop_bookings_enforce_vehicle_eta'));
assert(etaGuard.includes("v_location='IT'") && !etaGuard.includes("v_location in ('YH','IT')"), 'YH must schedule immediately while IT remains ETA-gated');
const scheduleClosure = closure.slice(closure.indexOf('create or replace function public.schedule_vehicle_work'), closure.indexOf('create or replace function public.move_workshop_booking'));
assert(!/\b(current_location|pmb_stage|visible_on_board)\s*=/.test(scheduleClosure), 'scheduling RPC must preserve location, workflow stage and visibility');
const moveClosure = closure.slice(closure.indexOf('create or replace function public.move_workshop_booking'), closure.indexOf('create or replace function public.resize_workshop_booking'));
assert(moveClosure.includes('workshop_move_booking') && !/update\s+public\.vehicles|\b(current_location|pmb_stage|visible_on_board)\s*=/.test(moveClosure), 'booking move RPC must preserve vehicle authority');
const stationSnapshotClosure = corrective.slice(corrective.indexOf('create or replace function public.get_station_workshop_snapshot'), corrective.indexOf('create or replace function public.get_workshop_eligibility_snapshot'));
assert(stationSnapshotClosure.includes('wi.vehicle_id=any(v_ids)') && stationSnapshotClosure.includes('public.workshop_stage_code_for_work_key(wi.work_key)=v_stage') && !stationSnapshotClosure.includes('to_jsonb(v)') && !stationSnapshotClosure.includes('to_jsonb(w)'), 'station snapshot must scope/project vehicles and scope work-item children to the requested station');
assert(backup.indexOf('"workshop_stage_aliases"') > backup.indexOf('"workshop_stages"'), 'backup manifest must preserve canonical stage aliases after their parent stages');

assert(moduleSource.includes("plannerEnabled: false") && moduleSource.includes("code: 'SUBLET'"), 'Sublet requirement must remain canonical but planner-disabled');
assert(!planner.includes('SUBLET'), 'dormant Sublet planner branches must be physically absent');
assert(!app.includes("view: 'planner-sublet'") && !app.includes("path: 'workshop/sublet'"), 'Sublet must expose no planner route');
assert(planner.includes('workshopRequirePlannerStage') && planner.includes('This work type does not have a Workshop Planner'), 'legacy frontend schedule paths must fail closed for Sublet');
assert(migration.includes('workshop_prevent_disabled_planner_booking_mutation'), 'database must block hidden/legacy Sublet scheduling mutations');
assert(app.includes("key: 'sublet'") && app.includes('function renderSubletHome('), 'Sublet requirement/provider/status workflow must remain');
assert(app.includes('pdcRequirementDefinitions(vehicle).some(job => !pdcJobComplete(vehicle, job))'), 'RFT/QC gate must still include every required item, including Sublet');
assert(app.includes('teardownWorkshopEligibilityOverview({ clearSnapshot: true })'), 'route/auth teardown must not retain stale candidate authority');
for (const gate of ['scripts/test_station_planner_300_performance.js','scripts/test_station_planner_fixture_performance.js','scripts/test_station_planner_browser_performance.js','test_station_planner_resources.js']) {
  const inventory = read(gate).match(/const\s+(?:STAGES|STATIONS)\s*=\s*\[([^\]]*)\]/)?.[1] || '';
  assert(!inventory.includes('SUBLET'), `${gate} must not require the removed Sublet planner`);
}

console.log(`All-station authority/Sublet contract: ${stations.length} stations passed`);
