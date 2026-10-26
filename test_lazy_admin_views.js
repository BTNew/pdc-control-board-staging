'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { DEFINITIONS, install } = require('./pdc-lazy-admin-views.js');

function harness(role = 'administrator', definition = DEFINITIONS[0]) {
  const nodes = new Map(), events = {}, timers = new Map(), assets = [];
  let timerId = 0;
  function element(tag = 'div') {
    return {tagName:tag, dataset:{}, hidden:false, children:[], attributes:{}, classList:{contains:() => false},
      setAttribute(key,value) { this.attributes[key] = value; },
      replaceChildren(...children) { this.children = children; },
      appendChild(child) { this.children.push(child); if (child.id) nodes.set(child.id,child); return child; },
      addEventListener(type, callback) { this[type] = callback; },
      remove() { if (this.id) nodes.delete(this.id); this.removed = true; }};
  }
  const host = element(); nodes.set(definition.view + '-content',host);
  for (const id of ['nav-' + definition.view, definition.view]) nodes.set(id,element());
  const section = nodes.get(definition.view);
  section.classList = { active:true, contains(name) { return name === 'active' && this.active; } };
  const head = element('head'); head.appendChild = child => { assets.push(child); nodes.set(child.id,child); };
  const win = { document:{head,getElementById:id => nodes.get(id),createElement:element},
    PDC_AUTH_CONTEXT:{role,userId:'synthetic-user'}, __pdcCachedAccessToken:'synthetic-token',
    PDC_SUPABASE_CONFIG:{url:'https://example.invalid',publishableKey:'public'},
    setTimeout(callback) { timers.set(++timerId,callback); return timerId; }, clearTimeout(id) { timers.delete(id); },
    addEventListener(event,fn) { (events[event] ||= []).push(fn); }};
  const stub = install(win,definition);
  const settle = async () => { for (let i=0;i<8;i++) await Promise.resolve(); };
  const emit = event => (events[event] || []).forEach(fn => fn());
  async function loadStyle() { assets.at(-1).onload(); await settle(); }
  async function loadScript(controller) { win[definition.name] = controller; assets.at(-1).onload(); await settle(); }
  return {win,stub,assets,timers,nodes,host,events,emit,loadStyle,loadScript,settle,definition};
}

test('reports are absent from startup; lazy entry preserves the existing global API names', () => {
  const html = fs.readFileSync('index.html','utf8');
  assert.match(html, /pdc-lazy-admin-views\.js\?v=2026\.10\.26\.opt1/);
  for (const def of DEFINITIONS) {
    assert.ok(!html.includes('src="'+def.script));
    assert.ok(!html.includes('href="'+def.css));
    const h = harness('administrator',def);
    assert.equal(h.assets.length,0);
    assert.equal(h.win[def.name],h.stub);
    assert.equal(h.nodes.get('nav-'+def.view).hidden,false);
  }
});
test('denied and signed-out access never downloads a report', async () => {
  for (const role of ['operator','viewer','importer','fitter',null]) {
    const h = harness(role); await h.stub.open();
    assert.equal(h.assets.length,0); assert.equal(h.nodes.get('nav-'+h.definition.view).hidden,true);
  }
  const h = harness(); h.win.__pdcCachedAccessToken = ''; await h.stub.open(); assert.equal(h.assets.length,0);
});
test('concurrent opens load style then script once and open controller once', async () => {
  const h = harness(); let opened=0;
  const a=h.stub.open(), b=h.stub.open(); assert.equal(a,b); assert.equal(h.assets.length,1);
  assert.equal(h.assets[0].tagName,'link');
  await h.loadStyle(); assert.equal(h.assets.length,2); assert.equal(h.assets[1].tagName,'script');
  await h.loadScript({open(){opened++;},reset(){throw Error('unexpected reset');}});
  await Promise.all([a,b]); assert.equal(opened,1); assert.equal(h.timers.size,0);
});
test('closing or changing identity while download is pending cannot open stale report', async () => {
  for (const change of [h=>h.stub.close(),h=>{h.win.__pdcCachedAccessToken='next-user-token';}]) {
    const h=harness(); let opened=0; const pending=h.stub.open();
    change(h); await h.loadStyle(); await h.loadScript({open(){opened++;},reset(){}});
    await pending; assert.equal(opened,0);
  }
});
test('auth lock during asset download resets the installed controller', async () => {
  const h=harness(); let opened=0,reset=0; const pending=h.stub.open(); h.emit('pdc-auth-locked');
  await h.loadStyle(); await h.loadScript({open(){opened++;},reset(){reset++;}}); await pending;
  assert.equal(opened,0); assert.equal(reset,1);
});
test('close and reopen during download uses the latest open without duplicate assets', async () => {
  const h=harness(); let opened=0; const first=h.stub.open(); h.stub.close(); const second=h.stub.open();
  await h.loadStyle(); await h.loadScript({open(){opened++;},reset(){}}); await Promise.all([first,second]);
  assert.equal(opened,1); assert.equal(h.assets.length,2);
});
test('failed asset has visible retry and next open replaces the failed element', async () => {
  const h=harness(); const first=h.stub.open(); h.assets[0].onerror(); await first;
  assert.equal(h.assets[0].removed,true); assert.equal(h.host.children.at(-1).textContent,'Try again');
  let opened=0; const second=h.stub.open(); await h.loadStyle();
  await h.loadScript({open(){opened++;},reset(){}}); await second; assert.equal(opened,1);
});
test('unresponsive asset times out and leaves a retry instead of a perpetual spinner', async () => {
  const h=harness(); const pending=h.stub.open(); [...h.timers.values()][0](); await pending;
  assert.equal(h.assets[0].removed,true); assert.match(h.host.children[0].textContent,/could not load/);
});
test('actual update-history controller loaded after auth-ready opens normally and clears on lock', async () => {
  const h=harness(); const host=h.host;
  host.contains=()=>false; host.querySelector=()=>null;
  h.win.document.activeElement=null;
  let requests=0;
  h.win.fetch=async()=>{requests++;return {ok:true,json:async()=>({ok:true,feeds:[],history:[]})};};
  const pending=h.stub.open(); await h.loadStyle();
  vm.runInNewContext(fs.readFileSync('pdc-update-history.js','utf8'),{window:h.win});
  h.assets.at(-1).onload(); await pending;
  assert.equal(requests,1); assert.match(host.innerHTML,/Latest completed imports/);
  h.emit('pdc-auth-locked'); assert.equal(h.nodes.get('nav-update-history').hidden,true);
});


test('a loaded script without a controller can be downloaded successfully on retry', async () => {
  const h = harness(); let opened = 0;
  const first = h.stub.open(); await h.loadStyle();
  const failed = h.assets.at(-1); failed.onload(); await first;
  assert.equal(failed.removed, true);
  assert.equal(h.host.children.at(-1).textContent, 'Try again');
  const second = h.stub.open(); await h.settle();
  assert.equal(h.assets.length, 3, 'valid stylesheet reused, failed script requested again');
  assert.equal(h.assets.at(-1).tagName, 'script');
  await h.loadScript({open(){opened++;},reset(){}}); await second;
  assert.equal(opened, 1);
});

test('auth-ready while loading refreshes the pending identity without downloading twice', async () => {
  for (const change of [h=>{h.win.__pdcCachedAccessToken='refreshed-token';},
    h=>{h.win.PDC_AUTH_CONTEXT.userId='next-synthetic-admin'; h.win.__pdcCachedAccessToken='next-admin-token';}]) {
    const h = harness(); let opened = 0;
    const first = h.stub.open(); change(h); h.emit('pdc-auth-ready');
    await h.loadStyle(); await h.loadScript({open(){opened++;},reset(){}});
    await first; await h.settle();
    assert.equal(opened, 1); assert.equal(h.assets.length, 2);
  }
});

test('navigation after controller installation but before load completion cannot reopen the hidden view', async () => {
  const h = harness(); let opened = 0, closed = 0;
  const pending = h.stub.open(); await h.loadStyle();
  h.win[h.definition.name] = {open(){opened++;},close(){closed++;},reset(){}};
  h.win[h.definition.name].close();
  h.nodes.get(h.definition.view).classList.active = false;
  h.assets.at(-1).onload(); await pending;
  assert.equal(closed, 1); assert.equal(opened, 0);
});

test('a controller arriving after script timeout is reused without a second installation', async () => {
  const h = harness(); let opened = 0;
  const first = h.stub.open(); await h.loadStyle();
  [...h.timers.values()][0](); await first;
  h.win[h.definition.name] = {open(){opened++;},reset(){}};
  await h.stub.open();
  assert.equal(opened, 1); assert.equal(h.assets.length, 2);
});
