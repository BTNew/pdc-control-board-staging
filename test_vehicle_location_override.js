const {test}=require('node:test'),assert=require('node:assert/strict');
const {mapServerVehicle}=require('./pdc-email-vehicle-location-service');
test('shared override controls displayed location and retains normal location and completion evidence',()=>{
 const source={id:'fixture',current_location:'YH',location_override:'RFT',location_override_reason:'Confirmed location',qc_completed_at:null};
 const mapped=mapServerVehicle(source);
 assert.equal(mapped.pdcLocation,'RFT');assert.equal(mapped.pdcAutomaticLocation,'YH');assert.equal(mapped.pdcLocationOverrideReason,'Confirmed location');assert.equal(mapped.pdcQcComplete,false);
 const cleared=mapServerVehicle({...source,current_location:'PMB',location_override:null});assert.equal(cleared.pdcLocation,'PMB');assert.equal(cleared.pdcLocationOverride,'');
});
