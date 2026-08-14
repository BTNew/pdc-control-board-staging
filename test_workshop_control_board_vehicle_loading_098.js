'use strict';
const fs=require('fs');
const assert=require('assert');
const sql=fs.readFileSync('supabase/staging_only/098_workshop_control_board_vehicle_loading.sql','utf8');
const app=fs.readFileSync('app.js','utf8');
const actions=fs.readFileSync('vehicle-lifecycle-actions.js','utf8');

assert.match(sql,/project_ref='cdsmnqxtyyoeoznmbidd'/,'staging sentinel is pinned');
assert.match(sql,/version='097'/,'migration 097 is required');
assert.match(sql,/function public\.pmb_transfer_vehicle\(/,'protected PMB transfer RPC exists');
assert.match(sql,/require_pdc_role\('operator'\)/,'PMB transfer requires operator authority');
assert.match(sql,/v_before\.version<>p_expected_version/,'optimistic concurrency is enforced');
assert.match(sql,/v_location not in \('YH','IT'\)/,'only YH or IT can explicitly enter PMB');
assert.match(sql,/insert into public\.vehicle_movements/,'movement is recorded');
assert.match(sql,/audit_pdc_event/,'transfer is audited');
assert.match(sql,/pdc_email_vehicle_revision/,'email snapshot revision is advanced');
assert.match(sql,/'pipeline',\(select/,'Control Board pipeline metrics are restored');
assert.match(sql,/v\.eta_to_kewdale is not null/,'IT still requires Kewdale ETA');
assert.match(sql,/grant execute on function public\.pmb_transfer_vehicle\(uuid,integer\) to authenticated,service_role/,'RPC remains authenticated');

assert.match(actions,/pmbTransferVehicle\(\{ vehicleId, expectedVersion \}, expectedOwner = null\)/,'lifecycle bridge exposes PMB transfer');
assert.match(actions,/rpc\('pmb_transfer_vehicle'/,'bridge uses exact RPC name');
assert.match(app,/workflowBucketsCollapsed: false/,'Control Board vehicle rows open on first load');
assert.match(app,/async function transferYhVehicleToPmb\(key = ''\) \{\s*const vehicle = selectedVehicle\(key\);/,'PMB transfer resolves canonical/shared aliases instead of silently missing server-authoritative rows');
assert.match(app,/operation === 'transfer to PMB'[\s\S]*?__emailVehicleServerAuthoritative === true/,'email vehicles allow only the protected PMB action');
assert.match(app,/lifecycleOwner\.actions\.pmbTransferVehicle/,'UI calls shared PMB transfer through the exact captured authority owner');
assert.match(app,/const emailVehicleId = String\(vehicle\.__emailVehicleId \|\| ''\)\.trim\(\);[\s\S]*?const emailVersion = Number\(vehicle\.__emailVehicleVersion\);/,'PMB transfer uses the exact authenticated snapshot UUID/version before any typed-identity fallback');
assert.match(app,/await refreshEmailVehicleLocations\(\)/,'UI reloads authoritative email vehicle state');
assert.match(app,/Required work is retained from the authenticated email import/,'imported work remains server-authoritative during transfer');

console.log('PASS migration 098 and workshop vehicle-loading contract');
