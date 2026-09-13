'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { mapServerVehicle, reconcileVehicleRows } = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync('app.js', 'utf8');
function fn(name) { const start=source.indexOf(`function ${name}(`); assert.ok(start>=0,name); const tail=source.slice(start+1).search(/\n(?:async )?function /); return source.slice(start,start+1+tail); }
const id='5b2bafda-dc41-48ba-81b5-379b0c885c37';
function harness() {
 const c={ app:{vehicleWorkshopDetailCache:new Map()}, Date, normalizePmbStage:v=>String(v||'').toUpperCase(),pmbStageLabel:v=>({FITTING:'Fitting',ELECTRICAL:'Electrical'})[v]||'',inferredPmbStage:v=>v.pmbStage||'',vehicleWorkshopDetailCanonicalId:v=>v.__emailVehicleId||'',parseIsoTimestamp:v=>v&&Number.isFinite(Date.parse(v))?new Date(v):null };
 vm.createContext(c); for(const name of ['vehicleWorkshopActivityLabel','incomingGridStatusLabel','collectedTransitTiming','refreshCollectedTransitTimers'])vm.runInContext(fn(name),c); return c;
}
function raw(bookings=[],extra={}) {return {id,stock_number:'SYNTHETIC-ONLY',current_location:'PMB',workshop_bookings:bookings,...extra};}
const booking={booking_id:'booking-one',stage_code:'FITTING',bay_name:'Bay 2',status:'started',scheduled_start_at:'2026-09-12T00:00:00Z',scheduled_end_at:'2026-09-14T00:00:00Z'};
test('maps supplied PMB fields and booking availability without deriving a location',()=>{
 const r=raw([booking],{current_location:'YH',pmb_stage:null,pmb_bay_stage:'FITTING',pmb_bay_number:'2',active_workshop_booking_id:'booking-one',workshop_status:'started'});const before=JSON.stringify(r);const m=mapServerVehicle(r);
 assert.equal(m.pdcLocation,'YH');assert.equal(m.pmbStage,'');assert.equal(m.pmbBayStage,'FITTING');assert.equal(m.pmbBay,'2');assert.equal(m.activeWorkshopBookingId,'booking-one');assert.equal(m.workshopStatus,'started');assert.equal(m.__emailVehicleWorkshopBookingsAvailable,true);assert.equal(JSON.stringify(r),before);
});
test('missing fields preserve an existing staff stream but explicit null clears the projection',()=>{
 const row={stock:'SYNTHETIC-ONLY',pmbStage:'FITTING'};
 assert.equal(reconcileVehicleRows([row],[raw([])]).rows[0].pmbStage,'FITTING');
 assert.equal(reconcileVehicleRows([row],[raw([],{pmb_stage:null})]).rows[0].pmbStage,'');
 const without={...raw()};delete without.workshop_bookings;assert.equal(mapServerVehicle(without).__emailVehicleWorkshopBookingsAvailable,false);
});
test('started and stopped bookings describe work while preserving physical location',()=>{
 const c=harness(); const v=mapServerVehicle(raw([booking],{current_location:'YH'}));assert.equal(c.vehicleWorkshopActivityLabel(v),'In progress · Fitting · Bay 2');assert.equal(v.pdcLocation,'YH');
 assert.equal(c.vehicleWorkshopActivityLabel(mapServerVehicle(raw([{...booking,status:'stoppage'}]))),'STOPPAGE · Fitting · Bay 2');
});
test('future planned work never becomes in progress or a physical station',()=>{
 const c=harness();const v=mapServerVehicle(raw([{...booking,status:'planned',scheduled_start_at:'2026-09-15T00:00:00Z'}]));
 assert.equal(c.incomingGridStatusLabel(v,'pmb',{now:Date.parse('2026-09-13T00:00:00Z')}),'Booked next · Fitting · Bay 2');
 assert.equal(c.vehicleWorkshopActivityLabel(v,{now:Date.parse('2026-09-16T00:00:00Z')}),'Planned — not started · Fitting · Bay 2');assert.equal(v.pdcLocation,'PMB');assert.equal(v.pmbStage,undefined);
});
test('started work remains in progress after its estimate until completed',()=>{const c=harness();assert.match(c.vehicleWorkshopActivityLabel(mapServerVehicle(raw([booking])),{now:Date.parse('2026-10-01')}),/^In progress/);});
test('completed canonical evidence overrides stale cached active work',()=>{
 const c=harness();c.app.vehicleWorkshopDetailCache.set(id,{status:'ready',detail:{vehicle_id:id,bookings:[booking]}});
 assert.equal(c.vehicleWorkshopActivityLabel(mapServerVehicle(raw([{...booking,status:'completed'}]))),'No active workshop booking');
});
test('multiple live bookings warn instead of picking a misleading current bay',()=>{
 const c=harness();assert.match(c.vehicleWorkshopActivityLabel(mapServerVehicle(raw([booking,{...booking,booking_id:'two',stage_code:'ELECTRICAL'}]))),/^Multiple active bookings/);
});
test('manual PMB stream and missing booking evidence have explicit labels',()=>{
 const c=harness();assert.equal(c.vehicleWorkshopActivityLabel(mapServerVehicle(raw([],{pmb_stage:'FITTING'}))),'PMB stream: Fitting');
 assert.equal(c.vehicleWorkshopActivityLabel({__emailVehicleId:id}),'Workshop activity not loaded');
});
test('fallback rejects another canonical vehicle and uses a verified supplied projection',()=>{
 const c=harness();const v={__emailVehicleId:id};
 c.app.vehicleWorkshopDetailCache.set(id,{status:'ready',detail:{vehicle_id:'other',bookings:[booking]}});
 assert.equal(c.vehicleWorkshopActivityLabel(v),'Workshop activity not loaded');
 c.app.vehicleWorkshopDetailCache.set(id,{status:'ready',detail:{vehicle_id:id,bookings:[booking]}});
 assert.equal(c.vehicleWorkshopActivityLabel(v),'In progress · Fitting · Bay 2');
 c.app.vehicleWorkshopDetailCache.clear();
 assert.equal(c.vehicleWorkshopActivityLabel(v,{bookingProjection:{available:true,activeBookings:[{sharedVehicleId:'other',stage:'FITTING',status:'started',bay:2}]}}),'No active workshop booking');
 assert.equal(c.vehicleWorkshopActivityLabel(v,{bookingProjection:{available:true,activeBookings:[{sharedVehicleId:id,stage:'FITTING',status:'started',bay:2}]}}),'In progress · Fitting · Bay 2');
});
test('open collected interval advances past collection using elapsed time',()=>{
 const c=harness(),v={dealerTransitStartedAt:'2026-09-12T00:00:00Z',rftCollectedAt:'2026-09-12T00:00:00Z'};
 assert.equal(c.collectedTransitTiming(v,Date.parse('2026-09-13T02:30:00Z')).label,'26h 30m');
 assert.equal(c.collectedTransitTiming(v,Date.parse('2026-09-13T02:31:00Z')).label,'26h 31m');
});
test('delivery freezes the interval and respects a canonical duration',()=>{
 const c=harness(),v={dealerTransitStartedAt:'2026-09-12T00:00:00Z',dealerTransitClosedAt:'2026-09-12T04:00:00Z'};
 assert.equal(c.collectedTransitTiming(v,Date.parse('2026-09-14')).label,'4h 0m');
 assert.equal(c.collectedTransitTiming({...v,dealerTransitDurationSeconds:7200}).label,'2h 0m');
 assert.match(c.collectedTransitTiming(v).note,/transit complete/);
});
test('unknown and future starts do not invent a zero-hour interval from booking/collection',()=>{
 const c=harness();assert.equal(c.collectedTransitTiming({rftTransportBookedAt:'2026-09-12',rftCollectedAt:'2026-09-12'}).label,'Start not recorded');
 assert.equal(c.collectedTransitTiming({dealerTransitStartedAt:'2026-09-15'},Date.parse('2026-09-13')).label,'Awaiting transit start');
});
test('timer stops when leaving the page or losing auth without repainting hidden content',()=>{
 const c=harness();let cleared=0;c.window={PDC_AUTH_CONTEXT:{userId:'synthetic'},clearInterval:()=>cleared++};c.app.collectedTransitTimer=123;c.app.currentView='dashboard';c.$$=()=>{throw Error('No hidden DOM read');};
 c.refreshCollectedTransitTimers();assert.equal(cleared,1);assert.equal(c.app.collectedTransitTimer,null);
 c.app.currentView='collected';c.app.collectedTransitTimer=124;delete c.window.PDC_AUTH_CONTEXT;c.refreshCollectedTransitTimers();assert.equal(cleared,2);
});
