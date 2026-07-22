'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const authSource = fs.readFileSync(path.join(root, 'pdc-auth.js'), 'utf8');
const registrationSource = fs.readFileSync(path.join(root, 'pdc-auth-registration.js'), 'utf8');
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
assert.ok(registrationSource.includes('beginProviderOperation()') && registrationSource.includes('completeProviderOperation(providerGeneration'), 'staging registration session results must be provider-generation-owned');
assert.ok(authSource.includes("scopes: 'email'"), 'Azure OAuth must request the email scope required by Supabase');
assert.ok(authSource.includes(".from('pdc_user_roles')"), 'Authorization must check the protected PDC role table');
const roleHandlerStart = authSource.indexOf('async function handleOwnRoleRowChanged()');
assert.ok(authSource.indexOf('await loadApprovedRole(session)', roleHandlerStart) < authSource.indexOf('unlockApplication(session, role,', roleHandlerStart), 'Role authorization must occur before unlocking the app');

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
    'window.__PDC_AUTH_INTERNALS = { state, applySession, handleOwnRoleRowChanged, beginProviderSessionOperation, completeProviderSessionOperation, signInWithPassword, signOut, initialize };\n})();'
  );
  const events = [];
  const lockedObservations = [];
  const nodes = {
    'pdc-login-email': { value: '' },
    'pdc-login-password': { value: '' },
    'pdc-password-login': { disabled: false },
  };
  const body = { dataset: {}, classList: { add() {}, remove() {} } };
  const raceContext = {
    console, URL, Set, Object, String, Boolean, Error, Promise,
    CustomEvent: function CustomEvent(type, init) { this.type = type; this.detail = init?.detail; },
    window: {
      location: { origin: 'http://localhost:8765', pathname: '/index.html', search: '', hash: '' },
      addEventListener() {},
      dispatchEvent(event) {
        events.push(event);
        if (event.type === 'pdc-auth-locked') {
          const current = raceContext.window.__PDC_AUTH_INTERNALS?.state;
          lockedObservations.push({
            context: raceContext.window.PDC_AUTH_CONTEXT,
            token: raceContext.window.__pdcCachedAccessToken,
            session: current?.session,
            role: current?.role,
          });
        }
      },
      setTimeout,
      clearTimeout,
    },
    document: {
      readyState: 'loading',
      addEventListener() {},
      getElementById(id) { return nodes[id] || null; },
      body,
    },
    setTimeout,
  };
  raceContext.globalThis = raceContext;
  vm.createContext(raceContext);
  vm.runInContext(instrumented, raceContext, { filename: 'pdc-auth-race.js' });
  const internals = raceContext.window.__PDC_AUTH_INTERNALS;
  const roleResponses = [];
  const roleChannels = [];
  let failChannelCreation = false;
  let autoSubscribe = true;
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
    channel() {
      if (failChannelCreation) throw new Error('role channel unavailable');
      return {
        change: null,
        status: null,
        on(_type, _filter, callback) { this.change = callback; return this; },
        subscribe(callback) {
          this.status = callback;
          roleChannels.push(this);
          if (autoSubscribe) callback('SUBSCRIBED');
          return this;
        },
      };
    },
    removeChannel() {},
    rpc() { return Promise.resolve({}); },
    auth: { signOut() { return Promise.resolve({}); } },
  };
  internals.state.client = client;
  const session = {
    access_token: 'session-a-token',
    user: { id: 'A', email: 'a@example.com', user_metadata: {} },
  };
  const approvedFor = (email, role) => ({ data: { email, role, active: true, account_status: 'approved' }, error: null });
  const approved = role => approvedFor('a@example.com', role);
  const deferred = () => {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
    return { promise, resolve, reject };
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

  // A newer live-row demotion must also supersede an older applySession role
  // result, not only another live-row lookup.
  const mixedOldAdmin = deferred();
  const mixedNewViewer = deferred();
  roleResponses.push(mixedOldAdmin.promise, mixedNewViewer.promise);
  const mixedApply = internals.applySession(session);
  const mixedLookup = internals.handleOwnRoleRowChanged();
  mixedNewViewer.resolve(approved('viewer'));
  await mixedLookup;
  mixedOldAdmin.resolve(approved('administrator'));
  await mixedApply;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.role, 'viewer', 'newer live demotion supersedes older applySession elevation');
  assert.strictEqual(internals.state.role.role, 'viewer', 'mixed async ordering retains newest database role');

  // signOut() must revoke local authority before provider transport settles,
  // and a transport rejection must never restore it.
  const staleDuringSignOut = deferred();
  const remoteSignOut = deferred();
  roleResponses.push(staleDuringSignOut.promise);
  const staleDuringSignOutApply = internals.applySession(session);
  client.auth.signOut = () => remoteSignOut.promise;
  const pendingSignOut = internals.signOut();
  staleDuringSignOut.resolve(approved('administrator'));
  await staleDuringSignOutApply;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'sign-out revokes context before remote transport completes');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'sign-out clears cached token before remote transport completes');
  assert.strictEqual(internals.state.session, null, 'sign-out clears local session immediately');
  remoteSignOut.resolve({ error: null });
  await pendingSignOut;

  roleResponses.push(Promise.resolve(approved('operator')));
  await internals.applySession(session);
  client.auth.signOut = () => Promise.reject(new Error('transport unavailable'));
  await internals.signOut();
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'rejected remote sign-out remains locally locked');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'rejected remote sign-out cannot retain cached token');
  assert.strictEqual(internals.state.session, null, 'rejected remote sign-out cannot retain session authority');

  // Rejected role revalidation and loss of its authoritative Realtime
  // monitor both fail closed rather than retaining previously rendered data.
  roleResponses.push(Promise.resolve(approved('operator')));
  await internals.applySession(session);
  roleResponses.push(Promise.reject(new Error('role query transport failed')));
  await internals.handleOwnRoleRowChanged();
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'rejected own-role query revokes context');
  assert.strictEqual(internals.state.session, null, 'rejected own-role query revokes session');

  const readyBeforeSubscriptionProof = events.filter(event => event.type === 'pdc-auth-ready').length;
  autoSubscribe = false;
  roleResponses.push(Promise.resolve(approved('operator')));
  const pendingMonitorApply = internals.applySession(session);
  await new Promise(resolve => setImmediate(resolve));
  const pendingRoleChannel = roleChannels[roleChannels.length - 1];
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'authority is not published before SUBSCRIBED');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'token is not cached before SUBSCRIBED');
  assert.strictEqual(internals.state.session, null, 'session authority is not installed before SUBSCRIBED');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-ready').length, readyBeforeSubscriptionProof, 'ready event waits for SUBSCRIBED');
  pendingRoleChannel.status('TIMED_OUT');
  await pendingMonitorApply;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'pre-subscription timeout remains locked');

  roleResponses.push(Promise.resolve(approved('operator')));
  const delayedSubscribedApply = internals.applySession(session);
  await new Promise(resolve => setImmediate(resolve));
  const delayedRoleChannel = roleChannels[roleChannels.length - 1];
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'delayed monitor still withholds authority');
  delayedRoleChannel.status('SUBSCRIBED');
  await delayedSubscribedApply;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'A', 'fresh SUBSCRIBED proof permits authority publication');
  autoSubscribe = true;

  const currentRoleChannel = roleChannels[roleChannels.length - 1];
  currentRoleChannel.status('CHANNEL_ERROR');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'role-monitor channel loss revokes context');
  assert.strictEqual(internals.state.session, null, 'role-monitor channel loss revokes session');

  const readyBeforeMonitorFailure = events.filter(event => event.type === 'pdc-auth-ready').length;
  roleResponses.push(Promise.resolve(approved('operator')));
  failChannelCreation = true;
  await internals.applySession(session);
  failChannelCreation = false;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'initial role-monitor failure prevents unlock');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-ready').length, readyBeforeMonitorFailure, 'initial monitor failure publishes no ready event');

  // Provider requests are intent-generation-owned before their first await.
  // An old login cannot reverse a newer explicit sign-out.
  const staleProviderLogin = deferred();
  client.auth.signInWithPassword = () => staleProviderLogin.promise;
  client.auth.signOut = () => Promise.resolve({ error: null });
  nodes['pdc-login-email'].value = 'a@example.com';
  nodes['pdc-login-password'].value = 'Secret!Password1';
  const staleLogin = internals.signInWithPassword({ preventDefault() {} });
  await Promise.resolve();
  await internals.signOut();
  staleProviderLogin.resolve({ data: { session }, error: null });
  await staleLogin;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'stale provider login cannot reverse sign-out');
  assert.strictEqual(internals.state.session, null, 'stale provider login cannot restore old session');

  // Overlapping provider logins are last-started-wins across different users.
  const loginA = deferred();
  const loginB = deferred();
  const loginResponses = [loginA.promise, loginB.promise];
  client.auth.signInWithPassword = () => loginResponses.shift();
  nodes['pdc-login-email'].value = 'a@example.com';
  nodes['pdc-login-password'].value = 'Secret!Password1';
  const olderLogin = internals.signInWithPassword({ preventDefault() {} });
  await Promise.resolve();
  nodes['pdc-login-email'].value = 'b@example.com';
  nodes['pdc-login-password'].value = 'Secret!Password2';
  const newerLogin = internals.signInWithPassword({ preventDefault() {} });
  await Promise.resolve();
  const sessionB = { access_token: 'session-b-token', user: { id: 'B', email: 'b@example.com', user_metadata: {} } };
  roleResponses.push(Promise.resolve(approvedFor('b@example.com', 'viewer')));
  loginB.resolve({ data: { session: sessionB }, error: null });
  await newerLogin;
  loginA.resolve({ data: { session }, error: null });
  await olderLogin;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'B', 'newer provider login owns final user authority');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.role, 'viewer', 'newer provider login owns final role authority');
  assert.strictEqual(internals.state.session, sessionB, 'older provider completion cannot replace newer session');

  // Initial saved-session discovery is subordinate to provider events that
  // occur while getSession() is unresolved.
  const initialSession = deferred();
  let authStateCallback = null;
  const startupClient = {
    ...client,
    auth: {
      getSession: () => initialSession.promise,
      onAuthStateChange(callback) { authStateCallback = callback; return { data: { subscription: {} } }; },
      signOut: () => Promise.resolve({ error: null }),
    },
  };
  raceContext.window.PDC_SUPABASE_CONFIG = { url: 'https://staging.example', publishableKey: 'public-test-key', auth: { mode: 'password' } };
  raceContext.window.supabase = { createClient: () => startupClient };
  const initialization = internals.initialize();
  assert.strictEqual(typeof authStateCallback, 'function', 'auth event listener registers before saved-session discovery resolves');
  authStateCallback('SIGNED_OUT', null);
  await new Promise(resolve => setTimeout(resolve, 0));
  initialSession.resolve({ data: { session }, error: null });
  await initialization;
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'stale initial getSession cannot reverse newer sign-out event');
  assert.strictEqual(internals.state.session, null, 'newer provider event owns startup session authority');
  authStateCallback('SIGNED_IN', session);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'late provider SIGNED_IN event cannot cross signed-out intent barrier');
  assert.strictEqual(internals.state.session, null, 'late provider event cannot restore a blocked session');

  const explicitBGeneration = internals.beginProviderSessionOperation();
  assert.ok(internals.completeProviderSessionOperation(explicitBGeneration, sessionB), 'explicit replacement session claims its provider generation');
  roleResponses.push(Promise.resolve(approvedFor('b@example.com', 'viewer')));
  await internals.applySession(sessionB);
  authStateCallback('SIGNED_IN', session);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'B', 'late different-user provider event cannot replace explicit newer user');
  assert.strictEqual(internals.state.session, sessionB, 'explicit newer user remains pinned against stale provider event');

  assert.ok(lockedObservations.length > 0, 'lockout observations were captured');
  for (const observation of lockedObservations) {
    assert.strictEqual(observation.context, undefined, 'lock listener cannot synchronously read prior context');
    assert.strictEqual(observation.token, undefined, 'lock listener cannot synchronously read prior token');
    assert.strictEqual(observation.session, null, 'lock listener cannot synchronously read prior session');
    assert.strictEqual(observation.role, null, 'lock listener cannot synchronously read prior role');
  }
}

testAuthGenerationOwnership().then(() => {
  console.log('PDC authentication gate and generation-race checks passed');
}).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
