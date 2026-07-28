'use strict';
const assert=require('assert');
const fs=require('fs');
const vm=require('vm');
const appSource=fs.readFileSync('app.js','utf8');
const css=fs.readFileSync('styles.css','utf8');
const pipelineSql=fs.readFileSync('supabase/staging_only/084_control_board_station_pipeline.sql','utf8');
const salesSql=fs.readFileSync('supabase/staging_only/085_salesperson_email_defaults.sql','utf8');

const functionStart=appSource.indexOf('function controlBoardStationPipelineMetrics');
const functionEnd=appSource.indexOf('\nfunction renderWorkflowBoard()',functionStart);
assert(functionStart>0&&functionEnd>functionStart,'Pipeline helpers must exist before Control Board rendering');
const context={app:{workshopEligibilityState:'connected',workshopEligibilitySnapshot:null},normalizePmbStage:v=>String(v||'').toUpperCase(),pmbStageLabel:v=>String(v||''),escapeHtml:v=>String(v??'').replace(/&/g,'&amp;').replace(/"/g,'&quot;')};
vm.createContext(context);
vm.runInContext(`${appSource.slice(functionStart,functionEnd)}\nthis.metricsFn=controlBoardStationPipelineMetrics;this.timeFn=controlBoardAverageBayTimeLabel;this.htmlFn=controlBoardStationPipelineHtml;`,context);
context.app.workshopEligibilitySnapshot={pipeline:[{stage_code:'TINT',it:2,pmb_waiting:5,in_bays:3,average_bay_hours:4.5,stoppage:1,completed_mtd:7}]};
assert.deepStrictEqual(JSON.parse(JSON.stringify(context.metricsFn('TINT'))),{stage:'TINT',it:2,pmbWaiting:5,inBays:3,averageBayHours:4.5,stoppage:1,completedMtd:7});
assert.strictEqual(context.timeFn(.5),'30m');
assert.strictEqual(context.timeFn(4.5),'4.5h');
assert.strictEqual(context.timeFn(49),'2d 1h');
const html=context.htmlFn('TINT');
for(const text of ['IT <b>2</b>','PMB wait <b>5</b>','Bays <b>3</b>','avg 4.5h','Stop <b>1</b>','Done MTD <b>7</b>']) assert(html.includes(text),`Pipeline missing ${text}`);
assert(appSource.indexOf('${controlBoardStationPipelineHtml(stage)}')<appSource.indexOf('Open ${escapeHtml(label)} Planner'),'Pipeline must render immediately before the planner action');
assert(css.includes('grid-template-columns: 20px minmax(100px, 145px) 48px minmax(220px, .7fr) minmax(560px, 1.6fr) auto'),'Control Board row must reserve chart space beside planner buttons');
for(const token of ["'it'","'pmb_waiting'","'in_bays'","'average_bay_hours'","'stoppage'","'completed_mtd'","time zone 'Australia/Perth'","b.status='started'","b.status='completed'"]) assert(pipelineSql.includes(token),`Pipeline SQL missing ${token}`);
assert(pipelineSql.includes("perform public.require_pdc_role('viewer')"),'Pipeline snapshot must preserve Viewer read authority');

const expected={JB:'jason.battle@pmgwa.com.au',KB:'kevin.bonser@pmgwa.com.au',CF:'clint.franklin@pmgwa.com.au',BH:'brooke.hornby@pmgwa.com.au',SL:'scott.lovett@pmgwa.com.au',SP:'stephen.peck@pmgwa.com.au',PS:'paul.symmons@broometoyota.com.au',DW:'dave@pmgwa.com.au',AW:'andy.weir@broometoyota.com.au',BG:'bryce.guthrie@broometoyota.com.au',PM:'peter.morris@broometoyota.com.au',CW:'craig.watson@broometoyota.com.au'};
for(const [code,email] of Object.entries(expected)){
  assert(appSource.includes(`initials: '${code}'`)&&appSource.includes(`email: '${email}'`),`Frontend roster missing ${code}`);
  assert(salesSql.includes(`'${code}'`)&&salesSql.includes(email),`Shared roster migration missing ${code}`);
}
assert(appSource.includes("['FO', 'SP']"),'FLEET ORDER UP must resolve through the supplied Stephen Peck address');
assert(salesSql.includes("if v_code='FO' then v_code:='SP'; end if"),'Shared vehicle resolution must map FO to SP');
assert(salesSql.includes('pdc_default_vehicle_salesperson_trigger'),'Future shared vehicle imports must resolve salesperson defaults');
assert(salesSql.includes('where salesperson_id is null'),'Backfill must preserve existing explicit salesperson assignments');
assert(salesSql.includes('count(distinct s.id)>1'),'Roster migration must fail closed on ambiguous existing identities');
console.log('Control Board pipeline and salesperson email default contracts passed');
