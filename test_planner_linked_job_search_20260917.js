const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/workshop-planner.js','utf8');
const context={cleanNavisionText:x=>String(x||'').trim(),vehicleKey:x=>x.vehicleKey||x.stock||'',displayStockNumber:x=>x.stock||'',vehicleKeyNumber:x=>x.keyNumber||'',vehicleJobcardNumber:x=>x.jobCardNumber||'',vehicleCustomerName:x=>x.customerName||'',displayVehicle:x=>x.vehicle||''};
vm.createContext(context);
for(const name of ['workshopSnapshotVehicleToPlannerRow','workshopSearchJobCards','workshopVehicleSearchText','workshopSearchRank']){
 const start=source.indexOf('function '+name+'('),end=source.indexOf('\nfunction ',start+10);
 vm.runInContext(source.slice(start,end),context);
}
const vehicle=context.workshopSnapshotVehicleToPlannerRow({id:'v1',stock_number:'U158863',key_number:'407',job_card_number:null,job_card_numbers:['J138000824','J138000825'],vehicle_description:'TOYHIA'},[],'BUS_4X4');
assert.match(context.workshopVehicleSearchText(vehicle),/j138000824/);
assert.match(context.workshopVehicleSearchText(vehicle),/j138000825/);
assert.equal(context.workshopSearchRank(vehicle,'J138000824'),0);
assert.equal(context.workshopSearchRank(vehicle,'407'),0);
assert.equal(context.workshopSearchRank(vehicle,'U158863'),0);
assert.equal(vehicle.vehicle,'TOYHIA');
assert.equal(context.workshopSearchJobCards({jobCardNumber:'OLD',jobCardNumbers:['OLD',null,42,'NEW']}).join(','),'OLD,NEW');
assert.equal(context.workshopSearchRank({stock:'OTHER',jobCardNumber:'J138000824X'},'J138000824'),2);
console.log('8 planner linked-job/key/search assertions passed');