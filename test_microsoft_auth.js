'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const authSource = fs.readFileSync(path.join(root, 'pdc-auth.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const configExample = fs.readFileSync(path.join(root, 'pdc-supabase-config.example.js'), 'utf8');
const vendor = fs.readFileSync(path.join(root, 'vendor', 'supabase', 'supabase-2.110.5.js'), 'utf8');

assert.ok(index.includes('<body class="auth-pending"'), 'Production shell must start locked');
assert.ok(index.includes('id="app-shell" inert aria-hidden="true"'), 'Production application must be inert before authorization');
assert.ok(index.includes('id="pdc-password-form"'), 'Temporary individual email/password form is missing');
assert.ok(index.includes('id="pdc-new-password-form"'), 'Invite and recovery password-setup form is missing');
assert.ok(index.includes('autocomplete="username"') && index.includes('autocomplete="current-password"'), 'Login fields need password-manager-compatible autocomplete values');
assert.ok(index.includes('id="pdc-auth-signout"'), 'Sign-out action is missing');
assert.ok(index.indexOf('vendor/supabase/supabase-2.110.5.js') < index.indexOf('pdc-auth.js'), 'Supabase client must load before the auth gate');
assert.ok(index.indexOf('pdc-supabase-config.js') < index.indexOf('pdc-auth.js'), 'Browser config must load before the auth gate');
assert.ok(index.indexOf('pdc-auth.js') < index.indexOf('app.js'), 'Auth gate must initialize before application code');
assert.ok(vendor.includes('supabase') && vendor.length > 150000, 'Pinned Supabase browser bundle is missing or incomplete');
assert.ok(configExample.includes("provider: 'azure'"), 'Microsoft/Azure must be the configured provider');
assert.ok(configExample.includes("mode: 'password'"), 'Temporary production login mode should be individual email/password');
assert.ok(!authSource.includes('URLSearchParams') && !authSource.includes('AUTH_BYPASS'), 'Production auth must not support a query-string bypass');
assert.ok(authSource.includes('signInWithPassword({ email, password })'), 'Email/password sign-in handler is missing');
assert.ok(authSource.includes('updateUser({ password })'), 'Invite and recovery flows must let staff establish a private password');
assert.ok(authSource.includes("event === 'PASSWORD_RECOVERY'"), 'Password recovery sessions must remain inside the password-setup gate');
assert.ok(!authSource.includes('.signUp('), 'The production browser must not expose public account registration');
assert.ok(authSource.includes("scopes: 'email'"), 'Azure OAuth must request the email scope required by Supabase');
assert.ok(authSource.includes(".from('pdc_user_roles')"), 'Authorization must check the protected PDC role table');
assert.ok(authSource.indexOf(".from('pdc_user_roles')") < authSource.indexOf('unlockApplication(session, role)'), 'Role authorization must occur before unlocking the app');

let domReadyHandler = null;
const context = {
  console,
  URL,
  Set,
  Object,
  String,
  Boolean,
  Error,
  Promise,
  CustomEvent: function CustomEvent(type, init) { this.type = type; this.detail = init?.detail; },
  window: {
    location: {
      origin: 'http://localhost:8765',
      pathname: '/index.html',
    },
    addEventListener() {},
    dispatchEvent() {},
    setTimeout,
  },
  document: {
    readyState: 'loading',
    addEventListener(type, handler) { if (type === 'DOMContentLoaded') domReadyHandler = handler; },
    getElementById() { return null; },
    body: {
      dataset: {},
      classList: { add() {}, remove() {} },
    },
  },
  setTimeout,
};
context.globalThis = context;
vm.createContext(context);
vm.runInContext(authSource, context, { filename: 'pdc-auth.js' });

assert.strictEqual(typeof domReadyHandler, 'function', 'Auth initialization should wait for the DOM');
const helpers = context.window.PDC_AUTH_TEST;
assert.ok(helpers.approvedRole({ email: 'staff@example.com', role: 'operator', active: true }, 'STAFF@example.com'), 'Approved roles should be case-insensitive by email');
assert.ok(!helpers.approvedRole({ email: 'staff@example.com', role: 'operator', active: false }, 'staff@example.com'), 'Inactive staff must be denied');
assert.ok(!helpers.approvedRole({ email: 'staff@example.com', role: 'owner', active: true }, 'staff@example.com'), 'Unknown roles must be denied');
assert.ok(!helpers.approvedRole({ email: 'other@example.com', role: 'administrator', active: true }, 'staff@example.com'), 'Mismatched email must be denied');
assert.strictEqual(helpers.safeRedirectTo('https://evil.example/login'), 'http://localhost:8765/index.html', 'OAuth redirect must stay on the current origin');
assert.strictEqual(helpers.safeRedirectTo('/index.html'), 'http://localhost:8765/index.html', 'Same-origin OAuth redirect should be accepted');

async function testAuthGenerationOwnership() {
  const instrumented = authSource.replace(
    /\}\)\(\);\s*$/,
    'window.__PDC_AUTH_INTERNALS = { state, applySession, handleOwnRoleRowChanged };\n})();'
  );
  const events = [];
  const body = { dataset: {}, classList: { add() {}, remove() {} } };
  const raceContext = {
    console, URL, Set, Object, String, Boolean, Error, Promise,
    CustomEvent: function CustomEvent(type, init) { this.type = type; this.detail = init?.detail; },
    window: {
      location: { origin: 'http://localhost:8765', pathname: '/index.html', search: '', hash: '' },
      addEventListener() {},
      dispatchEvent(event) { events.push(event); },
      setTimeout,
    },
    document: {
      readyState: 'loading',
      addEventListener() {},
      getElementById() { return null; },
      body,
    },
    setTimeout,
  };
  raceContext.globalThis = raceContext;
  vm.createContext(raceContext);
  vm.runInContext(instrumented, raceContext, { filename: 'pdc-auth-race.js' });
  const internals = raceContext.window.__PDC_AUTH_INTERNALS;
  const roleResponses = [];
  const client = {
    from() {
      return {
        select() { return this; },
        eq() { return this; },
        maybeSingle() {
          const response = roleResponses.shift();
          if (!response) throw new Error('missing role response');
          return response;
        },
      };
    },
    channel() { return { on() { return this; }, subscribe() { return this; } }; },
    removeChannel() {},
    rpc() { return Promise.resolve({}); },
  };
  internals.state.client = client;
  const session = {
    access_token: 'session-a-token',
    user: { id: 'A', email: 'a@example.com', user_metadata: {} },
  };
  const approved = role => ({ data: { email: 'a@example.com', role, active: true, account_status: 'approved' }, error: null });
  const deferred = () => {
    let resolve;
    const promise = new Promise(r => { resolve = r; });
    return { promise, resolve };
  };

  // An older session validation must not unlock after a newer sign-out.
  const staleSessionRole = deferred();
  roleResponses.push(staleSessionRole.promise);
  const staleApply = internals.applySession(session);
  await internals.applySession(null);
  staleSessionRole.resolve(approved('operator'));
  await staleApply;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'stale session validation must not restore auth context after sign-out');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'stale session validation must not recache an old JWT');
  assert.strictEqual(internals.state.session, null, 'signed-out session remains authoritative');

  // Concurrent own-row lookups are last-started-wins, even when the older
  // elevated result completes after a newer demotion.
  roleResponses.push(Promise.resolve(approved('operator')));
  await internals.applySession(session);
  const olderAdmin = deferred();
  const newerViewer = deferred();
  roleResponses.push(olderAdmin.promise, newerViewer.promise);
  const oldLookup = internals.handleOwnRoleRowChanged();
  const newLookup = internals.handleOwnRoleRowChanged();
  newerViewer.resolve(approved('viewer'));
  await newLookup;
  olderAdmin.resolve(approved('administrator'));
  await oldLookup;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.role, 'viewer', 'older elevated role lookup must not overwrite newer demotion');
  assert.strictEqual(internals.state.role.role, 'viewer', 'internal role authority must remain at newest lookup');
  assert.ok(events.some(event => event.type === 'pdc-auth-ready' && event.detail?.role === 'viewer'), 'newest demotion must publish auth-ready');
}

testAuthGenerationOwnership().then(() => {
  console.log('PDC authentication gate and generation-race checks passed');
}).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
