'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const calendar=require(path.resolve(__dirname,'./karratha/calendar.js'));
const options={timezone:'Australia/Perth',working_week:[1,2,3,4,5],day_start:'06:00',day_end:'16:30',break_windows:[],closures:[]};
function fixture(){return {settings:[{key:'calendar',value:options}],
 bays:[{id:'own-bay',stage_code:'FITTING',bay_number:1,display_name:'Bay 01',active:true}],
 technicians:[{id:'own-tech',name:'Fictional technician'}],
 jobs:[{id:'selected-job',selected:true,job_card_number:'Own selected RO'},{id:'review-job',selected:false,job_card_number:'Unselected RO'}],
 vehicles:[{id:'own-vehicle',stock_number:'123456'}],bookings:[]};}
function booking(overrides={}){return {id:'own-booking',operation_id:'own-operation',job_id:'selected-job',vehicle_id:'own-vehicle',
 bay_id:'own-bay',technician_id:'own-tech',stage_code:'FITTING',status:'planned',
 start_at:'2026-10-05T06:00:00+08:00',end_at:'2026-10-05T07:00:00+08:00',
 segments:[{start_at:'2026-10-05T06:00:00+08:00',end_at:'2026-10-05T07:00:00+08:00'}],...overrides};}
const viewer={can_edit:false},scope={stage:'FITTING',date:'2026-10-05',mode:'day'};

test('only selected cards in own station and own active bays render bookings',()=>{
 const data=fixture();data.bookings=[booking(),booking({id:'review-booking',job_id:'review-job'}),booking({id:'other-station-booking',stage_code:'TINT'})];
 const html=calendar.markup(data,scope,viewer);
 assert.equal((html.match(/data-calendar-booking=/g)||[]).length,1);
 assert.match(html,/data-calendar-booking="own-booking"/);
 assert.doesNotMatch(html,/review-booking|other-station-booking|Unselected RO/);
 assert.doesNotMatch(html,/data-calendar-bay=/);
});

test('scope rejects Bus 4x4 and week dates are Monday through Sunday',()=>{
 assert.deepEqual(calendar.days({date:'2026-10-09',mode:'week'}),['2026-10-05','2026-10-06','2026-10-07','2026-10-08','2026-10-09','2026-10-10','2026-10-11']);
 assert.match(calendar.markup(fixture(),{...scope,stage:'BUS_4X4'},viewer),/Choose a Karratha workshop station/);
});

test('booking tiles escape source identifiers and technician names',()=>{
 const data=fixture();data.vehicles[0].stock_number='<img src=x onerror=alert(1)>';data.technicians[0].name='<script>alert(1)</script>';data.bookings=[booking()];
 const html=calendar.markup(data,scope,viewer);
 assert.doesNotMatch(html,/<img|<script/);
 assert.match(html,/&lt;img/);
 assert.match(html,/&lt;script/);
});

test('continuing work uses actual working segments and does not fill closed weekend',()=>{
 const data=fixture();data.bookings=[booking({start_at:'2026-10-09T16:00:00+08:00',end_at:'2026-10-12T07:00:00+08:00',
  segments:[{start_at:'2026-10-09T16:00:00+08:00',end_at:'2026-10-09T16:30:00+08:00'},
            {start_at:'2026-10-12T06:00:00+08:00',end_at:'2026-10-12T07:00:00+08:00'}]})];
 const html=calendar.markup(data,{stage:'FITTING',date:'2026-10-09',mode:'week'},viewer);
 assert.equal((html.match(/data-calendar-booking="own-booking"/g)||[]).length,1);
});

test('one day operation split around lunch renders two real segments',()=>{
 const data=fixture();data.settings[0].value={...options,break_windows:[{start:'12:00',end:'13:00'}]};
 data.bookings=[booking({start_at:'2026-10-05T11:30:00+08:00',end_at:'2026-10-05T13:30:00+08:00',
  segments:[{start_at:'2026-10-05T11:30:00+08:00',end_at:'2026-10-05T12:00:00+08:00'},
            {start_at:'2026-10-05T13:00:00+08:00',end_at:'2026-10-05T13:30:00+08:00'}]})];
 const html=calendar.markup(data,scope,viewer);
 assert.equal((html.match(/data-calendar-booking="own-booking"/g)||[]).length,2);
});
test('Sunday-only working calendar uses ISO seven and shades Monday instead',()=>{
 const sunday={...options,working_week:[7]};
 assert.deepEqual(calendar.closedPeriods('2026-10-11',sunday),[]);
 assert.deepEqual(calendar.closedPeriods('2026-10-12',sunday),[{start:360,end:990,label:'Non-working day'}]);
 const data=fixture();data.settings[0].value=sunday;
 assert.doesNotMatch(calendar.markup(data,{...scope,date:'2026-10-11'},viewer),/calendar-closed/);
 assert.match(calendar.markup(data,{...scope,date:'2026-10-12'},viewer),/calendar-closed/);
});
