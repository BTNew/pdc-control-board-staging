'use strict';

process.env.TZ='Australia/Perth';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createWorkshopDataService}=require('./workshop-data-service.js');
const {createSlotRuntime}=require('./tests/helpers/workshop-slot-runtime.cjs');
const overview=require('./control-board-overview.js');
const fixtures=require('./qa/control-board-fixtures.js');
const stamp=(day,time)=>`${day}T${time}:00+08:00`;
const ms=(day,time)=>Date.parse(stamp(day,time));
const MON='2026-09-21',TUE='2026-09-22';
const calendar={day_start_time:'06:00',day_end_time:'16:30',scheduling_increment_minutes:15,
  working_week:['monday','tuesday','wednesday','thursday','friday'],closures:[],break_windows:[],overtime_windows:[]};

function booking(id,{stage='BUS_4X4',bay=3,status='planned',start=stamp(MON,'07:10'),end=stamp(MON,'10:10'),version=1,busVersion=null,...extra}={}) {
  const vehicle=fixtures.vehicle(id,{department_codes:stage==='BUS_4X4'?['138']:['139'],bus_workflow_department138:stage==='BUS_4X4',vehicle_description:'Synthetic HiAce'});
  const bayId=`${stage}-BAY-${String(bay).padStart(2,'0')}`;
  return {booking_id:fixtures.uuid(id),vehicle_id:vehicle.id,vehicle,stage:{code:stage},stage_code:stage,
    bay:{id:bayId,bay_number:bay},bay_id:bayId,bay_number:bay,status,version,bus_calendar_version:busVersion,
    scheduled_start_at:start,scheduled_end_at:end,default_duration_minutes:180,actual_start_at:null,actual_end_at:null,...extra};
}
function fixture(bookings,calendarOverrides={}) {
  const actualCalendar={...calendar,...calendarOverrides};
  const runtime=createSlotRuntime();
  Object.entries(actualCalendar).forEach(([key,value])=>runtime.config[key]={value,version:1});runtime.planner.workshopSyncConfigFromSharedSettings();
  let current={revision:1,bookings,vehicles:bookings.map(row=>row.vehicle),work_items:[],admin_blocks:[]};
  const calls=[],delivered=[],timers=new Map();let timerId=0;
  const scope={stageCode:'BUS_4X4',dateFrom:MON,dateTo:TUE};
  const service=createWorkshopDataService({config:{workshop:{sharedData:true}},scope,
    getAccessToken:()=> 'synthetic-token',getRole:()=> 'operator',
    client:{readRevision:async(_token,readScope)=>{calls.push({name:'revision',scope:readScope});return {ok:true,body:[{revision:current.revision}]};},
      rpc:async(_token,name,payload)=>{calls.push({name,payload});assert.equal(name,'get_station_workshop_snapshot','read-only fixture must never mutate');return {ok:true,body:current};}},
    scheduleTimeout:(fn,delay)=>{const id=++timerId;timers.set(id,{fn,delay});return id;},clearScheduledTimeout:id=>timers.delete(id),
    onSnapshot:value=>delivered.push(value)});
  runtime.context.window.__workshopDataService=service;
  const overviewSnapshot=snapshot=>({generated_at:stamp(MON,'09:01'),stages:[{code:'BUS_4X4',revision:snapshot.revision}],
    candidates:[],board:{calendar:actualCalendar,bays:[...new Map(snapshot.bookings.map(row=>[row.bay_id,{bay_id:row.bay_id,stage_code:row.stage_code,bay_number:row.bay_number,is_active:true}])).values()],
      bookings:snapshot.bookings,admin_blocks:[]}});
  const render=(id,dates=[MON,TUE],now=stamp(MON,'09:01'))=>{
    const snapshot=service.getTrustedSnapshot();assert.ok(snapshot,'geometry requires an authoritative snapshot');
    const entry=runtime.planner.workshopLoadPlans().find(row=>row.id===fixtures.uuid(id));assert.ok(entry);
    const model=overview.buildModel(overviewSnapshot(snapshot));
    const timeline=overview.buildTimeline(model,{startDate:dates[0],dayCount:Math.round((Date.parse(dates.at(-1))-Date.parse(dates[0]))/86400000)+1,now:new Date(now)});
    const pieces=timeline.rows.flatMap(row=>row.segments).filter(piece=>piece.item.id===entry.id);
    const station=dates.map(date=>({date,segment:runtime.planner.workshopEntrySegmentForDate(entry,date,new Date(now))}));
    return {entry,model,timeline,pieces,station};
  };
  return {runtime,service,calls,delivered,render,current:()=>current,setSnapshot:next=>current=next,
    reads:()=>calls.filter(call=>call.name==='get_station_workshop_snapshot').length};
}
function assertDayBounds(result,date,start,end) {
  const segment=result.station.find(row=>row.date===date).segment;
  const pieces=result.pieces.filter(piece=>piece.date===date);
  if(!start){assert.equal(segment,null);assert.equal(pieces.length,0);return;}
  assert.ok(segment,`${date}: station segment missing`);assert.ok(pieces.length,`${date}: overview segment missing`);
  assert.equal(ms(date,'06:00')+segment.start*60000,ms(date,start),`${date}: station start`);
  assert.equal(ms(date,'06:00')+segment.end*60000,ms(date,end),`${date}: station end`);
  assert.equal(Math.min(...pieces.map(piece=>piece.start)),ms(date,start),`${date}: overview start`);
  assert.equal(Math.max(...pieces.map(piece=>piece.end)),ms(date,end),`${date}: overview end`);
}

test('changed station revision rolls a planned DTO from07:10 to saved09:15 in both views without a browser-only cascade',async()=>{
  const source=booking(1),f=fixture([source]);await f.service.loadSnapshot('initial');
  const firstRows=f.runtime.planner.workshopLoadPlans(),before=JSON.stringify(f.current());
  assertDayBounds(f.render(1),MON,'07:10','10:10');
  assertDayBounds(f.render(1,[MON,TUE],stamp(MON,'09:08')),MON,'07:10','10:10');
  assert.equal(f.reads(),1);assert.equal(JSON.stringify(f.current()),before,'Now must not rewrite source positions');
  const moved={...source,version:2,bus_calendar_version:1,scheduled_start_at:stamp(MON,'09:15'),scheduled_end_at:stamp(MON,'12:15')};
  f.setSnapshot({...f.current(),revision:2,bookings:[moved]});
  await f.service.reconcileRevision('minute_clock');
  const result=f.render(1);assertDayBounds(result,MON,'09:15','12:15');assertDayBounds(result,TUE,null);
  assert.equal(result.entry.busCalendarVersion,1);assert.equal(result.entry.sharedVersion,2);assert.equal(result.entry.status,'planned');assert.equal(result.entry.actualStartAt,'');
  assert.notEqual(f.runtime.planner.workshopLoadPlans(),firstRows,'saved revision replaces the mapped-row cache');
  assert.equal(f.reads(),2);assert.deepEqual(f.delivered.map(row=>row.revision),[1,2]);
  assert.deepEqual(f.calls.filter(call=>call.name.includes('snapshot')).map(call=>call.payload),[
    {p_stage_code:'BUS_4X4',p_date_from:MON,p_date_to:TUE},{p_stage_code:'BUS_4X4',p_date_from:MON,p_date_to:TUE}]);
  const mapped=f.runtime.planner.workshopLoadPlans();
  for(let i=0;i<4;i++)await f.service.reconcileRevision('unchanged_minute');
  assert.equal(f.reads(),2);assert.equal(f.delivered.length,2);assert.equal(f.runtime.planner.workshopLoadPlans(),mapped);
  assert.deepEqual(source,JSON.parse(before).bookings[0],'old DTO was not modified by either view');
});

test('roll-forward snapshot moves its planned queue while live, stoppage and completed records retain source state',async()=>{
  const overdue=booking(1),live=booking(2,{bay:1,status:'started',start:stamp(MON,'06:00'),end:stamp(MON,'10:00'),actual_start_at:stamp(MON,'06:05')}),
    stopped=booking(3,{bay:2,status:'stoppage',start:stamp(MON,'06:00'),end:stamp(MON,'10:00'),stoppage_started_at:stamp(MON,'08:00'),stoppage_reason:'Awaiting part'}),
    completed=booking(4,{bay:4,status:'completed',start:stamp(MON,'06:00'),end:stamp(MON,'07:00'),actual_start_at:stamp(MON,'06:05'),actual_end_at:stamp(MON,'06:50')});
  const f=fixture([overdue,live,stopped,completed]);await f.service.loadSnapshot('initial');
  const saved={...f.current(),revision:2,bookings:[{...overdue,version:2,bus_calendar_version:1,scheduled_start_at:stamp(MON,'09:15'),scheduled_end_at:stamp(MON,'12:15')},live,stopped,completed]};
  const before=JSON.stringify(saved);f.setSnapshot(saved);await f.service.reconcileRevision('minute_clock');
  assertDayBounds(f.render(1),MON,'09:15','12:15');assertDayBounds(f.render(2),MON,'06:00','10:00');assertDayBounds(f.render(3),MON,'06:00','10:00');
  const rows=f.runtime.planner.workshopLoadPlans();
  for(const source of [live,stopped,completed]){
    const mapped=rows.find(row=>row.id===source.booking_id);assert.equal(mapped.status,source.status);
    assert.equal(mapped.startAt,source.scheduled_start_at);assert.equal(mapped.endAt,source.scheduled_end_at);assert.equal(mapped.sharedVersion,1);
  }
  assert.equal(f.render(1).model.totalBookings,3,'completed history stays out of active overview');
  assert.equal(JSON.stringify(saved),before,'neither rendering nor mapping may mutate any recorded state');
});

for(const [bay,close,start] of [[3,'15:00','14:00'],[8,'14:00','13:00'],[9,'14:00','13:00']]) {
  test(`Bus bay${bay} null→1 calendar migration renders the saved continuation only inside its scoped shift`,async()=>{
    const source=booking(1,{bay,start:stamp(MON,start),end:stamp(TUE,'07:00'),default_duration_minutes:120});
    const f=fixture([source]);await f.service.loadSnapshot('initial');
    assert.equal(f.render(1).entry.busCalendarVersion,null);
    // Legacy records retain their recorded display envelope until migrated.
    assertDayBounds(f.render(1),MON,start,'16:30');
    const migrated={...source,version:2,bus_calendar_version:1};f.setSnapshot({...f.current(),revision:2,bookings:[migrated]});
    await f.service.reconcileRevision('clock_calendar_migration');
    const result=f.render(1);assertDayBounds(result,MON,start,close);assertDayBounds(result,TUE,'06:00','07:00');
    assert.equal(result.entry.endAt,source.scheduled_end_at);assert.equal(result.entry.busCalendarVersion,1);
    assert.equal(f.runtime.planner.workshopWorkMinutesBetween(new Date(source.scheduled_start_at),new Date(source.scheduled_end_at),result.entry),120);
  });
}

test('nonBus jobs keep global hours when a saved Bus roll-forward snapshot arrives',async()=>{
  const source=booking(1,{stage:'FITTING',bay:1,start:stamp(MON,'14:00'),end:stamp(MON,'16:00'),default_duration_minutes:120}),f=fixture([source]);
  await f.service.loadSnapshot('initial');const result=f.render(1);assertDayBounds(result,MON,'14:00','16:00');assertDayBounds(result,TUE,null);
  assert.equal(f.runtime.planner.workshopBusShift(result.entry),null);
});

test('migrated Bus live overrun stops at its shift end and stoppage continuation resumes next opening',async()=>{
  for(const [bay,close] of [[3,'15:00'],[8,'14:00']]){
    const live=booking(1,{bay,status:'started',busVersion:1,start:stamp(MON,'06:00'),end:stamp(MON,'08:00'),actual_start_at:stamp(MON,'06:00')}),
      stopped=booking(2,{bay,status:'stoppage',busVersion:1,start:stamp(MON,'06:00'),end:stamp(MON,'08:00'),stoppage_started_at:stamp(MON,close)});
    const f=fixture([live,stopped]);await f.service.loadSnapshot('initial');
    assertDayBounds(f.render(1,[MON,TUE],stamp(MON,'16:20')),MON,'06:00',close);
    assertDayBounds(f.render(1,[MON,TUE],stamp(MON,'16:20')),TUE,null);
    assertDayBounds(f.render(2,[MON,TUE],stamp(MON,'16:20')),MON,'06:00',close);
    assertDayBounds(f.render(2,[MON,TUE],stamp(MON,'16:20')),TUE,'06:00','06:15');
    assert.equal(f.runtime.planner.workshopEntryEnd(f.render(1).entry).toISOString(),new Date(live.scheduled_end_at).toISOString(),'display projection retains planned end');
  }
});

test('migrated Bus continuation excludes weekends and overtime without changing the shared axis or other stations',async()=>{
  const friday='2026-09-25',saturday='2026-09-26',sunday='2026-09-27',monday='2026-09-28';
  const bus=booking(1,{bay:8,busVersion:1,start:stamp(friday,'13:00'),end:stamp(monday,'07:00'),default_duration_minutes:120}),
    other=booking(2,{stage:'FITTING',bay:1,start:stamp(saturday,'14:00'),end:stamp(saturday,'16:00')});
  const f=fixture([bus,other],{working_week:[...calendar.working_week,'saturday'],overtime_windows:[{scope:'global',start:'16:30',end:'18:00'}]});
  await f.service.loadSnapshot('initial');const dates=[friday,saturday,sunday,monday],result=f.render(1,dates,stamp(friday,'09:01'));
  assertDayBounds(result,friday,'13:00','14:00');assertDayBounds(result,saturday,null);assertDayBounds(result,sunday,null);assertDayBounds(result,monday,'06:00','07:00');
  assert.equal(result.timeline.axisStart,360);assert.equal(result.timeline.axisEnd,1080,'shared timeline continues to cover global overtime');
  assertDayBounds(f.render(2,dates,stamp(friday,'09:01')),saturday,'14:00','16:00');
  assert.ok(f.runtime.planner.workshopAvailabilityWindowsForDate(new Date(stamp(saturday,'16:30'))).some(window=>window.endMinutes===1080),'nonBus overtime configuration is retained');
});

test('scoped Bus windows retain workshop breaks in both views after a clock revision',async()=>{
  const source=booking(1,{bay:3,busVersion:1,start:stamp(MON,'11:30'),end:stamp(MON,'13:00'),default_duration_minutes:60});
  const f=fixture([source],{break_windows:[{scope:'global',start:'12:00',end:'12:30'}]});await f.service.loadSnapshot('initial');
  const result=f.render(1);assertDayBounds(result,MON,'11:30','13:00');
  assert.deepEqual(result.pieces.map(piece=>[piece.start,piece.end]),[[ms(MON,'11:30'),ms(MON,'12:00')],[ms(MON,'12:30'),ms(MON,'13:00')]]);
  assert.equal(f.runtime.planner.workshopWorkMinutesBetween(new Date(source.scheduled_start_at),new Date(source.scheduled_end_at),result.entry),60);
});
