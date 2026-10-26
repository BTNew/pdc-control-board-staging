/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r450 (F63, Craig 21 Oct, Option A): a controller can book a whole job - every unbooked Dept 138
// Bus 4x4 line of a vehicle, across categories - to one technician as ONE booking
// (work category BUS_WHOLE_JOB), so that technician's job card lists every line.
// Mirrors pdc_work_categories_private.allowed_bay / whole_job_lines_450 (check bus_whole_job_450).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const departments=require('./pdc-workshop-departments.js');
const slice=(file,from,to)=>{const s=fs.readFileSync(file,'utf8');const a=s.indexOf(from),b=s.indexOf(to,a+1);assert.ok(a>=0&&b>a,from);return s.slice(a,b);};
const row=(work_category,estimated_hours,extra={})=>({work_category,estimated_hours,completed:false,existing_booking:false,schedule_enabled:estimated_hours>0,...extra});

test('whole job: label, bays (any Bus bay except QA Bay 7) and station',()=>{
  assert.equal(departments.WHOLE_JOB.code,'BUS_WHOLE_JOB');
  assert.equal(departments.categoryLabel('BUS_WHOLE_JOB'),'Whole job');
  assert.deepEqual(departments.allowedBays('BUS_WHOLE_JOB'),[1,2,3,4,5,6,8,9,10]);
  assert.deepEqual(departments.preferredBays('BUS_WHOLE_JOB'),[1,2,3,4,5,6,8,9,10]);
  assert.equal(departments.categoryStage('BUS_WHOLE_JOB'),'BUS_4X4');
  assert.ok(departments.isWholeJob('BUS_WHOLE_JOB')&&!departments.isWholeJob('BUS_QA'));
});

test('it is not a line category: never in the category list, views or splits',()=>{
  assert.ok(!departments.categoryChoices('138').includes('BUS_WHOLE_JOB'));
  assert.equal(departments.category('BUS_WHOLE_JOB'),null);
  assert.ok(!departments.BUS_WORK.some(item=>item.code==='BUS_WHOLE_JOB'));
  const groups=departments.splitGroups([{stage:'BUS_4X4',lines:[{work_category:'BUS_MECHANICAL'},{work_category:'BUS_ELECTRICAL'}],
    bookings:[{work_category:'BUS_WHOLE_JOB',id:'w'},{work_category:'BUS_QA',id:'q'}]}]);
  assert.deepEqual(groups.map(g=>g.category),['BUS_MECHANICAL','BUS_ELECTRICAL']);
  for(const g of groups) assert.deepEqual(g.bookings.map(b=>b.id),['w'],'the whole-job booking shows with each category it holds');
});

test('the whole job is offered only with 2+ unbooked categories that all have hours',()=>{
  const offer=departments.wholeJobChoice([row('BUS_MECHANICAL',40),row('BUS_ELECTRICAL',5.5),row('BUS_QA',0.01),
    row('BUS_ACCESSORIES',3,{existing_booking:true}),row('BUS_PIT',1)]);
  assert.deepEqual(offer.categories,['BUS_MECHANICAL','BUS_ELECTRICAL','BUS_QA']);
  assert.equal(Math.round(offer.hours*100),4551,'original line hours, summed');
  assert.equal(departments.wholeJobChoice([row('BUS_MECHANICAL',40),row('BUS_ELECTRICAL',5,{completed:true})]),null,'one category left: book it by category');
  assert.equal(departments.wholeJobChoice([row('BUS_MECHANICAL',40),row('BUS_ELECTRICAL',null)]),null,'hours missing');
  assert.equal(departments.wholeJobChoice(undefined),null);
});

test('planner: a whole-job booking shows by bay in a category view and keeps its category on drop',()=>{
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  assert.match(planner,/const bayCategory = candidate\.workCategory === 'BUS_WHOLE_JOB' \? null : workshopBayAwareCategory\(/);
  assert.equal((planner.match(/entry\.workCategory && entry\.workCategory !== 'BUS_WHOLE_JOB' \? entry\.workCategory [!=]== workshopSelectedBusGroup\(\)\.code/g)||[]).length,3);
  assert.doesNotMatch(planner,/entry\.workCategory \? entry\.workCategory [!=]== workshopSelectedBusGroup/);
  // r540 (F154): the centred job modal had the second copy of this filter. The planner queue keeps the one that remains.
  assert.equal((planner.match(/!entry\.workCategory \|\| entry\.workCategory === 'BUS_WHOLE_JOB' \|\| entry\.workCategory === /g)||[]).length,1);
  // the vehicle panel lists every Bus line for a whole job
  const c={workshopResolvedJobLines:()=>[{stage:'BUS_4X4',workCategory:'BUS_QA'},{stage:'BUS_4X4',workCategory:'BUS_MECHANICAL'},{stage:'FITTING',workCategory:'FITTING'}],
    normalizePmbStage:s=>s};vm.createContext(c);
  vm.runInContext(slice('workshop-planner.js','function workshopStageJobLines(','\n}\n')+'\n}',c);
  assert.equal(c.workshopStageJobLines({},'BUS_4X4','BUS_WHOLE_JOB').length,2);
  assert.equal(c.workshopStageJobLines({},'BUS_4X4','BUS_QA').length,1);
});

test('planner: the Schedule window offers "Whole job to one technician" and sends BUS_WHOLE_JOB',()=>{
  const modal=slice('workshop-planner.js','function openWorkshopScheduleModal(','async function extendWorkshopPlan(');
  assert.match(modal,/wholeJobChoice\?\.\(vehicle\.__workshopOutstanding\?\.workCategories\)/);
  assert.match(modal,/Whole job to one technician – /);
  assert.match(modal,/Book QA separately first if someone else does QA/);
  assert.match(modal,/workCategoryValue: workCategory, baseHoursValue: wholeJob\.hours/);
  assert.match(modal,/const workBays = workshopCategoryBays\(normalizedStage, workCategory\)/);
  const schedule=slice('workshop-planner.js','async function scheduleWorkshopVehicle(','\n}\n');
  assert.match(schedule,/workCategoryValue = '', baseHoursValue = 0/);
  assert.match(schedule,/const duration = wholeJobRequested \? \{ hours: Number\(baseHoursValue\) \}/);
  assert.match(schedule,/workCategory: existing\?\.workCategory \|\| \(wholeJobRequested \? workCategoryValue : ''\)/);
});

test('migration, undo and rolled-back test are in the repo and consistent',()=>{
  const mig=fs.readdirSync('supabase/migrations').find(f=>/_r450_whole_job_booking\.sql$/.test(f));
  assert.ok(mig,'r450 migration');
  const up=fs.readFileSync('supabase/migrations/'+mig,'utf8'),down=fs.readFileSync('supabase/rollbacks/'+mig.replace('.sql','.down.sql'),'utf8');
  assert.match(up,/SET LOCAL lock_timeout = '2s'/);assert.match(up,/NOT BETWEEN 2 AND 45/);
  assert.match(up,/'bus_whole_job_450','F63'/);assert.match(up,/,true,249,'r450'\)/);
  assert.match(up,/OR \(category='BUS_WHOLE_JOB' AND bay IN \(1,2,3,4,5,6,8,9,10\)\)/);
  assert.match(up,/'BUS_QA'::text, 'BUS_WHOLE_JOB'::text/);
  assert.match(up,/AND b\.work_category<>'BUS_WHOLE_JOB'/,'a whole job never becomes a line category');
  assert.match(up,/expected 168 pins/);assert.match(up,/expected_function_md5\)<>178/);
  assert.doesNotMatch(up,/workshop_clock_tick\(boolean,timestamptz\) /);
  assert.match(down,/whole-job booking\(s\) exist/);assert.match(down,/expected_function_md5\)<>168/);
  assert.match(down,/DROP FUNCTION pdc_work_categories_private\.whole_job_lines_450\(uuid,uuid\);/);
  const rb=fs.readFileSync('tests/whole_job_booking_450_rollback.sql','utf8');
  assert.match(rb,/R450_RB_RESULT/);assert.match(rb,/ROLLBACK;\s*$/);assert.doesNotMatch(rb,/@[A-Za-z0-9._%+-]+\.(com|au)/);
  assert.doesNotMatch(rb,/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/,'no fixed IDs');
});
