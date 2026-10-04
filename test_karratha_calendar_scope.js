'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
test('Department 135 retains the exact PMB planner and calendar helper implementations',()=>{
 for(const file of ['workshop-planner.css','workshop-booking-timing.js','workshop-display-identity.js','workshop-data-service.js','workshop-reference-data-service.js','workshop-shared-actions.js','workshop-realtime.js','workshop-navigation.js','control-board-overview.js','pdc-planner-capacity.js','pdc-planner-slim.js']) assert.deepEqual(fs.readFileSync(path.join(__dirname,'karratha',file)),fs.readFileSync(path.join(__dirname,file)),file);
});
test('all six native planner routes remain and no Bus route can be selected',()=>{
 const html=fs.readFileSync(path.join(__dirname,'karratha/index.html'),'utf8');
 for(const station of ['tint','hoist','fitting','fab','elec','tyre'])assert.ok(html.includes('data-view="planner-'+station+'"'),station);
 assert.equal(html.includes('data-view="planner-bus-4x4"'),false);
 const app=fs.readFileSync(path.join(__dirname,'karratha/app.js'),'utf8');assert.ok(app.includes("['import', 'planner-bus-4x4', 'dept-bus-4x4'].includes(view)"));assert.ok(app.includes('k135VehicleTrackingCore'));
});
