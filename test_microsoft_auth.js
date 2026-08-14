'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const authSource = fs.readFileSync(path.join(root, 'pdc-auth.js'), 'utf8');
const registrationSource = fs.readFileSync(path.join(root, 'pdc-auth-registration.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const productionConfig = fs.readFileSync(path.join(root, 'pdc-supabase-config.production.js'), 'utf8');
const vendor = fs.readFileSync(path.join(root, 'vendor', 'supabase', 'supabase-2.110.5.js'), 'utf8');

assert.ok(index.includes('<body class="auth-pending"'), 'Production shell must start locked');
assert.ok(index.includes('id="app-shell" inert aria-hidden="true"'), 'Production application must be inert before authorization');
assert.ok(index.includes('id="pdc-password-form"'), 'Temporary individual email/password form is missing');
assert.ok(index.includes('id="pdc-new-password-form"'), 'Invite and recovery password-setup form is missing');
assert.ok(index.includes('autocomplete="username"') && index.includes('autocomplete="current-password"'), 'Login fields need password-manager-compatible autocomplete values');
assert.ok(index.includes('id="pdc-auth-signout"'), 'Sign-out action is missing');
assert.ok(index.indexOf('vendor/supabase/supabase-2.110.5.js') < index.indexOf('pdc-auth.js'), 'Supabase client must load before the auth gate');
assert.ok(index.indexOf('pdc-supabase-config.production.js') < index.indexOf('pdc-auth.js'), 'Tracked production browser config must load before the auth gate');
assert.ok(index.indexOf('pdc-auth.js') < index.indexOf('app.js'), 'Auth gate must initialize before application code');
assert.ok(vendor.includes('supabase') && vendor.length > 150000, 'Pinned Supabase browser bundle is missing or incomplete');
assert.ok(productionConfig.includes("provider: 'azure'"), 'Microsoft/Azure must be the configured provider');
assert.ok(productionConfig.includes("mode: 'password'"), 'Temporary production login mode should be individual email/password');
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
    'window.__PDC_AUTH_INTERNALS = { state, applySession, handleOwnRoleRowChanged, beginProviderSessionOperation, completeProviderSessionOperation, signInWithPassword, saveNewPassword, signOut, initialize };\n})();'
  );
  const events = [];
  const lockedObservations = [];
  let historyReplacements = 0;
  let serviceStops = 0;
  const nodes = {
    'pdc-login-email': { value: '' },
    'pdc-login-password': { value: '' },
    'pdc-password-login': { disabled: false },
    'pdc-new-password': { value: '' },
    'pdc-confirm-password': { value: '' },
    'pdc-save-password': { disabled: false },
  };
  const body = { dataset: {}, classList: { add() {}, remove() {} } };
  const raceContext = {
    console, URL, Set, Object, String, Boolean, Error, Promise,
    CustomEvent: function CustomEvent(type, init) { this.type = type; this.detail = init?.detail; },
    window: {
      location: { origin: 'http://localhost:8765', pathname: '/index.html', search: '', hash: '' },
      history: { replaceState() { historyReplacements += 1; } },
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
      stopWorkshopReferenceDataReconciliationTimer() { serviceStops += 1; },
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
  let roleQueryCount = 0;
  let failChannelCreation = false;
  let autoSubscribe = true;
  const client = {
    from() {
      return {
        select() { return this; },
        eq() { return this; },
        maybeSingle() {
          roleQueryCount += 1;
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

  // Recovery/invite sessions may drive the isolated password-update form but
  // must not become application, token, role, or monitor authority.
  const recoverySession = {
    access_token: 'RECOVERY_SECRET',
    user: { id: 'R', email: 'recovery@example.com', user_metadata: {} },
  };
  const channelsBeforeRecovery = roleChannels.length;
  internals.state.passwordSetupRequired = true;
  await internals.applySession(recoverySession);
  assert.strictEqual(internals.state.session, null, 'recovery session is not published as application authority');
  assert.strictEqual(internals.state.user, null, 'recovery user is not published as application authority');
  assert.strictEqual(internals.state.validatingSession, null, 'recovery session is not retained as a role-validation session');
  assert.strictEqual(internals.state.passwordSetupUserId, 'R', 'recovery form retains only the expected user identity');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'recovery path publishes no auth context');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'recovery path caches no token');
  assert.strictEqual(roleChannels.length, channelsBeforeRecovery, 'recovery path creates no operational role monitor before password completion');
  nodes['pdc-new-password'].value = 'Strong!Password123';
  nodes['pdc-confirm-password'].value = 'Strong!Password123';
  client.auth.updateUser = () => Promise.resolve({ data: { user: recoverySession.user }, error: null });
  client.auth.getSession = () => Promise.resolve({ data: { session: recoverySession }, error: null });
  roleResponses.push(Promise.resolve(approvedFor('recovery@example.com', 'operator')));
  await internals.saveNewPassword({ preventDefault() {} });
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT?.userId, 'R', 'completed recovery publishes authority only after fresh role and monitor proof');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, 'RECOVERY_SECRET', 'completed recovery caches the token only after monitored unlock');
  await internals.applySession(null);

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

  // Silent refresh for the already-authorized same user must update only the
  // token/session. It must not tear down authority or recreate the required
  // own-role monitor, which can otherwise leave a healthy long-lived tab
  // stuck on the access-check overlay if channel resubscription is delayed.
  const refreshAuthGeneration = internals.state.authGeneration;
  const refreshRoleChannel = internals.state.ownRoleChannel;
  const refreshLockCount = lockedObservations.length;
  const refreshTokenEventCount = events.filter(event => event.type === 'pdc-auth-token-changed').length;
  const refreshedSessionB = { ...sessionB, access_token: 'session-b-refreshed-token' };
  roleResponses.push(Promise.resolve(approvedFor('b@example.com', 'viewer')));
  authStateCallback('TOKEN_REFRESHED', refreshedSessionB);
  await new Promise(resolve => setTimeout(resolve, 0));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(internals.state.session, refreshedSessionB, 'same-user token refresh publishes the replacement session');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, 'session-b-refreshed-token', 'same-user token refresh updates the cached access token');
  assert.strictEqual(internals.state.authGeneration, refreshAuthGeneration, 'same-user token refresh does not revoke/revalidate authority');
  assert.strictEqual(internals.state.ownRoleChannel, refreshRoleChannel, 'same-user token refresh retains the proven own-role monitor');
  assert.strictEqual(lockedObservations.length, refreshLockCount, 'same-user token refresh emits no authority lock event');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-token-changed').length, refreshTokenEventCount + 1, 'same-user token refresh synchronously publishes token-bound authority invalidation');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-token-changed').at(-1)?.detail?.reason, 'token-refreshed', 'token refresh event exposes only a non-secret reason');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'B', 'same-user token refresh retains approved context');

  // Supabase also emits SIGNED_IN for an already-signed-in user when a tab
  // returns to the foreground. This is session continuity, not a new login:
  // retain the already-proven role/context/monitor and update only the fresh
  // session, user, and token authority surfaces.
  const foregroundAuthGeneration = internals.state.authGeneration;
  const foregroundRoleChannel = internals.state.ownRoleChannel;
  const foregroundRoleQueryCount = roleQueryCount;
  const foregroundChannelCount = roleChannels.length;
  const foregroundLockCount = lockedObservations.length;
  const foregroundReadyCount = events.filter(event => event.type === 'pdc-auth-ready').length;
  const foregroundHistoryCount = historyReplacements;
  const foregroundServiceStopCount = serviceStops;
  const foregroundTokenEventCount = events.filter(event => event.type === 'pdc-auth-token-changed').length;
  const foregroundSessionB = { ...refreshedSessionB, access_token: 'session-b-foreground-token' };
  authStateCallback('SIGNED_IN', foregroundSessionB);
  await new Promise(resolve => setTimeout(resolve, 0));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(internals.state.session, foregroundSessionB, 'same-user foreground SIGNED_IN publishes the replacement session');
  assert.strictEqual(internals.state.user, foregroundSessionB.user, 'same-user foreground SIGNED_IN publishes the replacement user');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, 'session-b-foreground-token', 'same-user foreground SIGNED_IN updates the cached access token');
  assert.strictEqual(internals.state.authGeneration, foregroundAuthGeneration, 'same-user foreground SIGNED_IN does not revoke/revalidate authority');
  assert.strictEqual(internals.state.ownRoleChannel, foregroundRoleChannel, 'same-user foreground SIGNED_IN retains the trusted own-role monitor');
  assert.strictEqual(roleQueryCount, foregroundRoleQueryCount, 'same-user foreground SIGNED_IN does not query the role row');
  assert.strictEqual(roleChannels.length, foregroundChannelCount, 'same-user foreground SIGNED_IN does not replace operational listeners');
  assert.strictEqual(lockedObservations.length, foregroundLockCount, 'same-user foreground SIGNED_IN emits no authority lock event');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-ready').length, foregroundReadyCount, 'same-user foreground SIGNED_IN emits no duplicate ready event');
  assert.strictEqual(historyReplacements, foregroundHistoryCount, 'same-user foreground SIGNED_IN does not mutate route/history state');
  assert.strictEqual(serviceStops, foregroundServiceStopCount, 'same-user foreground SIGNED_IN does not tear down application services');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-token-changed').length, foregroundTokenEventCount + 1, 'same-user foreground token replacement invalidates token-bound authority');
  assert.strictEqual(events.filter(event => event.type === 'pdc-auth-token-changed').at(-1)?.detail?.reason, 'session-token-replaced', 'foreground replacement event exposes only a non-secret reason');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'B', 'same-user foreground SIGNED_IN retains approved context');

  // A matching identity is not sufficient without the installed monitor.
  // The event must take the normal lock-and-revalidate path rather than
  // inheriting authority from an unmonitored session.
  internals.state.ownRoleChannel = null;
  const missingMonitorRole = deferred();
  roleResponses.push(missingMonitorRole.promise);
  const missingMonitorSessionB = { ...foregroundSessionB, access_token: 'session-b-missing-monitor-token' };
  const locksBeforeMissingMonitor = lockedObservations.length;
  authStateCallback('SIGNED_IN', missingMonitorSessionB);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(internals.state.session, null, 'same-user SIGNED_IN without a monitor revokes the prior session while revalidating');
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'same-user SIGNED_IN without a monitor revokes the prior context');
  assert.ok(lockedObservations.length > locksBeforeMissingMonitor, 'same-user SIGNED_IN without a monitor emits a lock event');
  missingMonitorRole.resolve(approvedFor('b@example.com', 'viewer'));
  await new Promise(resolve => setTimeout(resolve, 0));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(internals.state.session, missingMonitorSessionB, 'missing-monitor fallback republishes only after role and monitor proof');
  assert.ok(internals.state.ownRoleChannel, 'missing-monitor fallback installs a fresh trusted monitor');

  // A role-row revocation already in flight remains authoritative across a
  // same-principal token refresh. The refresh must neither invalidate the
  // consumed Realtime event nor retain stale authority when it resolves.
  const refreshRaceDisabled = deferred();
  roleResponses.push(refreshRaceDisabled.promise);
  const pendingRefreshRaceRole = internals.handleOwnRoleRowChanged();
  const refreshDuringRoleLookup = { ...missingMonitorSessionB, access_token: 'session-b-race-refresh' };
  authStateCallback('TOKEN_REFRESHED', refreshDuringRoleLookup);
  await new Promise(resolve => setTimeout(resolve, 0));
  refreshRaceDisabled.resolve({ data: { email: 'b@example.com', role: 'viewer', active: false, account_status: 'disabled' }, error: null });
  await pendingRefreshRaceRole;
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'in-flight disabled role result survives same-principal token refresh');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'in-flight disabled role result clears refreshed token');
  assert.strictEqual(internals.state.session, null, 'in-flight disabled role result revokes refreshed session');

  // Re-authorize B, then prove a same-id/different-email SIGNED_IN cannot use
  // the continuity path or retain the old email-bound monitor/context.
  roleResponses.push(Promise.resolve(approvedFor('b@example.com', 'viewer')));
  await internals.applySession(refreshedSessionB);
  const changedEmailSessionB = {
    ...refreshedSessionB,
    access_token: 'session-b-changed-email-token',
    user: { ...refreshedSessionB.user, email: 'unapproved@example.com' },
  };
  roleResponses.push(Promise.resolve({ data: null, error: null }));
  authStateCallback('SIGNED_IN', changedEmailSessionB);
  await new Promise(resolve => setTimeout(resolve, 0));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'same-id/different-email SIGNED_IN fails closed');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'same-id/different-email SIGNED_IN cannot retain the old token authority');
  assert.strictEqual(internals.state.session, null, 'same-id/different-email SIGNED_IN cannot retain the old session authority');

  roleResponses.push(Promise.resolve(approvedFor('b@example.com', 'viewer')));
  await internals.applySession(refreshedSessionB);

  authStateCallback('SIGNED_IN', session);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT.userId, 'B', 'late different-user provider event cannot replace explicit newer user');
  assert.strictEqual(internals.state.session, refreshedSessionB, 'refreshed explicit user remains pinned against stale provider event');

  // The continuity fast path still revalidates the role row. A disabled account
  // discovered during refresh must revoke every authority surface.
  const disabledRefresh = { ...refreshedSessionB, access_token: 'session-b-disabled-refresh' };
  roleResponses.push(Promise.resolve({ data: { email: 'b@example.com', role: 'viewer', active: false, account_status: 'disabled' }, error: null }));
  authStateCallback('TOKEN_REFRESHED', disabledRefresh);
  await new Promise(resolve => setTimeout(resolve, 0));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(raceContext.window.PDC_AUTH_CONTEXT, undefined, 'disabled role discovered on token refresh revokes context');
  assert.strictEqual(raceContext.window.__pdcCachedAccessToken, undefined, 'disabled role discovered on token refresh revokes cached token');
  assert.strictEqual(internals.state.session, null, 'disabled role discovered on token refresh revokes session');

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
