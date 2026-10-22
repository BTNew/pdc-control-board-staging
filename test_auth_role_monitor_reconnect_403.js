/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r403 (F11): a realtime blip on the own-role monitor must not lock an approved
// user out. Reconnect with backoff, re-read the staff row, lock only on a real
// not-approved answer, and after a sustained outage show "Connection lost"
// with Retry instead of "Access not approved".
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('pdc-auth.js', 'utf8');
const EMAIL = 'tester@example.invalid';

function harness({ roles = [] } = {}) {
  let now = 1_000_000;
  let timerId = 0;
  const timers = new Map();
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) {
      const listeners = {};
      elements.set(id, {
        id, hidden: true, textContent: '', disabled: false, listeners,
        setAttribute() {}, removeAttribute() {},
        addEventListener(type, fn) { listeners[type] = fn; },
      });
    }
    return elements.get(id);
  };
  const channels = [];
  const roleReads = [];
  const roleQueue = roles.slice();
  let lastRole = { data: { email: EMAIL, role: 'administrator', active: true, account_status: 'approved' }, error: null };
  const session = { access_token: 't', user: { id: 'u1', email: EMAIL, user_metadata: { full_name: 'Tester' } } };
  const client = {
    auth: {
      onAuthStateChange() {},
      getSession: async () => ({ data: { session }, error: null }),
    },
    from(table) {
      assert.equal(table, 'pdc_user_roles');
      const chain = {
        select: () => chain, eq: () => chain,
        maybeSingle: async () => {
          roleReads.push(now);
          const next = roleQueue.length ? roleQueue.shift() : lastRole;
          if (next.throws) throw next.throws;
          lastRole = next.sticky ? next : lastRole;
          return { data: next.data ?? null, error: next.error ?? null };
        },
      };
      return chain;
    },
    channel(name) {
      const ch = { name, removed: false, statusCb: null, on() { return ch; }, subscribe(cb) { ch.statusCb = cb; return ch; } };
      channels.push(ch);
      return ch;
    },
    removeChannel(ch) { ch.removed = true; },
    rpc: () => Promise.resolve({}),
  };
  class FakeDate extends Date { static now() { return now; } }
  const events = [];
  const body = { dataset: {}, classList: { add() {}, remove() {} } };
  const window = {
    PDC_SUPABASE_CONFIG: { url: 'https://example.invalid', publishableKey: 'k', auth: { mode: 'password' } },
    supabase: { createClient: () => client },
    location: { search: '', hash: '', origin: 'https://example.invalid', pathname: '/', href: 'https://example.invalid/', replace() {} },
    setTimeout(fn, ms = 0) { const id = ++timerId; timers.set(id, { fn, at: now + ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    dispatchEvent(event) { events.push(event.type); return true; },
  };
  const document = {
    readyState: 'complete', body,
    getElementById: element,
    addEventListener() {},
  };
  const ctx = { window, document, Date: FakeDate, CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init?.detail; } }, URL, Promise, console };
  vm.createContext(ctx);
  vm.runInContext(source, ctx, { filename: 'pdc-auth.js' });
  const flush = async () => { for (let i = 0; i < 20; i += 1) await new Promise(resolve => setImmediate(resolve)); };
  async function advance(ms) {
    const end = now + ms;
    for (;;) {
      await flush();
      const due = [...timers.entries()].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      timers.delete(due[0]);
      now = Math.max(now, due[1].at);
      due[1].fn();
    }
    now = end;
    await flush();
  }
  const live = () => channels.filter(ch => !ch.removed).at(-1);
  return { window, body, element, channels, roleReads, advance, flush, live, events, setRole: r => { lastRole = r; } };
}

async function signedIn(h) {
  await h.flush();
  h.live().statusCb('SUBSCRIBED');
  await h.flush();
  assert.equal(h.body.dataset.authState, 'approved');
}

test('a closed own-role channel reconnects with backoff and re-checks the role instead of locking', async () => {
  const h = harness();
  await signedIn(h);
  const readsBefore = h.roleReads.length;
  h.live().statusCb('CLOSED');
  await h.flush();
  assert.equal(h.body.dataset.authState, 'approved', 'not locked on a blip');
  assert.equal(h.body.dataset.authMonitor, 'reconnecting');
  assert.equal(h.element('pdc-auth-title').textContent.includes('Access not approved'), false);
  await h.advance(999);
  assert.equal(h.channels.length, 1, 'waits for the first backoff step');
  await h.advance(1);
  assert.equal(h.channels.length, 2, 'resubscribes after 1 s');
  h.live().statusCb('TIMED_OUT');
  await h.advance(2000);
  assert.equal(h.channels.length, 3, 'second step is 2 s');
  h.live().statusCb('SUBSCRIBED');
  await h.flush();
  assert.equal(h.body.dataset.authMonitor, 'live');
  assert.equal(h.body.dataset.authState, 'approved');
  assert.ok(h.roleReads.length > readsBefore, 'staff row re-read after reconnect');
});

test('a revoke missed while disconnected locks on reconnect', async () => {
  const h = harness();
  await signedIn(h);
  h.live().statusCb('CHANNEL_ERROR');
  h.setRole({ data: { email: EMAIL, role: 'administrator', active: false, account_status: 'disabled' }, error: null });
  await h.advance(1000);
  h.live().statusCb('SUBSCRIBED');
  await h.flush();
  assert.equal(h.body.dataset.authState, 'account-disabled');
});

test('a sustained outage shows Connection lost with Retry, and Retry restores access', async () => {
  const h = harness();
  await signedIn(h);
  h.live().statusCb('CLOSED');
  for (let i = 0; i < 12 && h.body.dataset.authState === 'approved'; i += 1) {
    await h.advance(30000);
    const ch = h.live();
    if (ch && ch.statusCb) ch.statusCb('TIMED_OUT');
    await h.flush();
  }
  assert.equal(h.body.dataset.authState, 'connection-lost');
  assert.equal(h.element('pdc-auth-title').textContent, 'Connection lost');
  assert.equal(h.element('pdc-auth-retry').hidden, false, 'Retry shown');
  assert.equal(h.element('pdc-auth-denied-signout').hidden, false, 'sign-out still available');
  h.element('pdc-auth-retry').listeners.click();
  await h.flush();
  h.live().statusCb('SUBSCRIBED');
  await h.flush();
  assert.equal(h.body.dataset.authState, 'approved');
  assert.equal(h.element('pdc-auth-retry').hidden, true);
});

test('a transient role read error is retried; a definite error still locks', async () => {
  const h = harness();
  await signedIn(h);
  const ok = { data: { email: EMAIL, role: 'administrator', active: true, account_status: 'approved' }, error: null };
  // Live row event while the API is briefly failing.
  h.setRole(ok);
  const h2 = harness({ roles: [ok, { error: { message: 'upstream', status: 503 } }, { throws: new TypeError('Failed to fetch') }, ok] });
  await signedIn(h2);
  h2.live().statusCb('CLOSED');
  await h2.advance(1000);
  h2.live().statusCb('SUBSCRIBED');
  await h2.advance(10000);
  assert.equal(h2.body.dataset.authState, 'approved', 'retried past 503 and network error');
  const h3 = harness({ roles: [ok, { error: { message: 'permission denied', code: '42501' } }] });
  await signedIn(h3);
  h3.live().statusCb('CLOSED');
  await h3.advance(1000);
  h3.live().statusCb('SUBSCRIBED');
  await h3.advance(10000);
  assert.notEqual(h3.body.dataset.authState, 'approved', 'definite failure is not retried');
});

test('a monitor that never subscribes keeps the app locked and offers Retry, not "not approved"', async () => {
  const h = harness();
  await h.flush();
  h.live().statusCb('TIMED_OUT');
  await h.flush();
  assert.equal(h.body.dataset.authState, 'connection-lost');
  assert.equal(h.element('pdc-auth-retry').hidden, false);
});

test('index pages carry the Retry button', () => {
  for (const file of ['index.html', 'sales/index.html']) {
    assert.match(fs.readFileSync(file, 'utf8'), /id="pdc-auth-retry"[^>]*hidden>Retry</, file);
  }
});
