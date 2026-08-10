const fs = require('fs');
const assert = require('assert');
const sql = fs.readFileSync('supabase/staging_only/083_navision_operational_location_and_completion.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'migration must be staging-sentinel guarded');
assert(sql.includes('navision_operational_location'), 'migration must centralise Navision operational location classification');
assert(sql.includes("like '%BODYBUILDER%'"), 'Body Builder must classify to PMB');
assert(sql.includes("then 'Completed'"), 'At Dealer must classify to Completed');
assert(sql.includes('v_open_work=0'), 'automatic completion must require no open required work');
assert(sql.includes("in ('PMB','PIT','QC','RFT','COMPLETED')"), 'ordinary reconciliation must preserve progressed workflow locations');
assert(sql.includes('canonical_vehicle_id'), 'activation rows must link to canonical vehicles');
assert(sql.includes('navision_record_operational_reconcile'), 'current Navision updates must trigger reconciliation');
assert(sql.includes('navision_activation_operational_reconcile'), 'activation must trigger canonical reconciliation');
assert(sql.includes("active=false"), 'completed Navision activations must leave the active board');
assert(sql.includes("'source','navision_operational_reconcile_083'"), 'vehicle changes must be audited');
assert(!sql.includes('vjdtsswhroyguxyfjdkt'), 'migration must not name the production project');

assert(app.includes("pdcLocation: completed ? 'Completed'"), 'shared canonical completion must map into the Completed UI model');
assert(app.includes(".filter(item => String(item.lifecycle_state || '').toLowerCase() === 'completed')"), 'Completed Vehicles must include shared canonical completions');
assert(app.includes('pdcLocation: shared.pdcLocation || vehicle.pdcLocation'), 'canonical shared location must override stale local display location');
assert(app.includes("const APP_VERSION = '2026.08.10.15-operation-routing-hours';"), 'release marker must remain explicit and immutable');

console.log('Navision operational location/completion migration contract passed');
