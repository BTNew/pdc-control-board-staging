// Own Department 135 boundary only. The native readers continue to supply all
// display data and the native refresh coordinator keeps its draft/route guards.
(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else {
    root.PDC135_NAVISION_FRESHNESS = api;
    if (!root.document || typeof root.setTimeout !== 'function') return;
    const start = () => api.install(root);
    if (root.document.readyState === 'loading') root.document.addEventListener('DOMContentLoaded', start, { once: true });
    else start();
  }
})(typeof window === 'object' ? window : globalThis, function () {
  'use strict';
  const interval = 30000;
  const busyRetry = 1000;
  const roles = new Set(['viewer', 'operator', 'importer', 'administrator']);
  const revision = value => value != null && /^\d+$/.test(String(value)) && Number.isSafeInteger(Number(value)) ? Number(value) : null;

  function create(options) {
    let epoch = 0, authority = '', locked = false, destroyed = false;
    let timer = null, timerAt = null, running = null, pendingRefresh = false;
    let lastProbeAt = -Infinity;
    const now = options.now || Date.now;
    const scheduleTimeout = options.setTimeout || setTimeout;
    const clearScheduledTimeout = options.clearTimeout || clearTimeout;
    const abortController = options.createAbortController || (() => new AbortController());
    const status = (state, value = null) => options.onStatus?.(state, value);
    const key = () => String(options.getAuthority() || '');
    const token = () => options.getToken();
    const eligible = () => !destroyed && !locked && Boolean(key() && token() && options.isVisible() && options.canRead());
    const cancelTimer = () => { if (timer !== null) clearScheduledTimeout(timer); timer = null; timerAt = null; };
    function adopt() {
      const next = key();
      if (next !== authority) {
        authority = next; epoch++; pendingRefresh = false; lastProbeAt = -Infinity; cancelTimer();
        running?.controller?.abort();
        if (!locked) status('pending');
      }
    }
    function schedule(delay = interval) {
      if (!eligible()) { cancelTimer(); return; }
      const at = now() + delay;
      if (timer !== null && timerAt <= at) return;
      cancelTimer(); timerAt = at;
      timer = scheduleTimeout(() => { timer = null; timerAt = null; void tick(); }, delay);
    }
    const current = owner => !destroyed && !locked && owner.epoch === epoch
      && owner.authority === key() && owner.token === token() && eligible();
    async function tick() {
      adopt();
      if (!eligible()) { cancelTimer(); return; }
      // Do not supersede a manual refresh, a native source load, or another
      // freshness request. One retry waits for the existing work to settle.
      if (running || options.isBusy()) { schedule(busyRetry); return; }
      const owner = { epoch, authority: key(), token: token(), controller: null, timeout: null };
      running = owner;
      try {
        if (!pendingRefresh) {
          if (now() - lastProbeAt < busyRetry) { schedule(busyRetry); return; }
          lastProbeAt = now();
          const before = revision(options.getKnownRevision());
          owner.controller = abortController();
          owner.timeout = scheduleTimeout(() => owner.controller.abort(), 15000);
          const response = await options.probe(owner.controller.signal);
          clearScheduledTimeout(owner.timeout); owner.timeout = null;
          if (!current(owner)) return;
          const after = revision(response?.data?.data?.revision ?? response?.data?.revision);
          if (response?.ok !== true || after === null) { status('error'); return; }
          status('checked', after);
          if (before === after) return;
          pendingRefresh = true;
        }
        if (!current(owner) || options.isBusy()) return;
        const route = options.getRoute();
        if (!route) return;
        // Projection finishes before the source/canonical/planner readers run.
        // The service probe never stores its one-row result as a board snapshot.
        const result = await options.refresh(route);
        if (!current(owner)) return;
        if (result?.ok === true && result.stale !== true) pendingRefresh = false;
      } catch (_error) {
        // Native connection/authority handling stays authoritative. No cached
        // source rows, role fallback, or error payload is adopted here.
        if (current(owner)) status('error');
      } finally {
        if (owner.timeout !== null) clearScheduledTimeout(owner.timeout);
        if (running === owner) running = null;
        adopt();
        schedule(pendingRefresh ? busyRetry : interval);
      }
    }
    function ready() { locked = false; adopt(); schedule(0); }
    function lockedSession() { locked = true; epoch++; authority = ''; pendingRefresh = false; lastProbeAt = -Infinity; cancelTimer(); running?.controller?.abort(); status('locked'); }
    function wake() { adopt(); if (!eligible()) running?.controller?.abort(); schedule(0); }
    function destroy() { destroyed = true; epoch++; pendingRefresh = false; cancelTimer(); running?.controller?.abort(); }
    return Object.freeze({ ready, locked: lockedSession, wake, tick, destroy });
  }

  function install(root) {
    if (root.PDC135_NAVISION_FRESHNESS_CONTROLLER) return root.PDC135_NAVISION_FRESHNESS_CONTROLLER;
    const nativeApp = () => typeof app === 'object' ? app : null;
    const ownContext = () => {
      const context = root.PDC_AUTH_CONTEXT;
      return context?.centreCode === '135' && roles.has(context.role) && root.PDC135_CONNECTION?.ready === true ? context : null;
    };
    const controller = create({
      getAuthority: () => {
        const context = ownContext();
        return context ? JSON.stringify([context.userId, context.role, context.membership_version, context.engine_version, context.centreCode]) : '';
      },
      getToken: () => root.PDC_AUTH?.getAccessToken?.() || root.__pdcCachedAccessToken || null,
      isVisible: () => root.document.visibilityState === 'visible',
      canRead: () => Boolean(ownContext()) && typeof navisionSharedBackendService === 'function'
        && typeof root.AbortController === 'function' && typeof root.PDC_NAVISION_BACKEND_SERVICE?.createNavisionBackendService === 'function'
        && typeof refreshOperationalPage === 'function' && typeof vehicleLocationsRefreshRoleCanRead === 'function'
        && vehicleLocationsRefreshRoleCanRead(),
      isBusy: () => Boolean(nativeApp()?.vehicleLocationsRefreshCoordinator?.isRefreshing?.()
        || nativeApp()?.sharedNavisionVisibleState === 'loading'),
      getKnownRevision: () => nativeApp()?.sharedNavisionVisibleRevision,
      getRoute: () => typeof OPERATIONAL_REFRESH_ROUTES !== 'undefined'
        && OPERATIONAL_REFRESH_ROUTES.includes(nativeApp()?.currentView) ? nativeApp().currentView : null,
      probe: signal => {
        const service = root.PDC_NAVISION_BACKEND_SERVICE.createNavisionBackendService({
          config: root.PDC_SUPABASE_CONFIG,
          getAccessToken: () => root.PDC_AUTH?.getAccessToken?.() || root.__pdcCachedAccessToken || null,
          fetchImpl: (url, init) => root.fetch(url, { ...init, signal }),
        });
        return service.visibleSnapshot({ sourceSystem: 'microsoft_navision', dealerCode: '14450' }, {}, 1, null);
      },
      refresh: route => refreshOperationalPage(route, { source: 'navision_freshness' }),
      now: () => Date.now(), setTimeout: root.setTimeout.bind(root), clearTimeout: root.clearTimeout.bind(root),
      createAbortController: () => new root.AbortController(),
      onStatus: (state, value) => {
        const data = root.document.body?.dataset;
        if (!data) return;
        data.pd135NavisionStatus = state;
        if (state === 'checked') { data.pd135NavisionChecked = new Date().toISOString(); data.pd135NavisionRevision = String(value); }
        else { delete data.pd135NavisionChecked; delete data.pd135NavisionRevision; }
      },
    });
    root.PDC135_NAVISION_FRESHNESS_CONTROLLER = controller;
    root.addEventListener('pdc-auth-ready', controller.ready);
    root.addEventListener('pdc-auth-locked', controller.locked);
    root.addEventListener('focus', controller.wake);
    root.addEventListener('online', controller.wake);
    root.addEventListener('hashchange', controller.wake);
    root.document.addEventListener('visibilitychange', controller.wake);
    controller.ready();
    return controller;
  }
  return Object.freeze({ create, install });
});
