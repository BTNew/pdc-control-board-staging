const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {values,text}=require('./pdc-service-locations.js');
test('Tag and Block remain distinct, preserving leading zeroes',()=>{
 const v={tuneServiceLocations:{jobs:[{parts_location:'05C1A',vehicle_key_number:'00513'}]}};
 assert.equal(text(v,'parts_location'),'05C1A');assert.equal(text(v,'vehicle_key_number'),'00513');
});
test('multiple jobs retain distinct locations without duplication',()=>{
 const v={tuneServiceLocations:{jobs:[{parts_location:'A1'},{parts_location:'A2'},{parts_location:'A1'}]}};
 assert.deepEqual(values(v,'parts_location'),['A1','A2']);assert.equal(text(v,'vehicle_key_number'),'Not supplied');
});
test('PMB row displays escaped values; other locations unchanged',()=>{
 const ctx={window:{PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd'}},document:{createElement:()=>({}),head:{appendChild:()=>{}}},vehiclePdcLocation:v=>v.location,escapeHtml:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;'),vehicleIdentityCells:()=>[{label:'Key',value:'old'}],incomingVehicleDetailRow:()=>'<span class="incoming-card-main"><strong>Hilux</strong></span><div class="incoming-vehicle-detail-grid">'};
 vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-service-locations.js'),'utf8'),ctx);
 const v={location:'PMB',tuneServiceLocations:{jobs:[{ro_number:'J1',parts_location:'<A>',vehicle_key_number:'513'}]}};
 assert.match(ctx.incomingVehicleDetailRow(v),/Parts location/);assert.match(ctx.incomingVehicleDetailRow(v),/&lt;A&gt;/);assert.equal(ctx.vehicleIdentityCells(v)[0].value,'513');
 assert.doesNotMatch(ctx.incomingVehicleDetailRow({...v,location:'YH'}),/Parts location/);
});

