'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { percentage, allocatedHours, allocatedBaseMinutes, selectEfficiency, requestInput, createController } = require('./pdc-planner-capacity.js');
const { workshopPlannerStageCodes } = require('./workshop-eligibility.js');
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const plan = () => ({ ok:true, can_apply:true, plan_hash:'server-plan-hash', changes:[{ booking_id:'fixture-booking' }], warnings:[], unchanged_count:2 });
function fixture(stage = 'FITTING') {
  const calls = [], timers = new Map();
  const state = { context:{ actor:'operator-a', token:'token-a', role:'operator', stage,
    config:{ projectRef:'cdsmnqxtyyoeoznmbidd', url:'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey:'public-fixture', workshop:{ sharedData:true } },
    service:{ getTrustedSnapshot:() => ({ revision:1 }), getScope:() => ({ stageCode:stage }), getState:() => 'connected_editable' },
  }, reply:plan(), fetch:null };
  const controller = createController({ getContext:() => state.context, uuid:() => '11111111-1111-4111-8111-111111111111',
    setTimeout(fn) { const id = {}; timers.set(id, fn); return id; }, clearTimeout:id => timers.delete(id),
    fetch:async (url, options) => { calls.push({ name:url.split('/').pop(), body:JSON.parse(options.body), options });
      if (state.fetch) return state.fetch(url, options);
      return { ok:true, json:async () => state.reply }; },
  });
  return { state, controller, calls, timers };
}
test('all seven canonical planner routes can load efficiency and preview capacity controls', async () => {
  const stages = workshopPlannerStageCodes();
  assert.equal(stages.length, 7);
  for (const stage of stages) {
    const f = fixture(stage);
    assert.equal(f.controller.canWrite(), true, `${stage} must expose enabled capacity controls`);
    f.state.reply = {ok:true, stage_code:stage, bays:[{bay_number:1, efficiency_percent:100, version:1}]};
    assert.equal((await f.controller.configuration(stage)).stage_code, stage);
    f.state.reply = plan();
    await f.controller.preview({stage});
    await f.controller.preview({stage, bay:1, efficiency:80});
    assert.deepEqual(f.calls.map(call => call.body.p_stage_code), [stage, stage, stage]);
    assert.equal(f.calls[1].body.p_bay_number, null, 'Close gaps uses the whole selected station');
    assert.equal(f.calls[2].body.p_bay_number, 1);
    assert.equal(f.calls[2].body.p_efficiency_percent, 80);
    assert.equal(f.calls.some(call => call.body.p_apply === true), false, 'loading or previewing controls never applies a plan');
  }
  for (const stage of ['PIT_INSPECTION', 'SUBLET']) {
    const f = fixture(stage);
    assert.equal(f.controller.canWrite(), false);
    await assert.rejects(() => f.controller.preview({stage}));
    assert.equal(f.calls.length, 0, 'non-planner stations stay excluded');
  }
});
test('efficiency uses exact source minutes and 100% is normal', () => {
  assert.equal(allocatedHours(4, 100), 4); assert.equal(allocatedHours(4, 80), 5);
  assert.equal(allocatedHours(.17, 100), 10 / 60);
  assert.equal(allocatedHours(1, 75), 80 / 60);
  assert.equal(allocatedBaseMinutes(32.8, 80), 41 / 60, 'manual allocated minutes retain fractional durable labour base');
  assert.equal(allocatedBaseMinutes(32.8, 100), 33 / 60);
  assert.equal(allocatedBaseMinutes(32.8, 50), 66 / 60);
  assert.equal(allocatedBaseMinutes(32.8, null), null);
  assert.equal(allocatedBaseMinutes(1.1, 10), 11 / 60, 'floating-point rounding cannot add an extra allocated minute');
  assert.equal(allocatedBaseMinutes(1.1001, 10), 12 / 60, 'a real fractional remainder still rounds up');
  for (const value of ['', null, undefined, 0, 9, 201, 80.5, 'eighty']) assert.equal(percentage(value), null);
  assert.equal(allocatedHours(4, null), null, 'unknown efficiency cannot masquerade as normal speed');
  assert.throws(() => requestInput({ stage:'SUBLET', bay:1, efficiency:80 }));
});
test('preview never writes and Apply submits only the exact reviewed server hash', async () => {
  const f = fixture();
  await f.controller.preview({ stage:'FITTING', bay:2, efficiency:80 });
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].name, 'replan_workshop_capacity');
  assert.equal(f.calls[0].body.p_apply, false); assert.equal(f.calls[0].body.p_expected_plan_hash, null);
  assert.equal(f.controller.canApply, true);
  await f.controller.apply();
  assert.deepEqual(f.calls[1].body, { p_stage_code:'FITTING', p_bay_number:2, p_efficiency_percent:80,
    p_apply:true, p_expected_plan_hash:'server-plan-hash', p_idempotency_key:'11111111-1111-4111-8111-111111111111' });
  assert.equal(f.controller.canApply, false);
  await assert.rejects(() => f.controller.apply(), /Preview/);
  assert.equal(f.calls.length, 2, 'a second click cannot replay an already consumed preview');
});
test('empty-bay realtime changes supersede old capacity cache without losing newer confirmed settings', () => {
  const before = { efficiency_percent:100, version:3 }, after = { efficiency_percent:80, version:4 };
  assert.equal(selectEfficiency(before, after), 80, 'reference realtime update wins without any booking revision');
  assert.equal(selectEfficiency(after, before), 80, 'newly saved configuration wins while reference refresh is pending');
  assert.equal(selectEfficiency(after, {efficiency_percent:90}), 90, 'current reference is preferred when version is absent');
  assert.equal(selectEfficiency({efficiency_percent:100}, after), 80);
  assert.equal(selectEfficiency(null, after), 80);
  assert.equal(selectEfficiency(after, null), 80);
  assert.equal(selectEfficiency(null, {version:4}), null, 'missing efficiency cannot become 100%');
});
test('Close gaps has no bay/efficiency mutation and concurrent clicks cannot duplicate a request', async () => {
  const f = fixture(), wait = deferred(); f.state.fetch = () => wait.promise;
  const pending = f.controller.preview({ stage:'FITTING' });
  await assert.rejects(() => f.controller.preview({ stage:'FITTING' }), /already running/);
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].body.p_bay_number, null); assert.equal(f.calls[0].body.p_efficiency_percent, null);
  wait.resolve({ ok:true, json:async () => plan() }); await pending;
});
test('readonly, untrusted, different-stage and unauthenticated planners cannot preview or apply', async () => {
  for (const change of [ctx => { ctx.role='viewer'; }, ctx => { ctx.token=''; }, ctx => { ctx.service.getTrustedSnapshot=() => null; },
    ctx => { ctx.service.getState=() => 'reconnecting'; }, ctx => { ctx.service.getScope=() => ({ stageCode:'HOIST' }); }]) {
    const f = fixture(); change(f.state.context);
    assert.equal(f.controller.canWrite(), false);
    await assert.rejects(() => f.controller.preview({ stage:'FITTING' }), /Refresh/);
    await assert.rejects(() => f.controller.apply(), /Preview/);
    assert.equal(f.calls.length, 0);
  }
});
test('actor, token, service and route changes invalidate the preview before any write', async () => {
  for (const change of [ctx => { ctx.actor='operator-b'; }, ctx => { ctx.token='token-b'; },
    ctx => { ctx.service={ ...ctx.service }; }, ctx => { ctx.stage='HOIST'; }]) {
    const f = fixture(); await f.controller.preview({ stage:'FITTING' }); change(f.state.context);
    assert.equal(f.controller.canApply, false); await assert.rejects(() => f.controller.apply(), /Preview/);
    assert.equal(f.calls.length, 1);
  }
});
test('late old-session preview cannot authorize a new operator or repaint success', async () => {
  const f=fixture(), wait=deferred(); f.state.fetch=() => wait.promise;
  const pending=f.controller.preview({stage:'FITTING'}); f.controller.invalidate(); f.state.context.actor='operator-b';
  wait.resolve({ok:true,json:async()=>plan()}); await assert.rejects(()=>pending,/session or planner changed/);
  assert.equal(f.controller.canApply,false); assert.equal(f.controller.busy,false);
});
test('stale or malformed previews cannot be applied, and editing input clears authority', async () => {
  for (const result of [{ ...plan(), plan_hash:'' }, { ...plan(), can_apply:'true' }, { ...plan(), changes:null }]) {
    const f=fixture(); f.state.reply=result; await assert.rejects(()=>f.controller.preview({stage:'FITTING'}),/incomplete/);
    assert.equal(f.controller.canApply,false);
  }
  const f=fixture(); await f.controller.preview({stage:'FITTING'}); f.controller.clearPreview();
  await assert.rejects(()=>f.controller.apply(),/Preview/);
  await f.controller.preview({stage:'FITTING'}); f.state.reply={ok:false,error:'stale_preview'};
  await assert.rejects(()=>f.controller.apply(),/Bookings changed/); assert.equal(f.controller.canApply,false);
});
test('configuration requires confirmed bay percentages and never substitutes 100%', async () => {
  const f=fixture(); f.state.reply={ok:true,stage_code:'FITTING',bays:[{bay_number:1,efficiency_percent:80,version:2}]};
  assert.equal((await f.controller.configuration('FITTING')).bays[0].efficiency_percent,80);
  f.state.reply={ok:true,stage_code:'FITTING',bays:[{bay_number:1}]};
  await assert.rejects(()=>f.controller.configuration('FITTING'),/could not be verified/);
});
test('a blocked preview retains the server reason and cannot authorize Apply', async () => {
  const f = fixture();
  f.state.reply = {ok:true, can_apply:false, error:'protected_booking_conflict', message:'A later job has already started.', changes:[], warnings:[]};
  const result = await f.controller.preview({stage:'FITTING'});
  assert.equal(result.message, 'A later job has already started.');
  assert.equal(f.controller.canApply, false);
  await assert.rejects(() => f.controller.apply(), /Preview/);
  assert.equal(f.calls.length, 1, 'a blocked preview never writes');
});
test('unconfirmed apply is bounded, cannot claim no changes and does not retry', async () => {
  const f=fixture(); await f.controller.preview({stage:'FITTING'}); f.state.fetch=()=>new Promise(()=>{});
  const pending=f.controller.apply(); assert.equal(f.calls.length,2);
  for(const expire of f.timers.values())expire();
  await assert.rejects(()=>pending,/result could not be confirmed.*Refresh/);
  assert.equal(f.calls.length,2); assert.equal(f.controller.canApply,false); assert.equal(f.controller.busy,false);
});

test('empty Close gaps preview cannot submit a no-op but empty-bay efficiency can save', async () => {
  const f=fixture(); f.state.reply={...plan(),changes:[]};
  await f.controller.preview({stage:'FITTING'});
  assert.equal(f.controller.canApply,false);
  await assert.rejects(()=>f.controller.apply(),/Preview/);
  assert.equal(f.calls.length,1);
  await f.controller.preview({stage:'FITTING',bay:2,efficiency:80});
  assert.equal(f.controller.canApply,true);
  await f.controller.apply();
  assert.equal(f.calls[2].body.p_apply,true);
});
