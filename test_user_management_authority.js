'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8').replace(/\r\n/g, '\n');

function extract(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, `extractable block: ${startMarker}`);
  return source.slice(start, end);
}

function deferred() {
  let resolve;
  const promise = new Promise(next => { resolve = next; });
  return { promise, resolve };
}

(async () => {
  const block = extract('const USER_MANAGEMENT_STATE', 'function cancelWorkshopPlannerRender');
  let role = 'administrator';
  let query = deferred();
  let rpc = deferred();
  let channelHandler = null;
  let removedChannels = 0;
  const channel = {
    on(_event, _filter, handler) { channelHandler = handler; return this; },
    subscribe() { return this; },
  };
  const client = {
    from() {
      return {
        select() {
          return { order() { return query.promise; } };
        },
      };
    },
    channel() { return channel; },
    removeChannel(value) { assert.strictEqual(value, channel); removedChannels += 1; },
    rpc() { return rpc.promise; },
  };
  const nodes = {
    '#nav-user-management': { hidden: true },
    '#user-management-content': { innerHTML: '', replaceChildren() { this.innerHTML = ''; } },
  };
  const context = vm.createContext({
    window: {
      PDC_SUPABASE: client,
      PDC_AUTH_CONTEXT: { userId: 'admin-a', email: 'admin@example.test', role },
      confirm: () => true,
      prompt: () => '',
    },
    document: {
      getElementById(id) {
        if (id === 'user-management') return { classList: { contains: () => true } };
        return null;
      },
    },
    $: selector => nodes[selector] || null,
    $$: () => [],
    backupStatusSharedModeReady: () => role === 'administrator',
    escapeHtml: value => String(value),
    cleanNavisionText: value => String(value || ''),
    alert: () => { throw new Error('stale authority must not alert'); },
  });
  vm.runInContext(block, context);

  const first = vm.runInContext('renderUserManagementScreen()', context);
  assert.strictEqual(channelHandler, null, 'Realtime must not subscribe before the initial administrator snapshot is authority-validated');
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin@example.test', role };
  query.resolve({ data: [{ email: 'private@example.test', role: 'administrator', account_status: 'approved' }], error: null });
  assert.strictEqual(await first, false, 'in-flight load must report superseded after administrator demotion');
  assert.ok(!nodes['#user-management-content'].innerHTML.includes('private@example.test'), 'demoted response must not publish user rows');
  assert.strictEqual(vm.runInContext('USER_MANAGEMENT_STATE.rows.length', context), 0, 'demoted response must not retain user rows');
  assert.strictEqual(nodes['#nav-user-management'].hidden, true, 'non-administrator User Management navigation must stay hidden');

  role = 'administrator';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin@example.test', role };
  query = deferred();
  const staleError = vm.runInContext('renderUserManagementScreen()', context);
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin@example.test', role };
  query.resolve({ data: null, error: new Error('private backend detail') });
  assert.strictEqual(await staleError, false, 'stale load error must be discarded after demotion');
  assert.ok(!nodes['#user-management-content'].innerHTML.includes('private backend detail'), 'stale errors must not publish after authority loss');

  role = 'administrator';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin-a@example.test', role };
  query = deferred();
  const replacedPrincipal = vm.runInContext('renderUserManagementScreen()', context);
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-b', email: 'admin-b@example.test', role };
  query.resolve({ data: [{ email: 'old-principal-private@example.test', role: 'viewer', account_status: 'approved' }], error: null });
  assert.strictEqual(await replacedPrincipal, false, 'same-role principal replacement must supersede the old administrator request');
  assert.ok(!nodes['#user-management-content'].innerHTML.includes('old-principal-private@example.test'), 'old principal rows must not cross into the replacement session');

  query = deferred();
  const second = vm.runInContext('renderUserManagementScreen()', context);
  query.resolve({ data: [{ email: 'visible@example.test', role: 'viewer', account_status: 'approved' }], error: null });
  assert.strictEqual(await second, true, 'current administrator load must publish');
  assert.ok(nodes['#user-management-content'].innerHTML.includes('visible@example.test'), 'current administrator rows must render');
  assert.strictEqual(typeof channelHandler, 'function', 'Realtime subscribes only after a current administrator snapshot');

  vm.runInContext('resetUserManagementAuthorityState({ clearHost: true })', context);
  assert.strictEqual(removedChannels, 1, 'authority reset must release User Management Realtime');
  assert.strictEqual(vm.runInContext('USER_MANAGEMENT_STATE.rows.length', context), 0, 'authority reset must clear retained rows');
  assert.strictEqual(nodes['#nav-user-management'].hidden, true, 'authority reset must hide User Management navigation');
  assert.ok(!nodes['#user-management-content'].innerHTML.includes('visible@example.test'), 'authority reset must clear rendered user data');

  role = 'administrator';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin@example.test', role };
  rpc = deferred();
  let postRpcRenders = 0;
  context.renderUserManagementScreen = async () => { postRpcRenders += 1; return true; };
  const mutation = vm.runInContext("userManagementCallRpc('admin_change_role', { p_target_email: 'x@example.test', p_role: 'viewer' }, 'Changed')", context);
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: 'admin-a', email: 'admin@example.test', role };
  rpc.resolve({ error: null });
  assert.strictEqual(await mutation, false, 'post-await RPC result must be discarded after demotion');
  assert.strictEqual(postRpcRenders, 0, 'stale mutation completion must not re-render User Management');

  // A callback already queued by principal A must never reset principal B's
  // replacement channel, rows, route, or DOM after the authority handover.
  let replacementRole = 'administrator';
  const removedBy = [];
  const handlers = new Map();
  function realtimeClient(label) {
    const ownedChannel = {
      label,
      on(_event, _filter, handler) { handlers.set(label, handler); return this; },
      subscribe() { return this; },
    };
    return {
      ownedChannel,
      channel() { return ownedChannel; },
      removeChannel(value) { removedBy.push(`${label}:${value.label}`); },
      from() { throw new Error('not used by the focused Realtime ownership test'); },
    };
  }
  const clientA = realtimeClient('A');
  const clientB = realtimeClient('B');
  const realtimeNodes = {
    '#nav-user-management': { hidden: false },
    '#user-management-content': { innerHTML: 'replacement-private-row', replaceChildren() { this.innerHTML = ''; } },
  };
  const realtimeContext = vm.createContext({
    window: {
      PDC_SUPABASE: clientA,
      PDC_AUTH_CONTEXT: { userId: 'admin-a', email: 'admin-a@example.test', role: replacementRole },
    },
    document: { getElementById: () => null },
    $: selector => realtimeNodes[selector] || null,
    $$: () => [],
    backupStatusSharedModeReady: () => replacementRole === 'administrator',
    escapeHtml: value => String(value),
    cleanNavisionText: value => String(value || ''),
    app: { currentView: 'user-management', currentRequestedView: 'user-management' },
    showView: () => { throw new Error('stale principal A callback must not redirect principal B'); },
  });
  vm.runInContext(block, realtimeContext);
  vm.runInContext('subscribeUserManagementRealtime()', realtimeContext);
  const staleHandlerA = handlers.get('A');
  assert.strictEqual(typeof staleHandlerA, 'function', 'principal A callback captured');
  vm.runInContext('resetUserManagementAuthorityState({ clearHost: true })', realtimeContext);
  realtimeContext.window.PDC_SUPABASE = clientB;
  realtimeContext.window.PDC_AUTH_CONTEXT = { userId: 'admin-b', email: 'admin-b@example.test', role: replacementRole };
  realtimeNodes['#user-management-content'].innerHTML = 'replacement-private-row';
  vm.runInContext("USER_MANAGEMENT_STATE.rows = [{ email: 'b@example.test' }]; subscribeUserManagementRealtime()", realtimeContext);
  assert.strictEqual(vm.runInContext('USER_MANAGEMENT_STATE.realtimeChannel.label', realtimeContext), 'B', 'principal B owns the replacement channel');
  staleHandlerA();
  assert.strictEqual(vm.runInContext('USER_MANAGEMENT_STATE.realtimeChannel.label', realtimeContext), 'B', 'stale A callback must preserve B channel ownership');
  assert.strictEqual(vm.runInContext('USER_MANAGEMENT_STATE.rows.length', realtimeContext), 1, 'stale A callback must preserve B rows');
  assert.strictEqual(realtimeNodes['#user-management-content'].innerHTML, 'replacement-private-row', 'stale A callback must preserve B DOM');
  assert.ok(!removedBy.includes('B:B'), 'stale A callback must not remove B channel');

  const navBlock = extract('function syncAdminNavigationVisibility()', 'function resetDeletedVehicleAuthorityState()');
  const navNodes = {
    '#nav-admin-group': { hidden: true },
    '#nav-user-management': { hidden: false },
  };
  role = 'viewer';
  const navContext = vm.createContext({
    window: { PDC_AUTH_CONTEXT: { userId: 'viewer-a', email: 'viewer@example.test', role } },
    $: selector => navNodes[selector] || null,
    document: { querySelector: selector => selector === '#nav-user-management' ? navNodes['#nav-user-management'] : null },
    setAdminNavigationExpanded() {},
    vehicleLifecycleAdministratorActive: () => false,
    userManagementSharedModeReady: () => role === 'administrator',
  });
  vm.runInContext(navBlock, navContext);
  vm.runInContext('syncAdminNavigationVisibility()', navContext);
  assert.strictEqual(navNodes['#nav-user-management'].hidden, true, 'signed-in viewer must not see User Management navigation');
  role = 'administrator';
  navContext.window.PDC_AUTH_CONTEXT.role = role;
  vm.runInContext('syncAdminNavigationVisibility()', navContext);
  assert.strictEqual(navNodes['#nav-user-management'].hidden, false, 'administrator must see User Management navigation');

  const showViewBlock = extract('function showView(view, options)', 'const HEAVY_VIEW_HOSTS');
  assert.match(showViewBlock, /requestedView === ['"]user-management['"]\s*&&\s*!userManagementSharedModeReady\(\)/, 'direct/hash/history User Management route must reject non-administrators');

  const authReadyBlock = extract("window.addEventListener?.('pdc-auth-ready'", '// Silent refresh and same-principal foreground sign-in');
  assert.match(authReadyBlock, /resetUserManagementAuthorityState\(/, 'auth-ready must invalidate User Management authority generation');
  assert.doesNotMatch(authReadyBlock, /navItem\.hidden\s*=\s*false/, 'auth-ready must not expose User Management unconditionally');
  const tokenBlock = extract("window.addEventListener?.('pdc-auth-token-changed'", '// Independent-review remediation');
  assert.match(tokenBlock, /resetUserManagementAuthorityState\(/, 'token changes must invalidate User Management in-flight work');
  const lockedBlock = extract("window.addEventListener?.('pdc-auth-locked'", 'function renderWorkshopPlannerWhenReady');
  assert.match(lockedBlock, /resetUserManagementAuthorityState\(/, 'lockout must centrally clear User Management rows, channel and generation');

  console.log('User Management administrator navigation, route, async-generation and authority teardown checks passed');
})().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
