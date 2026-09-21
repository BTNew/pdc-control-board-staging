'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const UUID = '11111111-1111-4111-8111-111111111111';
const OTHER_UUID = '22222222-2222-4222-8222-222222222222';
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));

function functionSource(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `Missing integration function ${name}`);
  const end = source.indexOf('\nfunction ', start + 1);
  return source.slice(start, end < 0 ? source.length : end);
}

function fixture(overrides = {}) {
  const state = {stage:'BUS_4X4', date:'2026-09-21'};
  const context = {
    WORKSHOP_UUID_PATTERN:/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    WORKSHOP_PENDING_STARTS:new Map(),
    escapeHtml, workshopState:() => state,
    vehicleKey:v => v.stock, displayStockNumber:v => v.stock,
    isPdcBlocked:() => false, workshopPartsSummary:() => ({status:'unknown',text:'Stage readiness needs confirmation'}),
    workshopQueueEstimatedLabel:() => '5.00h', workshopSchedulingDuration:() => ({hours:5}),
    workshopVehicleEtaConstraint:() => ({required:false,ok:true}),
    workshopOutstandingDisabledReasonLabel:reason => reason || '',
    workshopSharedModeActive:() => true, workshopLoadPlans:() => [],
    workshopVehicleIdentitySummaryHtml:v => `<strong>${escapeHtml(v.stock)}</strong>`,
    workshopQueueVehicleDescription:() => 'HiAce', vehicleCustomerName:() => 'Fixture customer',
    workshopVehicle:() => ({stock:'U158197'}),
    workshopRequiredJobsForStageHtml:() => '<div>Required work</div>',
    workshopStageJobLines:() => [], parseIsoTimestamp:() => null,
    pmbStageLabel:v => v, workshopExactDurationHours:v => Number(v),
    workshopAssigneeOptions:() => '<option value="">Select technician</option>',
    workshopBayMechanic:() => '', pmbBayMechanic:() => '',
    ...overrides,
  };
  vm.createContext(context);
  for (const name of ['workshopQueueCardHtml', 'workshopStationSelectionHtml']) vm.runInContext(functionSource(name), context);
  return {context,state};
}
const buttons = html => [...html.matchAll(/<button\b[^>]*data-bus-workflow-open="([^"]*)"[^>]*>[\s\S]*?<\/button>/g)].map(match => ({id:match[1],html:match[0]}));

test('unallocated Bus4x4 workflow actions use the canonical UUID, never stock or an alias', () => {
  const {context} = fixture();
  const vehicle = {stock:'U158197', sharedVehicleId:UUID};
  assert.deepEqual(buttons(context.workshopQueueCardHtml(vehicle, 'BUS_4X4')), [{id:UUID,html:`<button class="workshop-schedule-button" type="button" data-bus-workflow-open="${UUID}">Workshop flow / parts readiness</button>`}]);
  for (const id of ['', undefined, 'U158197', 'J138000814', 'not-a-uuid', `${UUID}" onclick="bad()`]) {
    assert.equal(buttons(context.workshopQueueCardHtml({...vehicle, sharedVehicleId:id}, 'BUS_4X4')).length, 0);
  }
  assert.equal(vehicle.sharedVehicleId, UUID);
});

test('other station surfaces retain scheduling controls without exposing the Bus4x4 workflow action', () => {
  const {context} = fixture();
  for (const stage of ['FITTING','ELECTRICAL','FABRICATION','TINT','TYRE','HOIST']) {
    const html = context.workshopQueueCardHtml({stock:'139-fixture',sharedVehicleId:UUID}, stage);
    assert.equal(buttons(html).length, 0, stage);
    assert.match(html, /data-workshop-schedule-vehicle="139-fixture"/);
    assert.match(html, /data-workshop-best-slot-stage=/);
  }
  // This asserts station-surface isolation. The server enforces exact Department138 eligibility,
  // including Department139 work manually placed in Bus4x4 and mixed-department vehicles.
});

test('parts readiness remains accessible when scheduling is blocked by authority, hours or ETA', () => {
  const cases = [
    [{}, {scheduleEnabled:false,disabledReason:'bus_parts_readiness_required'}],
    [{workshopSchedulingDuration:() => null}, {scheduleEnabled:true}],
    [{workshopVehicleEtaConstraint:() => ({required:true,ok:false,reason:'missing_eta',location:'IT'})}, {scheduleEnabled:true}],
    [{}, {scheduleEnabled:true,existingBooking:true}],
  ];
  for (const [overrides,outstanding] of cases) {
    const {context} = fixture(overrides);
    const html = context.workshopQueueCardHtml({stock:'U158197',sharedVehicleId:UUID,__workshopOutstanding:outstanding}, 'BUS_4X4');
    assert.match(html, /draggable="false"/);
    assert.match(html, /data-workshop-schedule-vehicle="U158197" disabled/);
    const action = buttons(html);
    assert.equal(action.length, 1);
    assert.equal(action[0].id, UUID);
    assert.doesNotMatch(action[0].html, /\bdisabled\b|aria-disabled/);
  }
});

test('the live compact queue decorator preserves the readiness action and scheduling guards', () => {
  const {compactQueue} = require('./pdc-planner-slim.js');
  const {context} = fixture();
  const html = context.workshopQueueCardHtml({stock:'U158197',sharedVehicleId:UUID,
    __workshopOutstanding:{scheduleEnabled:false,disabledReason:'bus_parts_readiness_required'}}, 'BUS_4X4');
  const compact = compactQueue(html,{stock:'U158197',jc:'J138000814',key:'517',model:'HiAce'});
  assert.equal(buttons(compact)[0]?.id,UUID);
  assert.doesNotMatch(buttons(compact)[0].html,/\bdisabled\b/);
  assert.match(compact,/draggable="false"/);
  assert.match(compact,/data-workshop-schedule-vehicle="U158197" disabled/);
});

test('dedicated booked station details offer the same exact-identity workflow entry point', () => {
  const {context} = fixture();
  const entry = {id:'booking-fixture',vehicleKey:'U158197',sharedVehicleId:UUID,stage:'BUS_4X4',status:'planned',hours:5,bay:3};
  assert.equal(buttons(context.workshopStationSelectionHtml(entry))[0]?.id, UUID);
  for (const status of ['started','stoppage','completed']) {
    assert.equal(buttons(context.workshopStationSelectionHtml({...entry,status}))[0]?.id, UUID);
  }
  for (const stage of ['FITTING','TINT','ELECTRICAL']) assert.equal(buttons(context.workshopStationSelectionHtml({...entry,stage})).length, 0);
  for (const id of [undefined, 'U158197', `${UUID}<script>`]) assert.equal(buttons(context.workshopStationSelectionHtml({...entry,sharedVehicleId:id})).length, 0);
});

test('workflow selection rejects malformed identity and stops the surrounding queue-card action', () => {
  const start = source.indexOf('function bindWorkshopPlanner(root) {');
  const boundary = source.indexOf("  if (root.dataset.workshopIncrementalBound", start);
  assert.ok(start >= 0 && boundary > start);
  const binding = source.slice(start, boundary) + '\n}';
  for (const [id,accepted] of [[UUID,true],['U158197',false],['',false],[`${UUID}"bad`,false]]) {
    let handler, renderCount = 0, scrollCount = 0, prevented = 0, stopped = 0;
    const state = {};
    const root = {
      querySelectorAll:selector => selector === '[data-bus-workflow-open]' ? [{dataset:{busWorkflowOpen:id},addEventListener:(_,fn) => {handler=fn;}}] : [],
      querySelector:() => ({scrollIntoView:() => {scrollCount++;}}),
    };
    const context = {root,workshopState:() => state,renderWorkshopPlanner:() => {renderCount++;},WORKSHOP_UUID_PATTERN:/^[0-9a-f-]{36}$/i};
    vm.createContext(context); vm.runInContext(binding, context); context.bindWorkshopPlanner(root);
    handler({preventDefault:() => {prevented++;},stopPropagation:() => {stopped++;}});
    assert.equal(prevented,1); assert.equal(stopped,1);
    assert.equal(renderCount,Number(accepted)); assert.equal(scrollCount,Number(accepted));
    assert.equal(state.busWorkflowVehicleId,accepted ? id : undefined);
  }
});

test('planner mounts only a current authoritative candidate or booking instead of a stale stored vehicle choice', () => {
  const start = source.indexOf("  const busHost = renderHost.querySelector('[data-bus-workflow-host]');");
  const end = source.indexOf('  updateWorkshopNowLine(renderHost);', start);
  assert.ok(start >= 0 && end > start);
  const integration = source.slice(start,end);
  for (const testCase of [
    {requested:UUID,candidates:[{sharedVehicleId:UUID,stock:'U158197'}],plans:[],expected:UUID},
    {requested:UUID,candidates:[],plans:[{sharedVehicleId:UUID,vehicleKey:'U158197'}],expected:UUID},
    {requested:OTHER_UUID,candidates:[{sharedVehicleId:UUID,stock:'U158197'}],plans:[],expected:''},
  ]) {
    const calls = [];
    const context = {renderHost:{querySelector:() => ({})},window:{PdcBusWorkflow:{mountPlanner:args => calls.push(args)}},
      state:{busWorkflowVehicleId:testCase.requested},selected:null,stageVehicleList:testCase.candidates,
      plans:testCase.plans,displayStockNumber:v => v.stock,stage:'BUS_4X4'};
    vm.createContext(context); vm.runInContext(integration, context);
    assert.equal(calls.length,1); assert.equal(calls[0].vehicleId,testCase.expected);
    assert.equal(calls[0].stageCode,'BUS_4X4');
  }
});

test('workflow module loads before fitter consumers and both lazy planner routes bypass the old cache', () => {
  const html = fs.readFileSync(path.join(__dirname, 'index.html'),'utf8');
  const app = fs.readFileSync(path.join(__dirname, 'app.js'),'utf8');
  const scripts = [...html.matchAll(/<script\b[^>]*src="([^"]+)"/g)].map(match => match[1]);
  const workflow = scripts.findIndex(src => src.startsWith('pdc-bus-workflow.js?'));
  const fitter = scripts.findIndex(src => src.startsWith('pdc-fitters.js?'));
  assert.ok(workflow >= 0 && fitter > workflow);
  assert.equal(scripts.filter(src => src.startsWith('pdc-bus-workflow.js?')).length,1);
  assert.match(html, /pdc-bus-workflow\.css\?v=2026\.09\.21\.01/);
  assert.match(scripts[fitter], /bus-workflow=2026\.09\.21\.01/);
  assert.ok(scripts.some(src => src.startsWith('app.js?') && /[?&](?:amp;)?bus-workflow=2026\.09\.21\.01(?:&|$)/.test(src)));
  const plannerUrls = [...app.matchAll(/loadExternalScript\(`(workshop-planner\.js\?[^`]+)`/g)].map(match => match[1]);
  assert.equal(plannerUrls.length,2);
  for (const url of plannerUrls) assert.match(url, /bus-workflow=2026\.09\.21\.01/);
});

test('Bus4x4 renders all ten physical bays without expanding the productive-work limit', () => {
  const app = fs.readFileSync(path.join(__dirname, 'app.js'),'utf8');
  const body = name => {
    const match = app.match(new RegExp(`const ${name} = \\{([\\s\\S]*?)\\n\\};`));
    assert.ok(match, `${name} configuration missing`);
    return vm.runInNewContext(`({${match[1]}})`);
  };
  const bays = body('PMB_STAGE_BAY_COUNTS'), limits = body('PMB_WIP_LIMITS');
  assert.equal(bays.BUS_4X4,10);
  assert.equal(limits.BUS_4X4,8, 'Buffer and QA bays are not extra simultaneous productive builds');
  assert.deepEqual({...bays,BUS_4X4:undefined},{BUS_4X4:undefined,TINT:2,HOIST:3,FITTING:5,FABRICATION:13,ELECTRICAL:10,TYRE:2,PIT_INSPECTION:1});
});
