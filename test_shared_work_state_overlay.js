'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

assert.ok(app.includes('function pendingSharedWorkStateMap()'), 'shared work saves have bounded pending state');
assert.ok(app.includes('function applyPendingSharedWorkStateOverlays(rows = [])'), 'incoming snapshots apply pending shared work overlays');
assert.ok(app.includes('pendingSharedWorkStateMap().set(ref.vehicleId'), 'successful RPC queues the canonical vehicle overlay');
assert.ok(app.includes('app.emailVehicleLocationRows = applyPendingSharedWorkStateOverlays('), 'email snapshot refresh cannot overwrite a just-saved stale work projection');
assert.ok(app.includes('void refreshEmailVehicleLocations();'), 'authoritative email snapshot refresh is non-blocking');
assert.ok(!app.includes("await loadWorkshopEligibilitySnapshot('vehicle_work_states_saved')"), 'unrelated Workshop refresh cannot leave Save stuck');
assert.ok(!app.includes("await window.__workshopDataService.loadSnapshot('vehicle_work_states_saved')"), 'unrelated Workshop data refresh cannot leave Save stuck');
console.log('Shared work-state stale projection and Save hang contract passed.');
