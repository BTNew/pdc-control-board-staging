/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {resolvePage, cleanPage, PAGE_LABELS, PAGE_ALIASES} = require('./pdc-staff-usage.js');
const code = fs.readFileSync(path.join(__dirname, 'pdc-staff-usage.js'), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));

function browser({sales = false, view = 'dashboard', role = 'operator', signedIn = true, hidden = false, offline = false, navVisible = true} = {}) {
  const events = {window:new Map(), document:new Map()}, requests = [], timeouts = [], intervals = new Map(), watched = [];
  let uuid = 0, observer, current = view, financeTab = 'pipeline';
  const html = fs.readFileSync(path.join(__dirname, sales ? 'sales/index.html' : 'index.html'), 'utf8');
  const views = [...html.matchAll(/<section id="([^"]+)" class="(?:view|sales-view)(?: active)?"/g)].map(m => ({id:m[1]}));
  const doc = {
    visibilityState:hidden ? 'hidden' : 'visible',
    body:{dataset:{get currentView() { return current; }}},
    querySelector(selector) {
      if (selector === '.nav-item.active[data-sales-view]') return sales ? {dataset:{salesView:current}} : null;
      if (selector === '.sales-view:not([hidden])') return sales ? {id:'sales-' + current + '-view'} : null;
      if (selector === '[data-finance-view][aria-pressed="true"]') return sales && current === 'finance' ? {dataset:{financeView:financeTab}} : null;
      if (selector === '.view.active') return sales ? null : {id:current === 'planner-bus-pit' ? 'bus-pit' : current.startsWith('planner-') ? 'workshop' : current};
      if (selector === '.nav-item.active[data-view]') return sales || !navVisible ? null : {dataset:{view:current}};
      return null;
    },
    querySelectorAll(selector) { return selector === '.view, .sales-view' ? views : []; },
    getElementById() { return null; },
    addEventListener(name, fn) { events.document.set(name, fn); }
  };
  const win = {
    document:doc, crypto:{randomUUID:() => 'batch-' + ++uuid}, performance:{now:() => 0},
    PDC_SUPABASE_CONFIG:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'public-test-key'},
    PDC_AUTH_CONTEXT:signedIn ? {userId:'staff-a',role} : undefined,
    __pdcCachedAccessToken:signedIn ? 'token-a' : undefined,
    addEventListener(name, fn) { events.window.set(name, fn); },
    setTimeout(fn) { timeouts.push(fn); },
    setInterval(fn, ms) { intervals.set(ms, fn); },
    MutationObserver:class {
      constructor(fn) { observer = fn; }
      observe(view, options) { watched.push({view, options}); }
    },
    fetch(url, options) {
      requests.push({url, body:JSON.parse(options.body), headers:options.headers, keepalive:options.keepalive});
      return Promise.resolve({ok:!offline, json:async () => ({ok:true})});
    }
  };
  vm.runInNewContext(code, {window:win});
  return {
    doc, win, requests, watched,
    async interval(ms = 15000) { intervals.get(ms)(); await tick(); },
    async click({trusted = true, scope = 'app', navigate, text = 'Customer data must stay private'} = {}) {
      events.document.get('click')({isTrusted:trusted,target:{value:text,textContent:text,closest:selector =>
        (scope === 'app' && selector.includes('#app-shell')) || (scope === 'dialog' && selector.includes('dialog')) ? {} : null}});
      if (navigate) current = navigate;
      while (timeouts.length) timeouts.shift()();
      await tick();
    },
    route(name, tab) { current = name; if (tab) financeTab = tab; observer(); },
    event(name, surface = 'window') { events[surface].get(name)(); },
    setFinanceTab(name) { financeTab = name; },
    online() { offline = false; }
  };
}

test('Every published PDC view/navigation and Sales view has a named activity page', () => {
  const pdc = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  for (const m of pdc.matchAll(/data-view="([^"]+)"|<section id="([^"]+)" class="view(?: active)?"/g)) {
    const view = m[1] || m[2];
    assert.notEqual(cleanPage(view), 'other', view);
    assert.ok(PAGE_LABELS[cleanPage(view)], view);
  }
  const sales = fs.readFileSync(path.join(__dirname, 'sales/index.html'), 'utf8');
  // r768: a Sales view may share an existing bucket through an alias (Navision Uploads -> import), like the PDC views above.
  for (const m of sales.matchAll(/<section id="sales-(.+?)-view" class="sales-view"/g)) { assert.notEqual(cleanPage('sales-' + m[1]), 'other', m[1]); assert.ok(PAGE_LABELS[cleanPage('sales-' + m[1])], m[1]); }
  for (const file of ['index.html', 'sales/index.html']) {
    const html = fs.readFileSync(path.join(__dirname, file), 'utf8');
    assert.equal([...html.matchAll(/src="(?:\.\.\/)?pdc-staff-usage\.js\?/g)].length, 1, file);
    assert.ok(html.includes('all-pages=2026.10.16.01'), file);
  }
});

test('Client and database page allowlists stay identical', () => {
  const sql = fs.readFileSync(path.join(__dirname, 'supabase/migrations/20261015003957_accepted_vehicle_operation_updates.sql'), 'utf8');
  const list = sql.match(/p_page not in \(([\s\S]*?)\)/)[1];
  assert.deepEqual([...list.matchAll(/'([^']+)'/g)].map(m => m[1]).sort(), Object.keys(PAGE_LABELS).sort());
  for (const canonical of Object.values(PAGE_ALIASES)) assert.ok(PAGE_LABELS[canonical], canonical);
  assert.ok(sql.includes("'administrator','fitter','salesperson'"));
});

test('Workshop station pages keep individual names inside the shared workshop section', () => {
  for (const name of Object.keys(PAGE_LABELS).filter(x => x.startsWith('planner-'))) {
    const b = browser({view:name});
    assert.equal(resolvePage(b.doc), name);
    assert.equal(b.requests[0].body.p_page, name);
  }
});

test('Bus category visits and clicks use the existing Bus reporting bucket while Pit uses Departments', async () => {
  const busViews = ['planner-bus-mechanical', 'planner-bus-accessory', 'planner-bus-electrical', 'planner-bus-qa'];
  for (const view of busViews) {
    const b = browser({view}); await tick();
    assert.equal(resolvePage(b.doc), 'planner-bus-4x4');
    await b.click(); await b.interval();
    assert.ok(b.requests.some(request => request.body.p_page === 'planner-bus-4x4' && request.body.p_clicks === 1));
    assert.ok(b.requests.every(request => request.body.p_page === 'planner-bus-4x4'));
  }
  for (const view of ['planner-bus-pit', 'bus-pit']) {
    const b = browser({view}); await tick(); await b.click(); await b.interval();
    assert.equal(resolvePage(b.doc), 'department');
    assert.ok(b.requests.some(request => request.body.p_page === 'department' && request.body.p_clicks === 1));
    assert.ok(b.requests.every(request => request.body.p_page === 'department'));
  }
  const allBays = browser({view:'planner-bus-4x4', navVisible:false}); await tick();
  assert.equal(resolvePage(allBays.doc), 'planner-bus-4x4');
  assert.equal(allBays.requests[0].body.p_page, 'planner-bus-4x4');
});

test('moving between Bus categories keeps one Bus visit and entering Pit records a separate department visit', async () => {
  const b = browser({view:'planner-bus-mechanical'}); await tick();
  await b.click({navigate:'planner-bus-electrical'}); await b.interval();
  await b.click({navigate:'planner-bus-pit'}); await b.interval();
  await b.click(); await b.interval();
  const batches = b.requests.map(request => request.body);
  assert.equal(batches.filter(batch => batch.p_visit && batch.p_page === 'planner-bus-4x4').length, 1);
  assert.equal(batches.filter(batch => batch.p_visit && batch.p_page === 'department').length, 1);
  assert.equal(batches.filter(batch => batch.p_page === 'planner-bus-4x4').reduce((total, batch) => total + batch.p_clicks, 0), 2);
  assert.equal(batches.filter(batch => batch.p_page === 'department').reduce((total, batch) => total + batch.p_clicks, 0), 1);
  assert.ok(batches.every(batch => PAGE_LABELS[batch.p_page] && batch.p_page !== 'other'));
});

test('Sales user visits all pages; Finance tabs and customer-email dialog clicks retain correct attribution', async () => {
  const b = browser({sales:true,role:'salesperson'});
  await tick();
  const names = ['myday','customeremails','alerts','labels','history','pipeline'];
  for (const name of names) { b.route(name); await b.click({scope:name === 'customeremails' ? 'dialog' : 'app'}); await b.interval(); }
  b.route('finance'); await b.click(); await b.interval();
  b.setFinanceTab('statistics'); await b.click(); await b.interval();
  b.setFinanceTab('all'); await b.click(); await b.interval(); await b.interval();
  const pages = b.requests.map(r => r.body.p_page);
  for (const name of ['sales-dashboard', ...names.map(x => 'sales-' + x), 'sales-finance', 'sales-finance-statistics', 'sales-finance-applications']) {
    assert.ok(pages.includes(name), name);
  }
  assert.ok(b.requests.some(r => r.body.p_page === 'sales-customeremails' && r.body.p_clicks === 1));
  for (const r of b.requests) {
    assert.deepEqual(Object.keys(r.body).sort(), ['p_batch_id','p_clicks','p_page','p_visit']);
    assert.equal(r.headers.Authorization, 'Bearer token-a');
    assert.equal(r.keepalive, true);
    assert.ok(!JSON.stringify(r).includes('Customer data'));
  }
});

test('A navigation click belongs to its source page, then the destination records a visit', async () => {
  const b = browser({sales:true,role:'administrator'}); await tick();
  await b.click({navigate:'finance'}); await b.interval(); await b.interval();
  assert.ok(b.requests.some(r => r.body.p_page === 'sales-dashboard' && r.body.p_clicks === 1 && r.body.p_visit === false));
  assert.ok(b.requests.some(r => r.body.p_page === 'sales-finance' && r.body.p_visit === true));
  assert.ok(b.requests.every(r => r.url.endsWith('/record_pdc_usage_20260914')), 'Sales administrators must not fetch the staff report on Sales pages');
});

test('Sales hidden-attribute routing is observed without observing planner tile subtrees', () => {
  const b = browser({sales:true});
  assert.equal(b.watched.length, 9); // r768: + Navision Uploads
  for (const {options} of b.watched) {
    assert.ok(options.attributeFilter.includes('hidden'));
    assert.equal(options.subtree, undefined);
    assert.equal(options.childList, undefined);
  }
});

test('Idle intervals and refreshed auth-ready notifications add no clicks or visits', async () => {
  const b = browser({sales:true}); await tick();
  const count = b.requests.length;
  for (let i = 0; i < 5; i++) { b.event('pdc-auth-ready'); await b.interval(); await b.interval(30000); }
  assert.equal(b.requests.length, count);
});

test('Signed-out, locked, hidden, authentication-form and synthetic clicks cannot establish activity', async () => {
  const signedOut = browser({signedIn:false,sales:true}); await signedOut.click(); await signedOut.interval();
  assert.equal(signedOut.requests.length, 0);
  const hidden = browser({hidden:true,sales:true}); await hidden.click(); await hidden.interval();
  assert.equal(hidden.requests.length, 0);
  hidden.doc.visibilityState = 'visible'; hidden.event('visibilitychange','document'); await hidden.interval();
  assert.equal(hidden.requests.length, 1);
  const b = browser({sales:true}); await tick(); const count = b.requests.length;
  await b.click({trusted:false}); await b.click({scope:'auth'}); await b.interval();
  assert.equal(b.requests.length, count);
  b.event('pdc-auth-locked'); await b.click(); await b.interval();
  assert.equal(b.requests.length, count);
});

test('Network failures retry the exact batch; pagehide flushes a pending dialog click', async () => {
  const b = browser({sales:true,offline:true}); await tick();
  await b.interval(); assert.deepEqual(b.requests[0].body, b.requests[1].body);
  b.online(); await b.interval();
  await b.click({scope:'dialog'}); b.event('pagehide'); await tick();
  assert.equal(b.requests.at(-1).body.p_clicks, 1);
  assert.equal(b.requests.at(-1).body.p_page, 'sales-dashboard');
});

test('Switching accounts clears pending activity before the new user click and captures its token', async () => {
  const b = browser({sales:true,offline:true}); await tick(); await b.click();
  b.win.PDC_AUTH_CONTEXT = {userId:'staff-b',role:'salesperson'};
  b.win.__pdcCachedAccessToken = 'token-b'; b.online();
  await b.click(); await b.interval();
  const current = b.requests.filter(r => r.headers.Authorization === 'Bearer token-b');
  assert.equal(current.length, 2);
  assert.equal(current[0].body.p_visit, true);
  assert.equal(current[0].body.p_clicks, 0);
  assert.equal(current[1].body.p_visit, false);
  assert.equal(current[1].body.p_clicks, 1);
  assert.ok(current.every(r => r.body.p_batch_id !== b.requests[0].body.p_batch_id));
});
