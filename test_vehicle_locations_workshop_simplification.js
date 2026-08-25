'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');

const rowStart = app.indexOf('function incomingVehicleDetailRow');
const rowEnd = app.indexOf('\nfunction ', rowStart + 20);
const row = app.slice(rowStart, rowEnd);
assert.match(row, /<b>Stock No\.<\/b><span>\$\{escapeHtml\(stock\)\}<\/span>/);
assert.doesNotMatch(row, /<b>Rego<\/b>/);

const renderStart = planner.indexOf('function renderWorkshopPlanner');
const renderEnd = planner.indexOf('function bindWorkshopPlanner', renderStart);
const render = planner.slice(renderStart, renderEnd);
assert.doesNotMatch(render, /workshop-completed-panel|workshopCompletedCardHtml|Nothing completed on this board date/);
assert.doesNotMatch(render, /<span class="completed">Completed<\/span>/);
assert.match(render, /const activePlans = plans\.filter\(entry => entry\.stage === stage && entry\.status !== 'completed'\)/);
assert.match(render, /const selectedDateBookingCount = todaysPlans\.length/);
assert.match(planner, /entry\.status !== 'completed' && workshopPlanVehicleIdentity\(entry\) === vehicleIdentity/,
  'completed bookings are omitted from planner search');
assert.match(planner, /\.filter\(item => item\.bookings\.length \|\| item\.candidateAvailable\)/,
  'vehicles with only completed history disappear from planner search');
assert.match(css, /grid-template-columns: 222px minmax\(720px, 1fr\);/);

const detailStart = planner.indexOf('function workshopDetailPanelHtml');
const detailEnd = planner.indexOf('\nfunction ', detailStart + 20);
const detail = planner.slice(detailStart, detailEnd);
assert.doesNotMatch(detail, /data-workshop-detail-pin|Pinned|>Pin</);
assert.doesNotMatch(planner, /WORKSHOP_DETAIL_SESSION_KEY|workshopDetailSessionPreference|workshopSaveDetailSessionPreference|detailPinnedOpen/,
  'Pin persistence and state are removed entirely');
assert.doesNotMatch(planner, /function workshopCompletedCardHtml|incrementalCompletedLimit|workshopLoadMore === 'completed'/,
  'Completed planner presentation code is removed');
const bindStart = planner.indexOf('function bindWorkshopPlanner');
const bindEnd = planner.indexOf('function bindWorkshopLane', bindStart);
assert.doesNotMatch(planner.slice(bindStart, bindEnd), /data-workshop-detail-pin/);

const importedStart = planner.indexOf('function workshopImportedJobLines');
const importedEnd = planner.indexOf('function workshopDetectedStageForLine', importedStart);
assert.ok(importedStart >= 0 && importedEnd > importedStart);
const boardVehicle = {
  __emailVehicleServerAuthoritative: true,
  __emailVehicleIdentityConflict: false,
  __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  pdcEmailOperationLines: [
    {operation_line_id: '22222222-2222-4222-8222-222222222222', operation_no: 'OP5', work_key: 'tyre', description: 'TYRE UPGRADE - BFG KO3 AT X 5', estimatedHours: 1.2, job_card_number: 'J139125060'},
  ],
};
const context = {
  workshopSharedModeActive: () => true,
  pdcSheetVehicles: () => [boardVehicle],
  cleanNavisionText: value => String(value || '').trim(),
  vehicleWorkshopStageCode: value => String(value || '').trim().toUpperCase(),
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  WORKSHOP_STAGE_SEQUENCE: ['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE'],
  vehicleJobcardNumber: () => 'J139125060',
  workshopJobLineId: (text, index) => `fallback-${index}-${text}`,
  vehiclePdcJobLines: () => [],
  workshopClampLineHours: value => value,
};
vm.createContext(context);
vm.runInContext(`${planner.slice(importedStart, importedEnd)} this.importLines = workshopImportedJobLines;`, context);
const lines = context.importLines({id: boardVehicle.__emailVehicleId});
assert.strictEqual(lines.length, 1);
assert.strictEqual(lines[0].operationNo, 'OP5');
assert.strictEqual(lines[0].text, 'TYRE UPGRADE - BFG KO3 AT X 5');
assert.strictEqual(lines[0].stage, 'TYRE');
assert.strictEqual(lines[0].hours, 1.2);
assert.strictEqual(lines[0].jobCardNumber, 'J139125060');
assert.strictEqual(lines[0].source, 'authenticated-operation-line');

const modalStart = planner.indexOf('function workshopRequiredJobsForStageHtml');
const modalEnd = planner.indexOf('function openWorkshopVehicleJob', modalStart);
const modal = planner.slice(modalStart, modalEnd);
assert.match(modal, /line\.operationNo/);
assert.match(modal, /line\.text/);
assert.match(modal, /line\.hours/);
assert.match(modal, /line\.jobCardNumber/);

const completeStart = planner.indexOf('async function completeWorkshopPlan');
const completeEnd = planner.indexOf('\nfunction ', completeStart + 20);
const complete = planner.slice(completeStart, completeEnd);
assert.match(complete, /workshopDispatchSharedAction\('completeWork'/);
assert.match(complete, /workKey: entry\.stage/);

console.log('Vehicle Locations stock and simplified Workshop planner operations: PASS');
