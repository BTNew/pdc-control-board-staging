const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = __dirname;
global.parseIsoTimestamp = value => { const date = new Date(value); return Number.isNaN(+date) ? null : date; };
global.cleanNavisionText = value => String(value ?? '').trim();
global.escapeHtml = value => String(value ?? '');
global.normalizePmbStage = value => String(value ?? '').toUpperCase();
const planner = require(path.join(base, 'workshop-planner.js'));
const handover = require(path.join(base, 'pdc-vehicle-handover.js'));
const row = value => ({ value, version: 1 });
const rows = {
  day_start_time: row('07:00'), day_end_time: row('17:00'),
  scheduling_increment_minutes: row(15), default_booking_duration_minutes: row(60),
  working_week: row(['monday','tuesday','wednesday','thursday','friday','saturday']),
  closures: row([]), overtime_windows: row([]), technician_leave: row([]),
  break_windows: row([{scope:'saturday',start:'07:00',end:'08:00'},{scope:'saturday',start:'12:00',end:'17:00'}]),
};
global.window = {
  __workshopReferenceDataService: { getCachedWorkshopConfiguration: () => ({state:'connected_read_only',rows}) },
  PDC_VEHICLE_HANDOVER: handover,
};
planner.workshopSyncConfigFromSharedSettings();
const day = (date,hour,minute=0) => new Date(2026,8,date,hour,minute);
const stamp = value => `${planner.workshopDateKey(value)} ${String(value.getHours()).padStart(2,'0')}:${String(value.getMinutes()).padStart(2,'0')}`;
const start = day(18,16), end = planner.workshopAddWorkMinutes(start, 6*60);
assert.equal(stamp(end),'2026-09-21 08:00');
assert.deepEqual(planner.workshopAvailabilityWindowsForDate(day(19,8)),[{startMinutes:480,endMinutes:720,overtime:false}]);
const booking = {id:'synthetic-booking',vehicleKey:'synthetic-vehicle',stage:'FITTING',bay:1,status:'planned',startAt:start.toISOString(),endAt:end.toISOString(),hours:6};
const segment = planner.workshopEntrySegmentForDate(booking,'2026-09-19',day(18,8));
assert.equal(segment.start,60); assert.equal(segment.end,300);
const result = {
  calendarCorrect: {sixHoursFromFriday16:stamp(end),saturdayAvailable:'08:00–12:00',sundayAvailableMinutes:planner.workshopWorkMinutesBetween(day(20,0),day(21,0))},
  saturdayRenderingFixed: {visibleChipRange:`${7+segment.start/60}:00–${7+segment.end/60}:00`,expected:'08:00–12:00',segment},
};
const busy = [{start_at:day(21,7).toISOString(),end_at:day(21,9).toISOString()}];
assert.equal(handover.fits(day(21,13,59),day(21,15),busy),false);
assert.equal(handover.fits(day(21,14),day(21,15),busy),true);
result.handover = {fourHours59GapRejected:true,fiveHourGapAccepted:true};
global.pmbStageBayCount = () => 2;
const bays = [1,2].map(bay => ({id:`synthetic-bay-${bay}`,code:`FITTING-BAY-0${bay}`,is_active:true}));
window.__workshopReferenceDataService.getCachedWorkshopBays = () => ({state:'connected_read_only',rows:bays});
window.workshopSharedModeEnabled = () => true;
let snapshot = {revision:1,bookings:[],vehicles:[],admin_blocks:[{id:'synthetic-training',version:1,stage_code:'FITTING',bay_number:1,block_type:'training',label:'Training',scheduled_start_at:day(21,7).toISOString(),scheduled_end_at:day(21,17).toISOString(),duration_minutes:600}]};
window.__workshopDataService = {isEnabled:()=>true,getTrustedSnapshot:()=>snapshot};
assert.equal(planner.workshopSharedModeActive(),true);
const best = planner.workshopBestStageSlot('FITTING','2026-09-21',1,planner.workshopLoadPlans());
assert.deepEqual(best,{stage:'FITTING',bay:2,dateKey:'2026-09-21',startMinutes:0});
result.adminBlockAvoided = {bestSlot:best,adminBlock:'Bay 1 training 07:00–17:00',availableAlternative:'Bay 2 07:00',adminBlockCount:snapshot.admin_blocks.length};
snapshot.admin_blocks.push({...snapshot.admin_blocks[0],id:'synthetic-training-2',bay_number:2});
const nextDay=planner.workshopBestStageSlot('FITTING','2026-09-21',1,planner.workshopLoadPlans());
assert.equal(nextDay.dateKey,'2026-09-22');assert.equal(nextDay.startMinutes,0);
assert.match(planner.workshopUnavailableTimeHtml('2026-09-19'),/Closed 7:00 am–8:00 am/);
assert.match(planner.workshopUnavailableTimeHtml('2026-09-19'),/Closed 12:00 pm–5:00 pm/);
const eligibility=require(path.join(base,'workshop-eligibility.js'));
for(const location of ['PMB','YH'])assert.equal(eligibility.scheduleEligibility({current_location:location}).enabled,true);
assert.equal(eligibility.scheduleEligibility({current_location:'IT'}).enabled,false);
assert.equal(eligibility.scheduleEligibility({current_location:'IT',eta_to_kewdale:'2026-09-21'}).earliestDateKey,'2026-09-28');
assert.equal(eligibility.workshopPlannerStageCodes().includes('SUBLET'),false);
fs.writeFileSync(path.join(__dirname,'calendar-results.json'),JSON.stringify(result,null,2));
console.log(result);
