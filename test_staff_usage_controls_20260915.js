'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { sortUsageUsers, filterUsageUsers, usagePresence } = require('./pdc-staff-usage.js');

const now = Date.parse('2026-09-15T05:00:00Z');
const iso = offset => new Date(now + offset).toISOString();
const report = { generated_at: iso(0), active_window_seconds: 120 };
const people = [
  { user_id:'quiet', name:'Alex', email:'alex@example.invalid', last_active_at:null, last_sign_in_at:null, sign_ins:0, active_days:0, page_visits:0, clicks:0, active_now:false },
  { user_id:'frequent', name:'Zoe', email:'zoe@example.invalid', last_active_at:iso(-60000), last_sign_in_at:iso(-7200000), sign_ins:12, active_days:10, page_visits:100, clicks:205, active_now:true, presence_last_active_at:iso(-60000) },
  { user_id:'recent', name:'Ben', email:'ben@example.invalid', last_active_at:iso(-1000), last_sign_in_at:iso(-3600000), sign_ins:2, active_days:2, page_visits:9, clicks:30, active_now:false },
  { user_id:'historic', name:'Casey', email:'casey@example.invalid', last_active_at:iso(-1000000000), last_sign_in_at:iso(-1000000000), sign_ins:0, active_days:0, page_visits:0, clicks:0, active_now:false }
];
const ids = rows => rows.map(x => x.user_id);

test('Most recent activity is first and never-recorded dates stay last', () => {
  assert.deepEqual(ids(sortUsageUsers(people,'last_active_at','desc')), ['recent','frequent','historic','quiet']);
  assert.deepEqual(ids(sortUsageUsers(people,'last_active_at','asc')), ['historic','frequent','recent','quiet']);
});
test('Last sign-in sorts independently from activity', () => {
  assert.deepEqual(ids(sortUsageUsers(people,'last_sign_in_at','desc')), ['recent','frequent','historic','quiet']);
});
for (const metric of ['sign_ins','active_days','page_visits','clicks']) {
  test(metric+' sorts numerically in both directions', () => {
    const rows = [{name:'Ten',[metric]:'10'},{name:'Two',[metric]:'2'},{name:'Zero',[metric]:0}];
    assert.deepEqual(sortUsageUsers(rows,metric,'desc').map(x=>x.name),['Ten','Two','Zero']);
    assert.deepEqual(sortUsageUsers(rows,metric,'asc').map(x=>x.name),['Zero','Two','Ten']);
  });
}
test('Name sorting and equal-metric tie order are predictable', () => {
  assert.deepEqual(sortUsageUsers(people,'name','asc').map(x=>x.name), ['Alex','Ben','Casey','Zoe']);
  const rows=[{name:'Sam',email:'b@example.invalid',clicks:1},{name:'Sam',email:'a@example.invalid',clicks:1}];
  assert.deepEqual(sortUsageUsers(rows,'clicks','desc').map(x=>x.email),['a@example.invalid','b@example.invalid']);
});
test('Sorting and filtering leave the cached report untouched', () => {
  const rows = people.map(x=>Object.freeze({...x})); Object.freeze(rows);
  const original=JSON.stringify(rows);
  sortUsageUsers(rows,'clicks','desc');
  filterUsageUsers(rows,{query:'alex',activity:'all'},report,now);
  assert.equal(JSON.stringify(rows),original);
});
test('Staff search matches name or email without case sensitivity', () => {
  assert.deepEqual(ids(filterUsageUsers(people,{query:'ZOE@EXAMPLE',activity:'all'},report,now)),['frequent']);
  assert.deepEqual(ids(filterUsageUsers(people,{query:'  ben  ',activity:'all'},report,now)),['recent']);
});
test('Period filters use the selected-period totals rather than lifetime dates', () => {
  assert.deepEqual(ids(filterUsageUsers(people,{query:'',activity:'used'},report,now)),['frequent','recent']);
  assert.deepEqual(ids(filterUsageUsers(people,{query:'',activity:'unused'},report,now)),['quiet','historic']);
});
test('Any selected-period usage metric qualifies as used', () => {
  for(const field of ['sign_ins','active_days','page_visits','clicks']) {
    const row={name:field,[field]:1};
    assert.equal(filterUsageUsers([row],{activity:'used'},report,now).length,1);
  }
});
test('Active filter combines with staff search', () => {
  assert.deepEqual(ids(filterUsageUsers(people,{query:'zoe',activity:'active'},report,now)),['frequent']);
  assert.equal(filterUsageUsers(people,{query:'ben',activity:'active'},report,now).length,0);
});
test('Green requires an explicitly valid session with recent activity', () => {
  assert.equal(usagePresence(people[1],report,now),'active');
  assert.equal(usagePresence(people[2],report,now),'inactive');
  assert.equal(usagePresence({...people[1],active_now:false},report,now),'inactive');
  assert.equal(usagePresence({last_active_at:iso(0),last_sign_in_at:iso(0)},report,now),'unknown');
});
test('Presence expires without counting idle time as activity', () => {
  const user={...people[1],presence_last_active_at:iso(-119000)};
  assert.equal(usagePresence(user,report,now),'active');
  assert.notEqual(usagePresence(user,report,now+2000),'active');
});
test('Stale report never leaves a green indicator displayed', () => {
  assert.equal(usagePresence({...people[1],presence_last_active_at:iso(0)},report,now+61000),'unknown');
  assert.equal(filterUsageUsers(people,{activity:'active'},report,now+61000).length,0);
});
test('Missing, malformed or future presence evidence cannot show active', () => {
  assert.notEqual(usagePresence({...people[1],presence_last_active_at:null},report,now),'active');
  assert.notEqual(usagePresence({...people[1],presence_last_active_at:'bad date'},report,now),'active');
  assert.notEqual(usagePresence({...people[1],presence_last_active_at:iso(60000)},report,now),'active');
  assert.equal(usagePresence(people[1],{generated_at:'bad date'},now),'unknown');
});
test('Invalid last-activity dates sort last rather than before real dates', () => {
  const rows=[{name:'Unknown',last_active_at:'bad date'},{name:'Known',last_active_at:iso(-2000)}];
  assert.equal(sortUsageUsers(rows,'last_active_at','asc')[0].name,'Known');
});

