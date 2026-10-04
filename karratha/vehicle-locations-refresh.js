'use strict';

/*
 * Coordinates read-only operational refreshes. Route adapters are composed by
 * app.js from existing authoritative service APIs; this module owns only
 * generations, duplicate-click coalescing, and stale completion isolation.
 * It never mutates operational data and keeps the old Vehicle Locations
 * factory name as a compatibility alias for existing callers/tests.
 */

function createPdcOperationalRefreshCoordinator(options = {}) {
  const loaders = options.loaders && typeof options.loaders === 'object' ? options.loaders : {};
  const routeAdapters = options.routeAdapters && typeof options.routeAdapters === 'object' ? options.routeAdapters : {};
  const getRoute = typeof options.getRoute === 'function' ? options.getRoute : () => '';
  const onStart = typeof options.onStart === 'function' ? options.onStart : () => {};
  const onFinish = typeof options.onFinish === 'function' ? options.onFinish : () => {};
  let generation = 0;
  let inFlight = null;
  let queuedRefresh = null;

  function refreshSources(refreshOptions) {
    const values = Array.isArray(refreshOptions.sources) ? refreshOptions.sources : [refreshOptions.source || 'full'];
    return [...new Set(values.length ? values : ['full'])];
  }

  // A slow network can deliver revisions faster than snapshots complete.
  // Keep one trailing refresh instead of running a full board load for each
  // event. It starts after the current read, so it includes the newest write.
  function queueLatest(refreshOptions) {
    if (queuedRefresh) {
      // A later email revision must not discard a queued Navision/manual
      // refresh, which still needs every authoritative reader.
      queuedRefresh.options = { ...refreshOptions, sources: [...new Set([
        ...refreshSources(queuedRefresh.options), ...refreshSources(refreshOptions),
      ])] };
      return queuedRefresh.promise;
    }
    const queued = { options: refreshOptions };
    queued.promise = new Promise(resolve => { queued.resolve = resolve; });
    queuedRefresh = queued;
    return queued.promise;
  }

  function startQueuedRefresh() {
    const queued = queuedRefresh;
    if (!queued || inFlight) return;
    queuedRefresh = null;
    // Explicit route changes that occurred during a background refresh win.
    const activeRoute = String(getRoute() || '');
    const route = routeAdapters[activeRoute] ? activeRoute : queued.options.route;
    refresh({ ...queued.options, route, deferSupersede: false }).then(queued.resolve,
      error => queued.resolve({ ok: false, error: error?.message || 'refresh_failed' }));
  }

  function isCurrent(candidate) {
    return Number(candidate) === generation;
  }

  function isRefreshing() {
    return Boolean(inFlight);
  }

  function refresh(refreshOptions = {}) {
    const supersede = refreshOptions?.supersede === true;
    if (inFlight && supersede && refreshOptions?.deferSupersede === true) return queueLatest(refreshOptions);
    if (inFlight && !supersede) return inFlight;
    const route = String(refreshOptions?.route || getRoute() || 'dashboard').trim() || 'dashboard';
    const currentGeneration = ++generation;
    const startedAt = Date.now();
    const selectedLoaders = routeAdapters[route] && typeof routeAdapters[route] === 'object'
      ? routeAdapters[route]
      : loaders;
    onStart(currentGeneration, route);
    const entries = Object.entries(selectedLoaders).filter(([, loader]) => typeof loader === 'function');
    const promise = Promise.all(entries.map(async ([key, loader]) => {
      const context = {
        generation: currentGeneration,
        route,
        sources: refreshSources(refreshOptions),
        isCurrent: () => isCurrent(currentGeneration),
      };
      try {
        const value = await loader(context);
        return { key, ok: value?.ok !== false, value, stale: !context.isCurrent() };
      } catch (error) {
        return { key, ok: false, error, stale: !context.isCurrent() };
      }
    })).then(results => {
      if (!isCurrent(currentGeneration)) return {
        ok: false,
        stale: true,
        generation: currentGeneration,
        route,
        results,
      };
      const failed = results.filter(result => result.ok !== true);
      const result = {
        ok: failed.length === 0,
        partial: failed.length > 0 && failed.length < results.length,
        stale: false,
        generation: currentGeneration,
        route,
        durationMs: Math.max(0, Date.now() - startedAt),
        results,
        errors: failed.map(result => ({ key: result.key, error: result.error || result.value?.error || result.value?.code || 'refresh_failed' })),
      };
      onFinish(result);
      return result;
    }).finally(() => {
      if (inFlight === promise) {
        inFlight = null;
        startQueuedRefresh();
      }
    });
    inFlight = promise;
    return promise;
  }

  function invalidate() {
    generation += 1;
    inFlight = null;
    if (queuedRefresh) queuedRefresh.resolve({ ok: false, stale: true, generation });
    queuedRefresh = null;
    return generation;
  }

  return {
    refresh,
    invalidate,
    isCurrent,
    isRefreshing,
    getGeneration: () => generation,
  };
}

function createVehicleLocationsRefreshCoordinator(options = {}) {
  return createPdcOperationalRefreshCoordinator(options);
}

const vehicleLocationsRefreshExported = {
  createPdcOperationalRefreshCoordinator,
  createVehicleLocationsRefreshCoordinator,
};
if (typeof module !== 'undefined' && module.exports) module.exports = vehicleLocationsRefreshExported;
if (typeof window !== 'undefined') window.PDC_VEHICLE_LOCATIONS_REFRESH = vehicleLocationsRefreshExported;
