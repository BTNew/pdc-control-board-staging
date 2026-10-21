'use strict';
// r456 (F69, Craig 22 Oct, decision 4): the Bus4x4 staff guide matches the live bay rules (r447 bay guide,
// r448 Bay 3, r450 whole job). Docs only; no database change, so no daily database check - this test is the check.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const d=require('./pdc-workshop-departments.js');
const md=fs.readFileSync('docs/bus4x4-user-guide.md','utf8'),html=fs.readFileSync('docs/bus4x4-user-guide.html','utf8');
test('r456: the guide no longer says Bay 3 is HiAce-only; it gives the r448 Coaster rule',()=>{
  for(const s of [md,html]){assert.doesNotMatch(s,/HiAce-only/);assert.match(s,/Bay 3 has a height restriction and takes any vehicle except a Coaster/);}
});
test('r456: the guide bay table matches the planner own-bay rules',()=>{
  assert.deepEqual(d.preferredBays('BUS_MECHANICAL'),[1,2,3,4]);
  assert.deepEqual(d.preferredBays('BUS_ELECTRICAL'),[8,9,10]);
  assert.deepEqual(d.preferredBays('BUS_QA'),[7]);
  for(const s of [md,html]){
    assert.match(s,/Mechanical and Accessories[^\n]*Bus4x4 1, 2, 3, 4/);
    assert.match(s,/Electrical and Accessories[^\n]*Bus4x4 8, 9, 10/);
    assert.match(s,/Overflow \(any Bus4x4 work, no warning\)[^\n]*Bus4x4 5, 6/);
    assert.doesNotMatch(s,/Progression \(physical override bays only\)|Accessory Fitting/);
  }
});
test('r456: the guide describes the r450 whole-job booking',()=>{
  assert.deepEqual(d.allowedBays('BUS_WHOLE_JOB'),[1,2,3,4,5,6,8,9,10]);
  for(const s of [md,html]) assert.match(s,/whole job/i);
  assert.match(html,/pdc-auto-reload\.js\?v=2026\.10\.21\.r441/,'the guide still loads pdc-auto-reload.js first');
});
