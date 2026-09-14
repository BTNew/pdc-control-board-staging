'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {approveReadyQueue} = require('./pdc-new-vehicles.js');

function vehicle(id, fields = {}) {
  return {
    vehicle_id:id, stock_number:`STOCK-${id}`, status:'pending', snapshot_hash:`snapshot-${id}`,
    current_location:'PMB', lifecycle_state:'active', visible_on_board:false,
    customer_name:'Workshop customer', job_cards:[`JC-${id}`],
    operations:[{
      line_identity:`source:${id}-fit`, source_line_id:`${id}-fit`, source_kind:'authenticated',
      description:'Fit supplied accessory', stage_code:'FITTING', active:true, completed:false,
      estimated_hours:1.25, source_estimated_hours:1.25, hours_provenance:'source_explicit',
      source_contract:'pilbara_service_open_jobcards_v1',
    }],
    ...fields,
  };
}
function receipt(row) {
  return {ok:true, data:{vehicle_id:row.vehicle_id, visible_on_board:true, bookings_created:0,
    operations:row.operations.map(line => ({...line}))}};
}
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
}
const ids = rows => rows.map(row => row.vehicle_id);
function fixture(rows) {
  const state = {serverRows:[...rows], pages:[], attempts:[], accepted:[], progress:[], current:true, stop:false};
  const options = {
    async listPage(offset, limit) {
      state.pages.push({offset, limit, approvalsSoFar:state.attempts.length});
      return {ok:true, data:{items:state.serverRows.slice(offset, offset + limit), total:state.serverRows.length,
        offset, has_more:offset + limit < state.serverRows.length}};
    },
    async approveRow(row) { state.attempts.push(row); return receipt(row); },
    isCurrent:() => state.current,
    shouldStop:() => state.stop,
    onProgress:value => state.progress.push(structuredClone(value)),
    onApproved:row => state.accepted.push(row),
  };
  return {state, options, run:() => approveReadyQueue(options)};
}

test('bulk approval gathers the whole queue before writes can shift later pages', async () => {
  const rows = Array.from({length:123}, (_, index) => vehicle(`vehicle-${index + 1}`));
  const f = fixture(rows);
  f.options.approveRow = async row => {
    f.state.attempts.push(row);
    // The real approval removes this row from the server's pending list.
    f.state.serverRows = f.state.serverRows.filter(item => item.vehicle_id !== row.vehicle_id);
    return receipt(row);
  };
  const result = await f.run();
  assert.deepEqual(f.state.pages, [0,50,100].map(offset => ({offset,limit:50,approvalsSoFar:0})));
  assert.deepEqual(ids(f.state.attempts), ids(rows), 'no skipped or duplicated vehicle after the pending queue shrinks');
  assert.deepEqual(ids(result.approved), ids(rows));
  assert.deepEqual(ids(f.state.accepted), ids(rows));
  assert.equal(result.checked,123); assert.equal(result.total,123);
  assert.equal(result.ready,123); assert.equal(result.needsReview,0);
  assert.deepEqual(result.failed,[]); assert.equal(result.stopped,false);
  assert.ok(f.state.progress.length > 0, 'the caller can show progress during a long run');
});

test('mixed queue leaves missing hours, mapping, identity and AI estimates for review while accepting Sublet zero', async () => {
  const supplied = vehicle('tune-hours');
  const missing = vehicle('missing-hours'); missing.operations[0].estimated_hours = 0;
  const unmapped = vehicle('unmapped'); unmapped.operations[0].stage_code = 'UNALLOCATED_MAPPING_REVIEW'; unmapped.operations[0].department = '138';
  const identity = vehicle('identity', {details_source:'identity_review'});
  const ai = vehicle('ai'); ai.operations[0].hours_provenance = 'ai_estimated'; ai.operations[0].source_estimated_hours = null;
  const sublet = vehicle('sublet-zero'); sublet.operations[0].stage_code = 'SUBLET'; sublet.operations[0].estimated_hours = 0;
  const note = vehicle('review-note'); note.operations[0].review_note = 'Confirm the installation scope.';
  const manual = vehicle('manual'); manual.operations[0].source_kind = 'manual';
  const rejected = vehicle('rejected'); rejected.operations[0].rejected = true;
  const conflict = vehicle('conflicting-times'); conflict.operations[0].hours_provenance = 'conflicting_description_times';
  const unable = vehicle('unable'); unable.operations[0].hours_provenance = 'estimate_unable';
  const rows = [supplied,missing,unmapped,identity,ai,sublet,note,manual,rejected,conflict,unable], before = JSON.stringify(rows);
  const f = fixture(rows); f.options.pageSize = 2;
  const result = await f.run();
  assert.deepEqual(ids(f.state.attempts), ['tune-hours','sublet-zero']);
  assert.deepEqual(ids(result.approved), ['tune-hours','sublet-zero']);
  assert.equal(result.checked,11); assert.equal(result.total,11);
  assert.equal(result.ready,2); assert.equal(result.needsReview,9);
  assert.equal(result.stopped,false); assert.deepEqual(result.failed,[]);
  assert.equal(JSON.stringify(rows),before, 'bulk review never edits source hours or chooses a replacement station');
  assert.deepEqual(f.state.pages.map(page => page.offset),[0,2,4,6,8,10]);
});

test('approvals run sequentially and only a verified result reaches onApproved', async () => {
  const rows = [vehicle('first'),vehicle('second')], f = fixture(rows), first = deferred(), dispatched = deferred();
  f.options.approveRow = row => {
    f.state.attempts.push(row);
    if (row.vehicle_id === 'first') { dispatched.resolve(); return first.promise; }
    return Promise.resolve(receipt(row));
  };
  const running = f.run(); await dispatched.promise;
  assert.deepEqual(ids(f.state.attempts),['first']);
  assert.deepEqual(f.state.accepted,[], 'an in-flight write has not been verified');
  first.resolve(receipt(rows[0]));
  const result = await running;
  assert.deepEqual(ids(f.state.attempts),['first','second']);
  assert.deepEqual(ids(f.state.accepted),['first','second']);
  assert.deepEqual(ids(result.approved),['first','second']);
});

test('duplicate vehicles or a changing total invalidate pagination before any approval', async () => {
  for (const defect of ['duplicate','total_changed','wrong_offset','empty_more']) {
    const rows = [vehicle('one'),vehicle('two'),vehicle('three')], f = fixture(rows);
    f.options.pageSize = 2;
    f.options.listPage = async offset => {
      if (offset === 0) return {ok:true,data:{items:rows.slice(0,2),total:3,offset:0,has_more:true}};
      const next = {ok:true,data:{items:[rows[2]],total:3,offset:2,has_more:false}};
      if (defect === 'duplicate') next.data.items = [{...rows[0],snapshot_hash:'new-copy'}];
      if (defect === 'total_changed') next.data.total = 4;
      if (defect === 'wrong_offset') next.data.offset = 0;
      if (defect === 'empty_more') { next.data.items = []; next.data.has_more = true; }
      return next;
    };
    await assert.rejects(f.run, /queue_changed/, defect);
    assert.deepEqual(f.state.attempts,[],defect);
    assert.deepEqual(f.state.accepted,[],defect);
  }
});

test('a failure while collecting a later page cannot leave earlier rows partially approved', async () => {
  const f = fixture([vehicle('one'),vehicle('two')]); f.options.pageSize = 1;
  const list = f.options.listPage;
  f.options.listPage = (offset,limit) => offset ? Promise.reject(new Error('Network unavailable')) : list(offset,limit);
  await assert.rejects(f.run);
  assert.deepEqual(f.state.attempts,[]);
});

test('known row validation conflicts remain queued and the next ready vehicle continues', async () => {
  const rows = [vehicle('approved-before'),vehicle('changed'),vehicle('invalid'),vehicle('approved-after')];
  const f = fixture(rows);
  f.options.approveRow = async row => {
    f.state.attempts.push(row);
    if (row.vehicle_id === 'changed') throw new Error('review_changed');
    if (row.vehicle_id === 'invalid') throw new Error('operation_hours_or_state_need_review');
    return receipt(row);
  };
  const result = await f.run();
  assert.deepEqual(ids(f.state.attempts),ids(rows));
  assert.deepEqual(ids(result.approved),['approved-before','approved-after']);
  assert.deepEqual(ids(f.state.accepted),['approved-before','approved-after']);
  assert.deepEqual(result.failed.map(failure => failure.row.vehicle_id),['changed','invalid']);
  assert.ok(result.failed.every(failure => failure.error));
  assert.equal(result.stopped,false); assert.equal(result.ready,4);
});

test('network uncertainty or authorization rejection stops after preserving verified approvals', async () => {
  for (const error of ['Network request failed','permission_denied','unauthorized']) {
    const rows = [vehicle('verified'),vehicle('uncertain'),vehicle('untouched')], f = fixture(rows);
    f.options.approveRow = async row => {
      f.state.attempts.push(row);
      if (row.vehicle_id === 'uncertain') throw new Error(error);
      return receipt(row);
    };
    const result = await f.run();
    assert.deepEqual(ids(f.state.attempts),['verified','uncertain']);
    assert.deepEqual(ids(result.approved),['verified']); assert.deepEqual(ids(f.state.accepted),['verified']);
    assert.equal(result.failed.length,1); assert.equal(result.failed[0].row.vehicle_id,'uncertain');
    assert.equal(result.stopped,true);
  }
});

test('every approval receipt must match identity, unchanged work and zero bookings before continuing', async () => {
  const changes = [
    result => { result.ok = false; },
    result => { result.data.vehicle_id = 'another-vehicle'; },
    result => { result.data.visible_on_board = false; },
    result => { result.data.bookings_created = 1; },
    result => { result.data.operations[0].estimated_hours = 9; },
    result => { result.data.operations[0].description = 'Changed work'; },
    result => { result.data.operations[0].stage_code = 'ELECTRICAL'; },
    result => { result.data.operations[0].source_line_id = 'wrong-source'; },
    result => { result.data.operations[0].completed = true; },
    result => { result.data.operations = []; },
  ];
  for (const change of changes) {
    const rows = [vehicle('unconfirmed'),vehicle('untouched')], f = fixture(rows);
    f.options.approveRow = async row => { f.state.attempts.push(row); const result = receipt(row); change(result); return result; };
    const result = await f.run();
    assert.deepEqual(ids(f.state.attempts),['unconfirmed']);
    assert.deepEqual(result.approved,[]); assert.deepEqual(f.state.accepted,[]);
    assert.equal(result.failed.length,1); assert.equal(result.failed[0].row.vehicle_id,'unconfirmed');
    assert.equal(result.stopped,true);
  }
});

test('Stop lets the current request finish and prevents all following approvals', async () => {
  const rows = [vehicle('in-flight'),vehicle('untouched')], f = fixture(rows), current = deferred(), dispatched = deferred();
  f.options.approveRow = row => { f.state.attempts.push(row); dispatched.resolve(); return current.promise; };
  const running = f.run(); await dispatched.promise;
  f.state.stop = true;
  assert.deepEqual(f.state.accepted,[]);
  current.resolve(receipt(rows[0]));
  const result = await running;
  assert.deepEqual(ids(result.approved),['in-flight']); assert.deepEqual(ids(f.state.accepted),['in-flight']);
  assert.deepEqual(ids(f.state.attempts),['in-flight']); assert.equal(result.stopped,true);
});

test('session changes discard a late approval receipt and cannot authorize a second write', async () => {
  const rows = [vehicle('former-user'),vehicle('next')], f = fixture(rows), current = deferred(), dispatched = deferred();
  f.options.approveRow = row => { f.state.attempts.push(row); dispatched.resolve(); return current.promise; };
  const running = f.run(); await dispatched.promise;
  f.state.current = false; current.resolve(receipt(rows[0]));
  await assert.rejects(running,/session_changed/);
  assert.deepEqual(ids(f.state.attempts),['former-user']);
  assert.deepEqual(f.state.accepted,[], 'an old-session receipt cannot remove a card in the new session');
});

test('a session change during pagination or after a verified row blocks subsequent writes', async () => {
  const rows = [vehicle('one'),vehicle('two')];
  const duringList = fixture(rows), list = duringList.options.listPage;
  duringList.options.listPage = async (offset,limit) => { const result = await list(offset,limit); duringList.state.current = false; return result; };
  await assert.rejects(duringList.run,/session_changed/); assert.deepEqual(duringList.state.attempts,[]);
  const afterApproval = fixture(rows);
  afterApproval.options.onApproved = row => { afterApproval.state.accepted.push(row); afterApproval.state.current = false; };
  await assert.rejects(afterApproval.run,/session_changed/);
  assert.deepEqual(ids(afterApproval.state.attempts),['one']); assert.deepEqual(ids(afterApproval.state.accepted),['one']);
});

test('empty and entirely unresolved queues perform no writes', async () => {
  for (const rows of [[],[vehicle('identity',{details_source:'identity_review'})]]) {
    const f = fixture(rows), result = await f.run();
    assert.equal(result.checked,rows.length); assert.equal(result.total,rows.length);
    assert.equal(result.ready,0); assert.equal(result.needsReview,rows.length);
    assert.deepEqual(result.approved,[]); assert.deepEqual(result.failed,[]);
    assert.deepEqual(f.state.attempts,[]); assert.equal(result.stopped,false);
  }
});
