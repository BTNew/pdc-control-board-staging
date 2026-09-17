'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const api=require('./pdc-new-vehicles.js');
const {mapServerVehicle}=require('./pdc-email-vehicle-location-service.js');
const intake=fs.readFileSync('pdc-new-vehicles.js','utf8');
const appSource=fs.readFileSync('app.js','utf8');
const sourceId='11111111-1111-4111-8111-111111111111';
const lineKey=`source:${sourceId}`;
const line={line_identity:lineKey,source_line_id:sourceId,department:'138',stage_code:'SUBLET',description:'Accessory',estimated_hours:2.25,active:true,completed:false};

test('all Department 138 review choices send Bus 4x4 and preserve supplied hours and source facts',()=>{
  const row={vehicle_id:'v1',status:'pending',operations:[line,{...line,line_identity:'other',department:'139',stage_code:'TINT'}]};
  const before=JSON.stringify(row);
  for(const [station] of [...api.STATIONS,['','']]) {
    const choices={[lineKey]:station,other:'ELECTRICAL'};
    const assignments=api.assignmentsFor(row,choices,{});
    assert.deepEqual(assignments.map(item=>item.stage_code),['BUS_4X4','ELECTRICAL']);
    assert.equal(assignments[0].estimated_hours,2.25);
    assert.deepEqual(api.problems(row,choices),[]);
    assert.equal(api.stationGroups(row,choices).find(group=>group.code==='BUS_4X4').hours,2.25);
    const receipt={ok:true,data:{vehicle_id:'v1',visible_on_board:true,bookings_created:0,operations:row.operations.map((item,index)=>({...item,stage_code:index?'ELECTRICAL':'BUS_4X4'}))}};
    assert.equal(api.verifyApproval(receipt,row,choices),true);
    receipt.data.operations[0].stage_code='FITTING';
    assert.equal(api.verifyApproval(receipt,row,choices),false);
  }
  assert.equal(JSON.stringify(row),before);
});

test('Department 138 review tile offers only Bus 4x4, allows hours and cannot drag to another station',()=>{
  const context={...api,choices:{[lineKey]:'FITTING'},hourDrafts:{},saving:false,sourceChanged:false,writable:()=>true};
  vm.createContext(context);
  vm.runInContext(intake.slice(intake.indexOf('  function operation(line)'),intake.indexOf('  function stationSection(group)')),context);
  const html=context.operation(line);
  assert.match(html,/draggable="false"/);
  assert.match(html,/data-nv-stage="[^"]+"[^>]*disabled/);
  assert.match(html,/<option value="BUS_4X4" selected>/);
  assert.doesNotMatch(html,/<option value="(?:FITTING|SUBLET|TINT)"/);
  assert.match(html,/Dept 138: window tint uses Tint; other work uses Bus 4×4/);
  assert.match(html,/data-nv-hours="[^"]+" value="2.25"/);
});

test('Department 138 changed operations normalize current and drafted stations before hours validation',()=>{
  const row={change_id:'c1',status:'pending',already_on_board:true,effective_hours:1.75,
    proposed:{department:'138',proposed_station:'FITTING'},current_work:{stage_code:'SUBLET',completed:false}};
  assert.equal(api.updateStation(row,{stage:'SUBLET'}),'BUS_4X4');
  assert.deepEqual(api.updateProblems(row,{stage:'SUBLET'}),[]);
  assert.ok(api.updateProblems({...row,effective_hours:0},{stage:'SUBLET'}).some(issue=>issue.includes('hours')));
  const html=api.operationUpdateHtml(row,{stage:'TINT'});
  assert.match(html,/data-update-stage disabled/);
  assert.match(html,/<option value="BUS_4X4" selected>/);
  assert.doesNotMatch(html,/<option value="(?:SUBLET|FITTING|TINT)"/);
  assert.equal(api.updateStation({...row,proposed:{department:'139'},current_work:{department:'138',stage_code:'TINT'}},{stage:'FITTING'}),'FITTING');
});

function detailRuntime(department='138') {
  const vehicle={id:'v1',department:'139'},detail={vehicle_version:1,job_card_lines:[{...line,department}]};
  const requests=[],alerts=[];
  const context={console,vehicle,detail,requests,alerts,app:{vehicleWorkshopDetailCache:new Map([['v1',{detail}]])},
    selectedVehicle:()=>vehicle,vehicleWorkshopDetailCanonicalId:()=>vehicle.id,vehicleDepartmentCode:vehicle=>String(vehicle.department||''),
    vehicleWorkshopCanEditLines:()=>true,vehicleWorkshopStageCode:stage=>String(stage).toUpperCase(),cleanNavisionText:value=>String(value??'').trim(),
    window:{alert:message=>alerts.push(message),prompt:()=>{throw Error('Unexpected prompt');},PDC_SUPABASE_CONFIG:{url:'https://example.test',publishableKey:'public'}},
    getPdcSupabaseAccessToken:()=> 'token',fetch:async(url,options)=>{requests.push(JSON.parse(options.body));return {ok:true,json:async()=>({ok:true})};},
    loadVehicleWorkshopDetail:async()=>true};
  vm.createContext(context);
  vm.runInContext(appSource.slice(appSource.indexOf('function vehicleWorkshopDepartment138('),appSource.indexOf('function vehicleWorkshopGroups(')),context);
  vm.runInContext(appSource.slice(appSource.indexOf('async function saveVehicleWorkshopLine('),appSource.indexOf('async function scheduleVehicleWorkshopNextAvailable(')),context);
  return context;
}

test('vehicle detail locks matching source department while preserving mixed-source jobs',()=>{
  const context=detailRuntime();
  assert.equal(context.vehicleWorkshopDepartment138(context.vehicle,{line_key:lineKey},context.detail),true);
  context.vehicle.department='138';context.detail.job_card_lines[0].department='139';
  assert.equal(context.vehicleWorkshopDepartment138(context.vehicle,{line_key:lineKey,department:'138'},context.detail),false);
  assert.equal(context.vehicleWorkshopDepartment138(context.vehicle,{department:'137'}),false);
  assert.equal(context.vehicleWorkshopDepartment138(context.vehicle,{workshopManualLine:true}),true);
  context.detail.job_card_lines=[];
  context.detail.line_adjustments=[{line_key:lineKey,department:'139'}];
  assert.equal(context.vehicleWorkshopDepartment138(context.vehicle,{line_key:lineKey},context.detail),false);
});

test('server mapping preserves each source department through the workshop and QC projections',()=>{
  const source=[{...line,department:138,operation_line_id:sourceId,operation_no:'OP1',work_key:'bus4x4'},
    {...line,line_identity:'source:22222222-2222-4222-8222-222222222222',source_line_id:'22222222-2222-4222-8222-222222222222',department:'139',operation_line_id:'22222222-2222-4222-8222-222222222222',operation_no:'OP2',work_key:'fitting'}];
  const before=JSON.stringify(source);
  const vehicle=mapServerVehicle({id:'v1',operation_lines:source,qc_operation_lines:source});
  assert.deepEqual(vehicle.pdcEmailOperationLines.map(item=>item.department),['138','139']);
  assert.deepEqual(vehicle.pdcQcOperationLines.map(item=>item.department),['138','139']);
  assert.equal(JSON.stringify(source),before);
  const context=detailRuntime();vehicle.department='138';
  assert.equal(context.vehicleWorkshopDepartment138(vehicle,{line_key:source[1].line_identity}),false);
  vehicle.pdcEmailOperationLines=[];
  assert.equal(context.vehicleWorkshopDepartment138(vehicle,{line_key:source[1].line_identity}),false);
  assert.equal(context.vehicleWorkshopDepartment138(vehicle,{line_key:lineKey}),true);
});

test('actual vehicle detail move and edit handlers reject non-Bus requests before any write',async()=>{
  const context=detailRuntime(),select={dataset:{lineKey,stage:'BUS_4X4'},value:'FITTING'};
  assert.equal(await context.moveVehicleWorkshopLineStage(select),false);
  assert.equal(select.value,'BUS_4X4');
  assert.equal(await context.moveVehicleWorkshopSourceLineStage(select,'TINT'),false);
  assert.equal(await context.saveVehicleWorkshopLine({stage:'SUBLET',lineKey,description:'Accessory',hours:2.25,hoursOnly:true}),false);
  assert.equal(context.requests.length,0);
  assert.equal(context.alerts.length,3);
  assert.equal(await context.saveVehicleWorkshopLine({stage:'BUS_4X4',lineKey,description:'Accessory',hours:2.25,hoursOnly:true}),true);
  assert.equal(context.requests[0].p_stage_code,'BUS_4X4');
  assert.equal(context.requests[0].p_estimated_hours,2.25);
});

test('other departments still move normally on a Department 138 vehicle',async()=>{
  const context=detailRuntime('139');context.vehicle.department='138';
  assert.equal(await context.moveVehicleWorkshopSourceLineStage({dataset:{lineKey}},'ELECTRICAL'),true);
  assert.equal(context.requests[0].p_stage_code,'ELECTRICAL');
});

test('Department 138 window tint stays in Tint through review and approval without changing source hours',()=>{
  for (const description of ['WINDOW TINT','M1 WINDOW TINT','DARKEST LEGAL WINDOW TINT','Window tinting']) {
    const tint={...line,description,stage_code:'BUS_4X4',estimated_hours:1.5};
    const row={vehicle_id:'v1',status:'pending',operations:[tint]};
    const choices={[lineKey]:'BUS_4X4'};
    assert.equal(api.assignedStation(tint,choices),'TINT');
    const assignment=api.assignmentsFor(row,choices,{})[0];
    assert.equal(assignment.stage_code,'TINT');
    assert.equal(assignment.estimated_hours,1.5);
    assert.equal(api.stationGroups(row,choices).find(group=>group.code==='TINT').hours,1.5);
    assert.equal(tint.stage_code,'BUS_4X4');
    const context={...api,choices,hourDrafts:{},saving:false,sourceChanged:false,writable:()=>true};
    vm.createContext(context);
    vm.runInContext(intake.slice(intake.indexOf('  function operation(line)'),intake.indexOf('  function stationSection(group)')),context);
    const html=context.operation(tint);
    assert.match(html,/<option value="TINT" selected>/);
    assert.doesNotMatch(html,/<option value="BUS_4X4"/);
    assert.equal(api.verifyApproval({ok:true,data:{vehicle_id:'v1',visible_on_board:true,bookings_created:0,operations:[{...tint,stage_code:'TINT'}]}},row,choices),true);
  }
});

test('tinted protectors remain Bus 4x4 while changed window tint uses Tint',()=>{
  for (const description of ['TINTED WEATHER SHIELDS','TINTED BONNET PROTECTOR','Accessory']) {
    assert.equal(api.assignedStation({...line,description}),'BUS_4X4');
  }
  const row={change_id:'c1',status:'pending',already_on_board:true,effective_hours:1.75,
    proposed:{department:'138',description:'WINDOW TINT',proposed_station:'BUS_4X4'},
    current_work:{stage_code:'BUS_4X4',completed:false}};
  assert.equal(api.updateStation(row,{stage:'BUS_4X4'}),'TINT');
  const html=api.operationUpdateHtml(row,{stage:'BUS_4X4'});
  assert.match(html,/<option value="TINT" selected>/);
  assert.doesNotMatch(html,/<option value="BUS_4X4"/);
});
