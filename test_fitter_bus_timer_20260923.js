'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {timerModel,timerHtml}=require('./pdc-fitters.js');

const started={status:'started',actual_start_at:'2026-09-23T00:00:00Z',timer:{
  elapsed_seconds:3600,history_complete:true,running:true,basis:'department138_bay_working_hours',
  as_of:'2026-09-23T01:00:00Z',next_change_at:'2026-09-23T02:00:00Z',
}};

test('incomplete Department 138 timing is unknown and requires review, never zero or a running clock',()=>{
  for(const status of ['started','stoppage','completed','queued']) {
    const detail={...started,status,timer:{...started.timer,elapsed_seconds:null,history_complete:false,running:false}};
    const model=timerModel(detail,{receivedAt:0,now:20000,frozenSeconds:4500});
    assert.equal(model.seconds,null);
    assert.equal(model.tone,'unconfirmed');
    assert.equal(model.label,'Progress update required');
    const html=timerHtml(detail,{receivedAt:0,now:20000});
    assert.match(html,/--:--:--/);
    assert.match(html,/Timing history is incomplete/);
    assert.doesNotMatch(html,/00:00:00|is-running|Approximate/);
  }
});

test('an incomplete history invalidates frozen time during saves, uncertain outcomes and disconnection',()=>{
  const detail={...started,timer:{...started.timer,elapsed_seconds:null,history_complete:false,running:false}};
  for(const options of [{pendingAction:'stop'},{unconfirmed:true,unconfirmedAction:'complete'},{connected:false}]) {
    const model=timerModel(detail,{...options,frozenSeconds:4500,now:25000});
    assert.equal(model.seconds,null);
    assert.notEqual(model.tone,'running');
  }
});

test('a previously started queued job retains verified work without counting its waiting interval',()=>{
  const queued={...started,status:'queued',timer:{...started.timer,running:false}};
  const model=timerModel(queued,{receivedAt:0,now:86400000});
  assert.equal(model.seconds,3600);
  assert.equal(model.label,'Paused · Unallocated');
  assert.equal(model.tone,'paused');
  assert.equal(timerModel({...queued,actual_start_at:null,timer:{...queued.timer,elapsed_seconds:0}}).label,'Not started');
  assert.equal(timerModel({...queued,timer:{...queued.timer,basis:undefined}}).label,'Not started');
});

test('legacy finite approximate timers and verified active timers keep their existing behavior',()=>{
  const approximate=timerModel({...started,timer:{...started.timer,history_complete:false}},{receivedAt:0,now:10000});
  assert.equal(approximate.seconds,3610);
  assert.match(approximate.hint,/Approximate/);
  assert.equal(timerModel(started,{receivedAt:0,now:10000}).seconds,3610);
});
