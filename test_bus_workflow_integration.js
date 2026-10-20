'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const layout=require('./pdc-workshop-departments.js'),overview=require('./control-board-overview.js');
const fixture=require('./qa/control-board-fixtures.js');
const planner=fs.readFileSync('workshop-planner.js','utf8');
test('138 has five Bus4x4 destinations plus the shared Tint and Tyre stations',()=>{
 const options=layout.options('138');assert.equal(options.length,7);
 assert.deepEqual(options.slice(0,5).map(x=>[x.label,x.bays]),[['Mechanical',[1,2,3,4]],['Accessories',[10]],['Electrical',[8,9]],['QA',[7]],['Pit',[]]]);
 assert.equal(options[4].external,true);
 assert.deepEqual(options.slice(5).map(x=>x.stage),['TINT','TYRE']);
 assert.deepEqual(layout.BUS_GROUPS.flatMap(x=>x.bays),[1,2,3,4,5,6,7,8,9,10]);
});
test('139 and 138 see identical shared capacity and bookings from both departments',()=>{
 const snapshot=fixture.emptySnapshot();
 const bus=snapshot.board.bays.find(b=>b.stage_code==='BUS_4X4');
 snapshot.board.bays.push(...[9,10].map(n=>({...bus,bay_id:fixture.uuid(5000+n),bay_number:n})));
 const tint=snapshot.board.bays.find(b=>b.stage_code==='TINT');
 const tyre=snapshot.board.bays.find(b=>b.stage_code==='TYRE');
 snapshot.board.bookings.push(fixture.booking(501,tint,fixture.vehicle(501,{department_codes:['138']})));
 snapshot.board.bookings.push(fixture.booking(502,tyre,fixture.vehicle(502,{department_codes:['139']})));
 const a=overview.buildModel(snapshot,{department:'138'}),b=overview.buildModel(snapshot,{department:'139'});
 assert.equal(a.totalBays,14);assert.equal(b.totalBays,35);
 const shared=m=>m.columns.filter(c=>['TINT','TYRE'].includes(c.stage)).map(c=>({id:c.bay.bay_id,items:c.items.map(i=>i.source.booking_id)}));
 assert.deepEqual(shared(a),shared(b));assert.equal(a.totalBookings,2);assert.equal(b.totalBookings,2);
 assert.ok(a.columns.every(c=>layout.stageVisible(c.stage,'138')));
 assert.ok(b.columns.every(c=>layout.stageVisible(c.stage,'139')));
});
test('independent shared operations split without inventing conversion hours',()=>{
 for(const d of ['Window tint','Tinting'])assert.equal(layout.sharedStation(d),'TINT',d);
 for(const d of ['Tyres upgrade','6 x rims and tyres','Wheel alignment','Second spare genuine wheel'])assert.equal(layout.sharedStation(d),'TYRE',d);
 for(const d of ['Coaster bus 4x4 conversion with tyres','Spare wheel carrier','Wheel nut indicators','Wheel chocks','Wheelchair lift','Bonnet protector'])assert.equal(layout.sharedStation(d),'BUS_4X4',d);
});
test('group view and Schedule both use the selected station bays',()=>{
 const state={busBayGroup:'mechanical'},context={window:{PDC_WORKSHOP_DEPARTMENTS:layout},workshopState:()=>state,workshopStageBayCount:()=>10,workshopPad:n=>String(n).padStart(2,'0')};
 vm.createContext(context);vm.runInContext(planner.slice(planner.indexOf('function workshopDepartmentLayout('),planner.indexOf('function workshopBayRowsHtml(')),context);
 assert.deepEqual(Array.from(context.workshopVisibleBays('BUS_4X4')),[1,2,3,4]);
 state.busBayGroup='electrical';assert.deepEqual(Array.from(context.workshopVisibleBays('BUS_4X4')),[8,9]);
 state.focusedBookingMode=true;assert.equal(context.workshopVisibleBays('BUS_4X4').length,10);
 state.focusedBookingMode=false;
 state.busBayGroup='';assert.equal(context.workshopVisibleBays('BUS_4X4').length,10);
 assert.match(context.workshopBayChoiceLabel('BUS_4X4',10),/Accessory Fitting/);
 const start=planner.indexOf('function openWorkshopScheduleModal('),modal=planner.slice(start,planner.indexOf('\nfunction ',start+1));
 assert.match(modal,/const categoryBays = workshopCategoryBays\(normalizedStage, scheduleCategory\)/);assert.match(modal,/categoryBays\.map/);
 assert.doesNotMatch(modal,/Choose any suitable Bus4x4 bay/);
});
test('working shell loads department layout and retires readiness panels',()=>{
 const html=fs.readFileSync('index.html','utf8');
 assert.match(html,/src="pdc-workshop-departments.js/);
 assert.doesNotMatch(html,/<script[^>]*src="pdc-bus-workflow.js/);
 assert.doesNotMatch(planner,/<button[^>]+data-bus-workflow-open/);
 assert.doesNotMatch(planner,/<div[^>]+data-bus-workflow-host/);
 assert.doesNotMatch(planner,/PdcBusWorkflow\.mountPlanner|data-bus-workflow-host|data-bus-workflow-open|busWorkflowVehicleId/);
});
test('database change preserves compatibility, source history and bookings',()=>{
 const sql=fs.readFileSync('supabase/migrations/20261015005540_bus4x4_department_bays_and_shared_work.sql','utf8');
 const rule=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule'),sql.indexOf('-- Supplier operations'));
 assert.match(rule,/bus_bay_vehicle_incompatible/);assert.doesNotMatch(rule,/bus_stage_parts_required|parts_readiness/);
 for(const marker of ['existing_booking_changed','source_operation_changed','operation_hours_history_or_identity_changed','DROP TRIGGER bus_supplier_completion_guard','conversion_sections_required'])assert.ok(sql.includes(marker),marker);
});
