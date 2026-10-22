/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r441 (F52): open pages reload once after a release, only when no work can be lost.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const reload = require('./pdc-auto-reload.js');
const builder = require('./scripts/build_pages_runtime.js');
const code = fs.readFileSync(path.join(__dirname, 'pdc-auto-reload.js'), 'utf8');
const TAG = 'pdc-auto-reload.js?v=2026.10.21.r441';
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const base = { loaded: 'b-old000', server: 'b-new000', now: 100000, lastTypingAt: NaN, writesInFlight: 0, unsaved: false, modalOpen: false, pointerActive: false, fieldFocused: false, alreadyReloadedFor: null, guardUnavailable: false };

test('version change reloads; same, missing or first version does not', () => {
  assert.deepEqual(reload.decide(base), { action: 'reload', reason: 'new-version' });
  assert.equal(reload.decide({ ...base, server: 'b-old000' }).action, 'none');
  assert.equal(reload.decide({ ...base, server: null }).reason, 'no-version');
  assert.equal(reload.decide({ ...base, server: '<bad>' }).reason, 'no-version');
  assert.equal(reload.decide({ ...base, loaded: null }).reason, 'baseline');
});

test('unsaved work defers the reload', () => {
  const reasons = [
    [{ writesInFlight: 1 }, 'saving'], [{ unsaved: true }, 'unsaved'], [{ modalOpen: true }, 'modal-open'],
    [{ pointerActive: true }, 'dragging'], [{ fieldFocused: true }, 'field-focused'], [{ lastTypingAt: 100000 - 9999 }, 'recent-typing']
  ];
  for (const [change, reason] of reasons) assert.deepEqual(reload.decide({ ...base, ...change }), { action: 'defer', reason }, reason);
  assert.equal(reload.decide({ ...base, lastTypingAt: 100000 - 10000 }).action, 'reload', '10 s with no typing is idle');
});

test('loop guard allows one reload per version and none without session storage', () => {
  assert.equal(reload.decide({ ...base, alreadyReloadedFor: 'b-new000' }).reason, 'loop-guard');
  assert.equal(reload.decide({ ...base, alreadyReloadedFor: 'b-older00' }).action, 'reload', 'a newer release may reload again');
  assert.equal(reload.decide({ ...base, guardUnavailable: true }).reason, 'loop-guard-unavailable');
});

test('malformed version.json is ignored and fetch failures back off to 15 minutes', () => {
  for (const body of ['', '{', '[]', 'null', '{"build":1}', '{"build":"x"}', '{"build":"<script>"}', '{}', []]) assert.equal(reload.parseVersion(body), null, JSON.stringify(body));
  assert.equal(reload.parseVersion('{"build":"b-1e45d88164a68852b555","commit":"abc"}'), 'b-1e45d88164a68852b555');
  assert.deepEqual([0, 1, 2, 3, 4, 5, 9].map(reload.nextDelay), [60000, 120000, 240000, 480000, 900000, 900000, 900000]);
});

test('only text fields count as typing focus', () => {
  for (const el of [{ tagName: 'TEXTAREA' }, { tagName: 'SELECT' }, { tagName: 'INPUT', type: 'text' }, { tagName: 'INPUT', type: 'number' }, { tagName: 'DIV', isContentEditable: true }]) assert.equal(reload.isTextField(el), true, JSON.stringify(el));
  for (const el of [null, { tagName: 'BUTTON' }, { tagName: 'INPUT', type: 'checkbox' }, { tagName: 'INPUT', type: 'radio' }, { tagName: 'DIV' }]) assert.equal(reload.isTextField(el), false, JSON.stringify(el));
});

function page({ meta = 'b-old000', responses = [], scriptSrc = 'https://pmgpdc.au/pdc-auto-reload.js?v=x', pathname = '/', storage = new Map(), storageThrows = false } = {}) {
  let clock = 1000000, timerId = 0;
  const timers = new Map(), docEvents = new Map(), winEvents = new Map(), versionRequests = [], reloads = [];
  let active = null, dialogs = [];
  const doc = {
    currentScript: { src: scriptSrc },
    get activeElement() { return active; },
    querySelector: selector => selector === 'meta[name="pdc-build"]' && meta ? { getAttribute: () => meta } : null,
    querySelectorAll: () => dialogs,
    addEventListener: (name, fn) => docEvents.set(name, [...(docEvents.get(name) || []), fn])
  };
  const sessionStorage = {
    getItem: key => { if (storageThrows) throw new Error('blocked'); return storage.has(key) ? storage.get(key) : null; },
    setItem: (key, value) => { if (storageThrows) throw new Error('blocked'); storage.set(key, String(value)); },
    removeItem: key => storage.delete(key)
  };
  const pending = [];
  const win = {
    document: doc, sessionStorage, navigator: { onLine: true },
    location: { href: 'https://pmgpdc.au' + pathname, pathname, reload: () => reloads.push(clock) },
    setTimeout: (fn, ms) => { timers.set(++timerId, { fn, at: clock + ms }); return timerId; },
    clearTimeout: id => timers.delete(id),
    addEventListener: (name, fn) => winEvents.set(name, [...(winEvents.get(name) || []), fn]),
    dispatchEvent: event => { for (const fn of winEvents.get(event.type) || []) fn(event); return !event.defaultPrevented; },
    Event: class { constructor(type, init = {}) { this.type = type; this.cancelable = !!init.cancelable; this.defaultPrevented = false; } preventDefault() { if (this.cancelable) this.defaultPrevented = true; } },
    fetch(url, init = {}) {
      if (String(url).includes('version.json')) {
        versionRequests.push({ url: String(url), init });
        const next = responses.length ? responses.shift() : { status: 404 };
        if (next instanceof Error) return Promise.reject(next);
        return Promise.resolve({ ok: next.status === undefined || next.status === 200, text: async () => next.body });
      }
      let resolve; const p = new Promise(r => { resolve = r; }); pending.push(resolve); return p;
    }
  };
  vm.runInNewContext(code, { window: win, URL, Promise, Date: { now: () => clock } });
  return {
    win, storage, versionRequests, reloads, pending, docEvents, winEvents,
    api: win.PDCAutoReload,
    focus(el) { active = el; }, openDialog(open) { dialogs = open ? [{ hidden: false, closest: () => null, getClientRects: () => [{}] }] : []; },
    type() { for (const fn of docEvents.get('keydown') || []) fn({}); },
    async advance(ms) {
      const until = clock + ms;
      for (;;) {
        const due = [...timers.entries()].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]); clock = Math.max(clock, due[1].at); due[1].fn(); await flush();
      }
      clock = until; await flush();
    },
    nextTimerIn: () => Math.min(...[...timers.values()].map(t => t.at - clock))
  };
}
const version = build => ({ body: JSON.stringify({ build }) });

test('browser: polls no-store version.json every 60 s and reloads once on a new build', async () => {
  const p = page({ responses: [version('b-old000'), version('b-new000')] });
  assert.equal(p.nextTimerIn(), 60000);
  await p.advance(60000);
  assert.equal(p.reloads.length, 0);
  assert.match(p.versionRequests[0].url, /^https:\/\/pmgpdc\.au\/version\.json\?t=\d+$/);
  assert.equal(p.versionRequests[0].init.cache, 'no-store');
  await p.advance(60000);
  assert.equal(p.reloads.length, 1);
  assert.equal(p.storage.get('pdc.auto-reload.v1:/'), 'b-new000');
});

test('browser: after the reload the loop guard stops a second reload if the page is still old', async () => {
  const storage = new Map([['pdc.auto-reload.v1:/', 'b-new000']]);
  const p = page({ storage, responses: [version('b-new000'), version('b-new000')] });
  await p.advance(120000);
  assert.equal(p.reloads.length, 0);
  assert.equal(p.api.status().last.reason, 'loop-guard');
  const fresh = page({ meta: 'b-new000', storage, responses: [version('b-new000')] });
  assert.equal(storage.has('pdc.auto-reload.v1:/'), false, 'a page that reached the new build clears its guard');
  await fresh.advance(60000);
  assert.equal(fresh.reloads.length, 0);
});

test('browser: a focused field, recent typing or an open dialog defers until idle', async () => {
  const p = page({ responses: [version('b-new000')] });
  p.focus({ tagName: 'TEXTAREA' }); p.openDialog(true);
  await p.advance(60000);
  assert.equal(p.reloads.length, 0);
  assert.equal(p.api.status().last.action, 'defer');
  p.focus(null);
  await p.advance(4000);
  assert.equal(p.api.status().last.reason, 'modal-open');
  p.openDialog(false); p.type();
  await p.advance(6000);
  assert.equal(p.api.status().last.reason, 'recent-typing');
  assert.equal(p.reloads.length, 0);
  await p.advance(6000);
  assert.equal(p.reloads.length, 1, 'reloads about 10 s after the last key press');
});

test('browser: page unsaved-work rules (beforeunload) and saves in flight defer the reload', async () => {
  const p = page({ responses: [version('b-new000')] });
  let drafts = 1;
  p.win.addEventListener('beforeunload', e => { if (drafts) { e.preventDefault(); e.returnValue = ''; } });
  const save = p.win.fetch('https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/save', { method: 'POST' });
  p.win.fetch('https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/read');
  assert.equal(p.api.status().writesInFlight, 1, 'only writes are counted');
  await p.advance(60000);
  assert.equal(p.api.status().last.reason, 'saving');
  p.pending[0]({ ok: true }); await save; await flush();
  await p.advance(2000);
  assert.equal(p.api.status().last.reason, 'unsaved');
  drafts = 0;
  await p.advance(2000);
  assert.equal(p.reloads.length, 1);
});

test('browser: fetch errors, 404 and malformed bodies never reload and back off', async () => {
  const p = page({ responses: [new Error('offline'), { status: 404 }, { body: 'not json' }, { body: '{"build":""}' }] });
  await p.advance(60000); assert.equal(p.nextTimerIn(), 120000);
  await p.advance(120000); assert.equal(p.nextTimerIn(), 240000);
  await p.advance(240000); assert.equal(p.nextTimerIn(), 480000);
  await p.advance(480000); assert.equal(p.nextTimerIn(), 900000);
  assert.equal(p.reloads.length, 0);
  assert.equal(p.api.status().failures, 4);
});

test('browser: no session storage means no reload (cannot guard against loops)', async () => {
  const p = page({ storageThrows: true, responses: [version('b-new000')] });
  await p.advance(60000);
  assert.equal(p.reloads.length, 0);
});

test('browser: a page without the build tag uses its first answer as the baseline; sales resolves the root version.json', async () => {
  const p = page({ meta: null, scriptSrc: 'https://pmgpdc.au/pdc-auto-reload.js?v=x', pathname: '/sales/', responses: [version('b-old000'), version('b-new000')] });
  await p.advance(60000);
  assert.equal(p.reloads.length, 0);
  assert.match(p.versionRequests[0].url, /^https:\/\/pmgpdc\.au\/version\.json\?/);
  await p.advance(60000);
  assert.equal(p.reloads.length, 1);
  assert.equal(p.storage.get('pdc.auto-reload.v1:/sales/'), 'b-new000');
});

test('browser: coming back to the tab checks straight away (throttled to once per 15 s)', async () => {
  const p = page({ responses: [version('b-new000')] });
  await p.advance(20000);
  for (const fn of p.docEvents.get('visibilitychange')) fn();
  await p.advance(0);
  assert.equal(p.versionRequests.length, 1);
  assert.equal(p.reloads.length, 1);
});

test('wiring: board, Sales and the guide load the script once, before Supabase and not deferred; Karratha does not', () => {
  const board = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  const sales = fs.readFileSync(path.join(__dirname, 'sales/index.html'), 'utf8');
  const guide = fs.readFileSync(path.join(__dirname, 'docs/bus4x4-user-guide.html'), 'utf8');
  assert.equal(board.split('<script src="' + TAG + '"></script>').length, 2);
  assert.ok(board.indexOf(TAG) < board.indexOf('vendor/supabase/'), 'board: before Supabase so its saves are counted');
  assert.ok(board.indexOf(TAG) < board.indexOf('</head>'));
  assert.equal(sales.split('<script src="../' + TAG + '"></script>').length, 2);
  assert.ok(sales.indexOf(TAG) < sales.indexOf('vendor/supabase/'));
  assert.equal(guide.split('<script src="../' + TAG + '"></script>').length, 2);
  assert.equal(fs.readFileSync(path.join(__dirname, 'karratha/index.html'), 'utf8').includes('pdc-auto-reload'), false);
  assert.ok(builder.RUNTIME_FILES.includes('pdc-auto-reload.js'));
  assert.equal(builder.RUNTIME_FILES.includes('version.json'), false, 'version.json is generated, not a source file');
  assert.equal(/fetch\s*\(|\.rpc\(/.test(code.replace(/nativeFetch\.(?:apply|call)\(/g, '')), false, 'the script never calls the database');
});

test('build: version.json and page tags share one content build id; unchanged bytes keep it, changed bytes move it', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-r441-'));
  const src = path.join(tmp, 'src');
  for (const filename of builder.RUNTIME_FILES) { fs.mkdirSync(path.dirname(path.join(src, filename)), { recursive: true }); fs.copyFileSync(path.join(__dirname, filename), path.join(src, filename)); }
  try {
    const a = builder.buildRuntimeArtifact(src, path.join(tmp, 'a'));
    const b = builder.buildRuntimeArtifact(src, path.join(tmp, 'b'));
    assert.match(a.build, /^b-[0-9a-f]{20}$/);
    assert.equal(a.build, b.build, 'deterministic');
    const body = JSON.parse(fs.readFileSync(path.join(tmp, 'a', 'version.json'), 'utf8'));
    assert.equal(reload.parseVersion(body), a.build);
    assert.deepEqual(Object.keys(body).filter(k => k !== 'commit'), ['build']);
    for (const pageFile of builder.BUILD_TAGGED_PAGES) assert.ok(fs.readFileSync(path.join(tmp, 'a', pageFile), 'utf8').includes('<meta name="pdc-build" content="' + a.build + '">'), pageFile);
    assert.equal(fs.readFileSync(path.join(tmp, 'a', 'karratha/index.html'), 'utf8').includes('pdc-build'), false);
    fs.appendFileSync(path.join(src, 'sales/sales.css'), '\n/* r441 fixture change */\n');
    assert.notEqual(builder.buildRuntimeArtifact(src, path.join(tmp, 'c')).build, a.build);
    assert.deepEqual(JSON.parse(builder.versionFile('b-abcdef', { GITHUB_SHA: 'a'.repeat(40) })), { build: 'b-abcdef', commit: 'a'.repeat(12) });
    assert.deepEqual(JSON.parse(builder.versionFile('b-abcdef', { GITHUB_SHA: 'not-a-sha' })), { build: 'b-abcdef' });
    const sales = path.join(src, 'sales/index.html'), before = fs.readFileSync(sales, 'utf8');
    fs.writeFileSync(sales, before.replace('<script src="../' + TAG + '"></script>', ''));
    assert.throws(() => builder.validateRuntime(src), /Auto-reload script must be included exactly once: sales\/index\.html/);
    fs.writeFileSync(sales, before.replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta name="pdc-build" content="b-fixture">'));
    assert.throws(() => builder.validateRuntime(src), /Build tag must be added by the build/);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});

test('FAULT_LOG records F52 with its root cause', () => {
  const log = fs.readFileSync(path.join(__dirname, 'docs/FAULT_LOG.md'), 'utf8');
  const row = log.split('\n').find(line => line.startsWith('| F52 |'));
  assert.ok(row, 'F52 row');
  assert.match(row, /version check/i);
  assert.match(row, /test_auto_reload_after_release_441\.js/);
});
