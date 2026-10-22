/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
test('Department 135 retains the exact PMB planner and calendar helper implementations',()=>{
 for(const file of ['workshop-booking-timing.js','workshop-display-identity.js','workshop-reference-data-service.js','workshop-realtime.js','workshop-navigation.js','pdc-planner-capacity.js']) assert.deepEqual(fs.readFileSync(path.join(__dirname,'karratha',file)),fs.readFileSync(path.join(__dirname,file)),file);
});
test('Department135 retains its original planner presentation',()=>{
 const crypto=require('node:crypto');
 // r417: PMG workshop-shared-actions.js asks to confirm a bay rule warning; the Karratha copy stays frozen.
 const hashes={"workshop-shared-actions.js":"6080315b8615d544ecec0ad324be883e064ecb912a2c5a28c41a19f11d4980d5","pdc-planner-slim.js":"941e4c695533816856dd64f5c43d7f0da9fb4d41ef6f7a8747827607ade85e36","workshop-data-service.js": "004267f09a9fa4f5ad0852dd8f983e25395d8352f8b0f9fb798777b3d733e9ff","workshop-planner.css": "ac0c86ee34a4785aeee648513da5b9ce188fabf0425f9964dc6ea94f34ae53f1", "control-board-overview.js": "440d999fb5478214a2c763093068b3446bbdd7f97847853f26e86650fb13c7b1"};
 for(const [file,hash] of Object.entries(hashes))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'karratha',file),'utf8').replace(/\r\n/g,'\n')).digest('hex'),hash);
});
test('all six native planner routes remain and no Bus route can be selected',()=>{
 const html=fs.readFileSync(path.join(__dirname,'karratha/index.html'),'utf8');
 for(const station of ['tint','hoist','fitting','fab','elec','tyre'])assert.ok(html.includes('data-view="planner-'+station+'"'),station);
 assert.equal(html.includes('data-view="planner-bus-4x4"'),false);
 const app=fs.readFileSync(path.join(__dirname,'karratha/app.js'),'utf8');assert.ok(app.includes("['import', 'planner-bus-4x4', 'dept-bus-4x4'].includes(view)"));assert.ok(app.includes('k135VehicleTrackingCore'));
});
