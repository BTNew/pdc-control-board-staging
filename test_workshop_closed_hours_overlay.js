'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
global.parseIsoTimestamp=v=>{const d=new Date(v);return Number.isNaN(d.getTime())?null:d;};global.cleanNavisionText=v=>String(v??'').trim();global.escapeHtml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const planner=require('./workshop-planner.js'),config=planner.WORKSHOP_CONFIG;
Object.assign(config,{dayStartMinutes:360,dayEndMinutes:990,dayLengthMinutes:630,workingDayIndexes:[1,2,3,4,5],closureDateKeys:['2026-10-06'],breakWindowsByDateOrScope:[],overtimeWindowsByDateOrScope:[]});
function geometry(html){return [...html.matchAll(/--closed-start:([\d.]+)%;--closed-size:([\d.]+)%/g)].map(m=>({start:Math.round(Number(m[1])*630/100),size:Math.round(Number(m[2])*630/100)}));}
test('Bus bay closed shading starts at 3pm except bays 8/9 at 2pm, independently of existing bookings',()=>{
 const before=JSON.stringify(config);
 for(let bay=1;bay<=10;bay++){
  const html=planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'BUS_4X4',bay});
  assert.deepEqual(geometry(html),[{start:[8,9].includes(bay)?480:540,size:[8,9].includes(bay)?150:90}]);
  assert.match(html,new RegExp('Closed '+([8,9].includes(bay)?'2:00':'3:00')+' pm–4:30 pm'));
 }
 assert.equal(JSON.stringify(config),before,'Rendering must not change configured hours');
 assert.equal(planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'FITTING',bay:8}),'');
 assert.equal(planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'BUS_4X4',bay:11}),'');
});
test('closed hours include existing breaks, weekends and closures in daily and weekly orientations',()=>{
 config.breakWindowsByDateOrScope=[{startMinutes:720,endMinutes:750,dateKey:'',scope:'global'}];
 assert.deepEqual(geometry(planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'BUS_4X4',bay:3})),[{start:360,size:30},{start:540,size:90}]);
 const vertical=planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'BUS_4X4',bay:8,vertical:true});assert.match(vertical,/workshop-closed-time is-vertical/);assert.deepEqual(geometry(vertical),[{start:360,size:30},{start:480,size:150}]);
 for(const day of ['2026-10-03','2026-10-06'])assert.deepEqual(geometry(planner.workshopUnavailableTimeHtml(day,{stage:'BUS_4X4',bay:3})),[{start:0,size:630}]);
 config.breakWindowsByDateOrScope=[];
 global.window={__workshopDataService:{getLastSnapshot:()=>({planning_calendar:{verified:true,closures:['2026-10-05']}})}};
 assert.deepEqual(geometry(planner.workshopUnavailableTimeHtml('2026-10-05',{stage:'BUS_4X4',bay:8})),[{start:0,size:630}]);
 delete global.window;
});
test('other workshop calendars retain configured break/overtime availability',()=>{
 config.breakWindowsByDateOrScope=[{startMinutes:720,endMinutes:750,dateKey:'',scope:'global'}];
 config.overtimeWindowsByDateOrScope=[{startMinutes:990,endMinutes:1080,dateKey:'',scope:'global',overtime:true}];
 assert.deepEqual(geometry(planner.workshopUnavailableTimeHtml('2026-10-02',{stage:'FITTING',bay:1})),[{start:360,size:30}]);
 assert.equal(planner.workshopBusShift({stage:'BUS_4X4',bay:8,calendarVehicle:{department_codes:['139']}}),null,'No change to booking department authority');
});
test('daily bay renderer supplies bay-specific overlays with only two Bus calendar calculations',()=>{
 const source=fs.readFileSync('workshop-planner.js','utf8'),start=source.indexOf('function workshopBayRowsHtml('),end=source.indexOf('\nfunction ',start+10);let calls=[];
 const ctx={workshopStageBayCount:()=>10,workshopLoadAdminBlocks:()=>[],workshopBayMechanic:()=>'',workshopAssigneeOptions:()=>'',workshopPad:v=>String(v).padStart(2,'0'),escapeHtml:v=>String(v),WORKSHOP_PENDING_BAY_ASSIGNMENTS:new Set(),workshopDropPreviewHtml:()=>'',workshopUnavailableTimeHtml:(date,options)=>{calls.push(options);return '<i data-closed-bay="'+options.bay+'"></i>';}};
 vm.runInNewContext(source.slice(start,end)+';this.render=workshopBayRowsHtml;',ctx);
 const html=ctx.render('BUS_4X4','2026-10-02',[]);assert.equal(calls.length,2);assert.equal((html.match(/data-closed-bay="1"/g)||[]).length,8);assert.equal((html.match(/data-closed-bay="8"/g)||[]).length,2);
 calls=[];ctx.render('FITTING','2026-10-02',[]);assert.equal(calls.length,1);
});
test('workshop closed overlay uses exactly the Control Board stripe colours and remains pointer transparent',()=>{
 const css=fs.readFileSync('workshop-planner.css','utf8'),board=fs.readFileSync('styles.css','utf8');
 const block=css.match(/\.workshop-closed-time \{([^}]+)\}/)[1],a=block.match(/background:\s*([^;]+);/)[1],b=board.match(/\.control-board-closed-time \{[^}]*background:([^;]+);/)[1];
 assert.equal(a.replace(/\s+/g,''),b.replace(/\s+/g,''));assert.match(block,/pointer-events:\s*none/);
});
