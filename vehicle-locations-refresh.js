'use strict';

/*
 * Coordinates the read-only Vehicle Locations refresh fan-in. Each loader is
 * an existing authoritative service API supplied by app.js. This module owns
 * only refresh generations, duplicate-click coalescing, and stale completion
 * isolation; it never mutates operational data.
 */

function createVehicleLocationsRefreshCoordinator(options = {}) {
  const loaders = options.loaders && typeof options.loaders === 'object' ? options.loaders : {};
  const onStart = typeof options.onStart === 'function' ? options.onStart : () => {};
  const onFinish = typeof options.onFinish === 'function' ? options.onFinish : () => {};
  let generation = 0;
  let inFlight = null;

  function isCurrent(candidate) {
    return Number(candidate) === generation;
  }

  function isRefreshing() {
    return Boolean(inFlight);
  }

  function refresh(refreshOptions = {}) {
    const supersede = refreshOptions?.supersede === true;
    if (inFlight && !supersede) return inFlight;
    const currentGeneration = ++generation;
    const startedAt = Date.now();
    onStart(currentGeneration);
    const entries = Object.entries(loaders).filter(([, loader]) => typeof loader === 'function');
    const promise = Promise.all(entries.map(async ([key, loader]) => {
      const context = {
        generation: currentGeneration,
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
        results,
      };
      const failed = results.filter(result => result.ok !== true);
      const result = {
        ok: failed.length === 0,
        partial: failed.length > 0 && failed.length < results.length,
        stale: false,
        generation: currentGeneration,
        durationMs: Math.max(0, Date.now() - startedAt),
        results,
        errors: failed.map(result => ({ key: result.key, error: result.error || result.value?.error || result.value?.code || 'refresh_failed' })),
      };
      onFinish(result);
      return result;
    }).finally(() => {
      if (inFlight === promise) inFlight = null;
    });
    inFlight = promise;
    return promise;
  }

  function invalidate() {
    generation += 1;
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

const vehicleLocationsRefreshExported = { createVehicleLocationsRefreshCoordinator };
if (typeof module !== 'undefined' && module.exports) module.exports = vehicleLocationsRefreshExported;
if (typeof window !== 'undefined') window.PDC_VEHICLE_LOCATIONS_REFRESH = vehicleLocationsRefreshExported;
