/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const searchFactory = require('./pdc-workshop-vehicle-search.js');
const source = fs.readFileSync(__dirname + '/workshop-planner.js', 'utf8');
const context = {
  cleanNavisionText: x => String(x || '').trim(),
  vehicleKey: x => x.vehicleKey || x.stock || '',
  displayStockNumber: x => x.stock || '',
  vehicleKeyNumber: x => x.keyNumber || '',
  vehicleJobcardNumber: x => x.jobCardNumber || '',
  vehicleCustomerName: x => x.customerName || '',
  displayVehicle: x => x.vehicle || '',
};
vm.createContext(context);
const searchApi = searchFactory.create(() => context);
context.PDC_WORKSHOP_VEHICLE_SEARCH_FACTORY = searchFactory;
context.PDC_WORKSHOP_VEHICLE_SEARCH = searchApi;
const start = source.indexOf('function workshopSnapshotVehicleToPlannerRow(');
const end = source.indexOf('\nfunction ', start + 10);
vm.runInContext(source.slice(start, end), context);
const vehicle = context.workshopSnapshotVehicleToPlannerRow({
  id: 'v1', stock_number: 'U158863', key_number: '407', job_card_number: null,
  job_card_numbers: ['J138000824', 'J138000825'], vehicle_description: 'TOYHIA',
}, [], 'BUS_4X4');
assert.match(searchApi.workshopVehicleSearchText(vehicle), /j138000824/);
assert.match(searchApi.workshopVehicleSearchText(vehicle), /j138000825/);
assert.equal(searchApi.workshopSearchRank(vehicle, 'J138000824'), 0);
assert.equal(searchApi.workshopSearchRank(vehicle, '407'), 0);
assert.equal(searchApi.workshopSearchRank(vehicle, 'U158863'), 0);
assert.equal(vehicle.vehicle, 'TOYHIA');
assert.equal(searchApi.workshopSearchJobCards({ jobCardNumber: 'OLD', jobCardNumbers: ['OLD', null, 42, 'NEW'] }).join(','), 'OLD,NEW');
assert.equal(searchApi.workshopSearchRank({ stock: 'OTHER', jobCardNumber: 'J138000824X' }, 'J138000824'), 2);
console.log('8 planner linked-job/key/search assertions passed');
