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
const index = read('index.html');

const stations = ['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION'];
for (const stage of stations) {
  assert(moduleSource.includes(`code: '${stage}'`), `canonical frontend mapping missing ${stage}`);
  assert(migration.includes(`'${stage}'`), `canonical database mapping missing ${stage}`);
}
for (const alias of ['Bus 4x4','BUS4X4','Fabrication','Fab','Electrical','Elec','Tyre Bay','Tyre','Pit Inspection','Pit']) {
  assert(moduleSource.toLowerCase().includes(alias.toLowerCase()), `frontend aliases missing ${alias}`);
  assert(migration.toLowerCase().includes(alias.toLowerCase()), `database aliases missing ${alias}`);
}

assert(index.indexOf('workshop-eligibility.js') < index.indexOf('app.js'), 'canonical mapping must load before app routing/counts');
assert(app.includes('return authoritativeWorkshopVehiclesForStage(normalizedStage)'), 'shared Control Board counts must fail over to authoritative candidates, not browser-local filtering');
assert(app.includes("get_workshop_eligibility_snapshot"), 'Control Board must load canonical aggregate RPC');
assert(app.includes("{ allStations: true }"), 'Control Board must subscribe to all station revision signals');
assert(app.includes("table = stageCode || allStations ? 'workshop_station_revision'"), 'all-station Realtime must use station revision authority');
assert(planner.includes('WORKSHOP_ELIGIBILITY_RUNTIME.workshopCanonicalEligibility'), 'planner must apply the canonical candidate contract');
assert(migration.match(/get_station_workshop_snapshot[\s\S]*workshop_station_eligibility\(v_stage\)/), 'station RPC must use canonical eligibility');
assert(migration.match(/get_workshop_eligibility_snapshot[\s\S]*workshop_station_eligibility\(s\.code\)/), 'Control Board RPC must use canonical eligibility');
assert(migration.includes("in('PMB','YH')") && migration.includes("='IT'"), 'database eligibility must implement PMB/YH/IT rules');
assert(migration.includes("'missing_eta'"), 'missing IT ETA must remain visible and disabled');
assert(!/(update\s+public\.vehicles|insert\s+into\s+public\.vehicle_movements)/i.test(migration), 'eligibility migration must never change location/workflow state');
assert(migration.includes('workshop_station_revision_from_vehicle') && migration.includes('vehicle_work_items'), 'location changes must invalidate every outstanding requirement station');

assert(moduleSource.includes("plannerEnabled: false") && moduleSource.includes("code: 'SUBLET'"), 'Sublet requirement must remain canonical but planner-disabled');
assert(!app.includes("view: 'planner-sublet'") && !app.includes("path: 'workshop/sublet'"), 'Sublet must expose no planner route');
assert(planner.includes('workshopRequirePlannerStage') && planner.includes('This work type does not have a Workshop Planner'), 'legacy frontend schedule paths must fail closed for Sublet');
assert(migration.includes('workshop_prevent_disabled_planner_booking_mutation'), 'database must block hidden/legacy Sublet scheduling mutations');
assert(app.includes("key: 'sublet'") && app.includes('function renderSubletHome('), 'Sublet requirement/provider/status workflow must remain');
assert(app.includes('pdcRequirementDefinitions(vehicle).some(job => !pdcJobComplete(vehicle, job))'), 'RFT/QC gate must still include every required item, including Sublet');
assert(app.includes('teardownWorkshopEligibilityOverview({ clearSnapshot: true })'), 'route/auth teardown must not retain stale candidate authority');

console.log(`All-station authority/Sublet contract: ${stations.length} stations passed`);
