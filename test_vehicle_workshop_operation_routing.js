'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');

assert(app.includes('data-auth-operation-work'), 'email operation cards must expose the Move jobs entry point');
assert(app.includes('openAuthenticatedOperationWorkshop(button.dataset.authOperationWork)'), 'Move jobs must use the Workshop-only canonical opener');
const workshopOpener = app.slice(app.indexOf('function openAuthenticatedOperationWorkshop('), app.indexOf('function closeVehicleModal('));
assert(workshopOpener.includes('vehicleWorkshopDetailCanonicalId(vehicle)'), 'Workshop-only opener must require canonical vehicle identity');
assert(workshopOpener.includes('vehicleWorkshopCanEditLines()'), 'Workshop-only opener must require operator/admin edit authority');
assert(!workshopOpener.includes('vehicleLocationActionAllowed'), 'Workshop-only opener must not weaken or reuse location/lifecycle mutation authority');
assert(workshopOpener.includes("app.vehicleDetailPage = 'work'"), 'Workshop-only opener must open directly on the Work page');
assert(workshopOpener.includes('loadVehicleWorkshopDetail(vehicle, { force: true })'), 'Workshop-only opener must load the canonical Workshop detail');
const dashboardProjection = app.slice(app.indexOf('function ensureDashboardWorkshopProjectionReady('), app.indexOf('function renderActiveView('));
assert(dashboardProjection.indexOf('if (sharedMode) return false') < dashboardProjection.indexOf('initWorkshopSharedServicesIfEnabled()'), 'shared dashboard must fail closed before the forbidden broad Workshop snapshot can initialize');
assert(app.includes('data-vehicle-workshop-line-stage'), 'editable Workshop lines must expose a station selector');
assert(app.includes('moveVehicleWorkshopLineStage(select)'), 'station selector must use the audited line-adjustment save path');
const lineHandleActivation = app.slice(app.indexOf('function activateVehicleWorkshopLineHandle('), app.indexOf('function bindVehicleDetailTabs('));
assert(lineHandleActivation.includes("querySelector?.('[data-vehicle-workshop-line-stage]')"), 'clicking a Workshop job handle must resolve its station selector');
assert(lineHandleActivation.indexOf("querySelector?.('[data-vehicle-workshop-line-stage]')") < lineHandleActivation.indexOf("querySelector?.('[data-vehicle-workshop-schedule-next]')"), 'station reassignment must take priority over planner navigation when a job handle is clicked');
assert(lineHandleActivation.includes('stationSelect.focus()'), 'job-handle activation must focus the visible station selector');
assert(lineHandleActivation.includes('stationSelect.showPicker()'), 'job-handle activation should open the native station picker when supported');
assert(app.includes("handle.addEventListener('click', () => activateVehicleWorkshopLineHandle(handle))"), 'the visible job handle must invoke the station-first activation helper');
const activateVehicleWorkshopLineHandle = Function(
  'openVehicleWorkshopBooking',
  'vehicleWorkshopBookingDateKey',
  'app',
  `${lineHandleActivation}; return activateVehicleWorkshopLineHandle;`
)(() => { throw new Error('planner navigation must not run when a station selector exists'); }, () => '', { vehicleWorkshopDetailCache: new Map() });
let stationFocusCount = 0;
let stationPickerCount = 0;
let plannerFocusCount = 0;
const stationSelect = { focus: () => { stationFocusCount += 1; }, showPicker: () => { stationPickerCount += 1; } };
const scheduleButton = { focus: () => { plannerFocusCount += 1; } };
const line = { querySelector: selector => selector === '[data-vehicle-workshop-line-stage]' ? stationSelect : scheduleButton };
assert.strictEqual(activateVehicleWorkshopLineHandle({ closest: () => line, dataset: {} }), true, 'clicking an editable job handle should activate station reassignment');
assert.strictEqual(stationFocusCount, 1, 'station selector should receive focus exactly once');
assert.strictEqual(stationPickerCount, 1, 'supported native station picker should open exactly once');
assert.strictEqual(plannerFocusCount, 0, 'station activation must not focus or navigate to the planner');
assert(app.includes('sourceWorkshopStage: group.stage'), 'source station must remain available as immutable provenance');
assert(app.includes('relocatedLines.push({ targetStage, line: adjustedLine })'), 'effective station overlays must relocate lines');
assert(app.includes('relocatedLines.forEach(({ targetStage, line }) => groups.get(targetStage).lines.push(line))'), 'relocated lines must enter the target station group');
assert(app.includes("groups.filter(group => group.requirements.some(item => item?.required === true && item?.completed !== true)).map(group => group.stage)"), 'station choices must be limited to outstanding canonical work');
assert(app.includes('const totalHours = lineHours.length ? lineHours.reduce((sum, value) => sum + value, 0)'), 'station chip hours must sum effective line estimates');
assert(app.includes('vehicleWorkshopCompactLinesHtml(group, bookingFallback, vehicle, validStages)'), 'station choices must be passed to every effective line row');
assert(app.includes("station.operations.map(operation => {"), 'source station headings must sum their displayed operation estimates');
assert(app.includes("const totalHoursLabel = totalHours === null ? 'Unknown hours' : `${totalHours.toFixed(2)} h`"), 'source station headings must display the exact estimated-line sum');
assert(css.includes('.vehicle-workshop-line-station select'), 'station selector must have compact responsive styling');
assert(css.includes('.authenticated-email-operations-heading'), 'Move jobs entry point must have responsive styling');

console.log('vehicle workshop operation routing and hour chips verified');
