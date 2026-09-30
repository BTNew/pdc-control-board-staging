'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {FEEDS,formatDate,validTime,normalizeReport,reportHtml,createController} = require('./pdc-update-history.js');

const time = '2026-09-29T17:12:00Z';
const report = (feeds = [],history = []) => ({ok:true,generated_at:time,feeds,history});
const feed = (overrides = {}) => ({key:'broome_navision',last_success_at:time,last_attempt_at:time,last_status:'completed',record_count:23,...overrides});
function fixture() {
  let ctx = {userId:'synthetic-admin',role:'administrator',token:'synthetic-token',url:'https://example.invalid',key:'synthetic-key'};
  const pending = [], renders = [];
  const controller = createController({
    context:() => ctx,
    request:captured => new Promise((resolve,reject) => pending.push({captured,resolve,reject})),
    render:state => renders.push(state)
  });
  return {controller,pending,renders,change:values => {ctx = {...ctx,...values};}};
}

test('dates are Perth time across UTC midnight rather than the device timezone', () => {
  assert.match(formatDate(time),/30 Sept 2026/);
  assert.match(formatDate(time),/1:12 am/);
  assert.equal(formatDate('2026-09-30T01:12:00+08:00'),formatDate(time));
});

test('unknown and ambiguous dates never become a made-up update time', () => {
  for (const value of [null,undefined,'','invalid','2026-09-30','2026-09-30T01:12:00',0,{},'2030-99-99T00:00:00Z']) {
    assert.equal(validTime(value),null);
    assert.equal(formatDate(value),'Not recorded');
  }
});

test('the five requested feeds always appear, even with no recorded imports', () => {
  const normalized = normalizeReport(report());
  assert.deepEqual(normalized.feeds.map(x=>x.key),FEEDS.map(x=>x.key));
  assert.equal(normalized.feeds.length,5);
  assert.equal(normalized.feeds.filter(x=>x.last_success_at).length,0);
  const html = reportHtml(normalized);
  assert.equal((html.match(/No completed update recorded/g)||[]).length,5);
  assert.match(html,/No update history has been recorded yet/);
});

test('a newer failed or pending attempt does not replace the last completed update', () => {
  for (const status of ['failed','processing','partial']) {
    const normalized = normalizeReport(report([feed({last_attempt_at:'2026-09-30T02:00:00Z',last_status:status})]));
    assert.equal(normalized.feeds[0].last_success_at,new Date(time).toISOString());
    const html = reportHtml(normalized);
    assert.match(html,/This attempt has not replaced the latest completed update/);
    assert.match(html,/30 Sept 2026, 1:12 am/);
    assert.match(html,/30 Sept 2026, 10:00 am/);
  }
});

test('an unsuccessful first attempt is not labelled as a completed update', () => {
  const normalized = normalizeReport(report([feed({last_success_at:null,last_status:'failed'})]));
  const html = reportHtml(normalized);
  assert.match(html,/<strong>Failed<\/strong>/);
  assert.doesNotMatch(html,/class="update-history-badge is-success"/);
  assert.equal((html.match(/No completed update recorded/g)||[]).length,5);
});

test('completed imports with held or unmatched rows show a review warning and source row counts', () => {
  const html = reportHtml(normalizeReport(report([feed({last_status:'completed_with_warnings',record_count:100,detail:'80 updated; 20 held for review.'})])));
  assert.match(html,/is-pending">Completed · review items/);
  assert.match(html,/100 source rows/);
  assert.match(html,/80 updated; 20 held for review/);
  assert.doesNotMatch(html,/This attempt has not replaced/);
});

test('preview and rollback attempts remain separate from a prior warned completion', () => {
  for (const latest of ['preview','rolled_back']) {
    const normalized = normalizeReport(report([feed({last_success_status:'completed_with_warnings',last_attempt_at:'2026-09-30T02:00:00Z',last_status:latest})]));
    const html = reportHtml(normalized);
    assert.match(html,/Completed · review items/);
    assert.match(html,/This attempt has not replaced/);
    assert.match(html,latest === 'preview' ? /Preview only/ : /Rolled back/);
  }
});

test('untrusted data is escaped and cannot supply feed labels or CSS classes', () => {
  const injection = '<img src=x onerror="bad()">';
  const normalized = normalizeReport(report([feed({label:injection,detail:injection,last_status:injection})],[{feed_key:'parts_info',completed_at:time,status:injection,detail:injection}]));
  const html = reportHtml(normalized);
  assert.doesNotMatch(html,/<img|onerror="bad/);
  assert.match(html,/&lt;img src=x onerror=&quot;bad\(\)&quot;&gt;/);
  assert.match(html,/Broome Navision Update/);
  assert.match(html,/Status unavailable/);
});

test('malformed authority responses fail closed instead of showing false empty success', () => {
  for (const value of [null,{},[],{ok:false,feeds:[]},{feeds:[]},{ok:true,feeds:'bad'}]) {
    assert.throws(()=>normalizeReport(value),/unavailable/);
  }
});

test('history is newest first, capped, limited to known feeds, and does not mutate input', () => {
  const rows = Array.from({length:25},(_,i)=>({feed_key:'parts_info',completed_at:new Date(Date.parse(time)+i*60000).toISOString(),status:'completed',record_count:i}));
  for (const key of ['unexpected','__proto__','constructor']) rows.push({feed_key:key,completed_at:'2040-01-01T00:00:00Z',status:'completed'});
  const original = JSON.stringify(rows);
  const normalized = normalizeReport(report([],rows));
  assert.equal(normalized.history.length,20);
  assert.equal(normalized.history[0].record_count,24);
  assert.equal(normalized.history[19].record_count,5);
  assert.equal(JSON.stringify(rows),original);
});

test('invalid counts are unavailable and a valid zero remains zero', () => {
  for (const value of [undefined,null,'',' ',true,false,[],{},-1,1.5,'not a number',Infinity]) {
    assert.equal(normalizeReport(report([feed({record_count:value})])).feeds[0].record_count,null);
  }
  assert.equal(normalizeReport(report([feed({record_count:0})])).feeds[0].record_count,0);
});

test('non-admin and signed-out users never make a history request', async () => {
  for (const changes of [{role:'operator'},{role:'fitter'},{userId:null},{token:null}]) {
    const f = fixture(); f.change(changes);
    await f.controller.open();
    assert.equal(f.pending.length,0);
    assert.equal(f.controller.getState().allowed,false);
  }
});

test('repeated refresh is deduplicated and closing the page discards pending results', async () => {
  const f = fixture();
  const opened = f.controller.open();
  await f.controller.refresh();
  assert.equal(f.pending.length,1);
  f.controller.close();
  f.pending[0].resolve(report([feed()])); await opened;
  assert.equal(f.controller.getState().report,null);
  await f.controller.refresh();
  assert.equal(f.pending.length,1);
});

test('rerendering the active view does not repeatedly reload a completed report', async () => {
  const f = fixture();
  const loading = f.controller.open(); f.pending[0].resolve(report([feed()])); await loading;
  await f.controller.open(); await f.controller.open();
  assert.equal(f.pending.length,1);
  f.controller.close();
  const reopened = f.controller.open();
  assert.equal(f.pending.length,2);
  f.pending[1].resolve(report()); await reopened;
  f.change({token:'rotated-synthetic-token'});
  const changedSession = f.controller.open();
  assert.equal(f.pending.length,3);
  f.pending[2].resolve(report()); await changedSession;
});

test('a session lock clears loaded information and ignores pending replies', async () => {
  const f = fixture();
  const first = f.controller.open(); f.pending[0].resolve(report([feed()])); await first;
  assert.ok(f.controller.getState().report);
  const refresh = f.controller.refresh(); f.controller.reset();
  assert.equal(f.controller.getState().report,null);
  f.pending[1].resolve(report([feed()])); await refresh;
  assert.equal(f.controller.getState().report,null);
  assert.equal(f.controller.getState().allowed,false);
});

test('responses cannot cross a user, role, token, or backend change', async () => {
  for (const changes of [{userId:'another-synthetic-admin'},{role:'fitter'},{token:'rotated-synthetic-token'},{url:'https://other.example.invalid'}]) {
    const f = fixture();
    const loading = f.controller.open();
    f.change(changes);
    f.pending[0].resolve(report([feed()])); await loading;
    assert.equal(f.controller.getState().report,null);
    assert.equal(f.controller.getState().loading,false);
  }
});

test('a superseded request cannot overwrite a newer view result', async () => {
  const f = fixture();
  const old = f.controller.open(); f.controller.close();
  const fresh = f.controller.open();
  f.pending[1].resolve(report([feed({record_count:99})])); await fresh;
  f.pending[0].resolve(report([feed({record_count:1})])); await old;
  assert.equal(f.controller.getState().report.feeds[0].record_count,99);
});

test('request failure is visible and previous data is only retained for the same authority', async () => {
  const f = fixture();
  const first = f.controller.open(); f.pending[0].resolve(report([feed()])); await first;
  const second = f.controller.refresh(); f.pending[1].reject(new Error('synthetic network outage')); await second;
  assert.match(f.controller.getState().error,/Could not load/);
  assert.ok(f.controller.getState().report);
  f.change({userId:'another-synthetic-admin'}); f.controller.syncAccess();
  assert.equal(f.controller.getState().report,null);
});

test('browser access sync explicitly hides both the navigation item and page on auth lock', () => {
  const nav = {hidden:true}, view = {hidden:true,classList:{contains:()=>false}};
  const host = {replaceChildren(){this.cleared = true;}}, listeners = {};
  const window = {
    PDC_AUTH_CONTEXT:{userId:'synthetic-admin',role:'administrator'},__pdcCachedAccessToken:'synthetic-token',
    document:{getElementById:id=>({'nav-update-history':nav,'update-history':view,'update-history-content':host}[id])},
    addEventListener:(name,fn)=>{listeners[name]=fn;}
  };
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-update-history.js'),'utf8'),{window});
  assert.equal(nav.hidden,false);
  assert.equal(view.hidden,false);
  listeners['pdc-auth-locked']();
  assert.equal(nav.hidden,true);
  assert.equal(view.hidden,true);
  assert.equal(host.cleared,true);
  listeners['pdc-auth-ready']();
  assert.equal(nav.hidden,false);
  assert.equal(view.hidden,false);
  window.PDC_AUTH_CONTEXT.role='operator'; window.PdcUpdateHistory.syncAccess();
  assert.equal(nav.hidden,true);
  assert.equal(view.hidden,true);
});
