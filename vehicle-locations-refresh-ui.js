'use strict';

(function installVehicleLocationsRefreshUi(global) {
  function setButtonBusy(button, busy) {
    if (!button) return;
    button.disabled = busy === true;
    if (busy === true) {
      button.setAttribute('aria-busy', 'true');
      button.textContent = 'Refreshing…';
    } else {
      button.removeAttribute('aria-busy');
      button.textContent = 'Refresh';
    }
  }

  function createRefreshClickDelegation(options = {}) {
    const root = options.root;
    const refresh = typeof options.refresh === 'function' ? options.refresh : () => ({ ok: false, error: 'refresh_unavailable' });
    const onStart = typeof options.onStart === 'function' ? options.onStart : () => {};
    const onResult = typeof options.onResult === 'function' ? options.onResult : () => {};
    let bound = false;
    let inFlight = null;

    function handleClick(event) {
      const button = event.target?.closest?.('[data-vehicle-locations-refresh]');
      if (!button || (typeof root?.contains === 'function' && !root.contains(button))) return;
      if (button.disabled || inFlight) return;
      event.preventDefault();
      event.stopPropagation();
      setButtonBusy(button, true);
      onStart(button);
      let request;
      try {
        request = refresh();
      } catch (error) {
        request = Promise.reject(error);
      }
      const promise = Promise.resolve(request)
        .then(result => {
          const normalized = result && typeof result === 'object' ? result : { ok: true, value: result };
          onResult(normalized);
          return normalized;
        })
        .catch(error => {
          const failed = { ok: false, error: 'refresh_failed', cause: error };
          onResult(failed);
          return failed;
        })
        .finally(() => {
          if (inFlight === promise) inFlight = null;
          setButtonBusy(button, false);
        });
      inFlight = promise;
    }

    return {
      bind() {
        if (bound || !root || typeof root.addEventListener !== 'function') return false;
        root.addEventListener('click', handleClick);
        bound = true;
        return true;
      },
      isBound: () => bound,
      isRefreshing: () => Boolean(inFlight),
    };
  }

  const vehicleLocationsRefreshUiExported = { createRefreshClickDelegation };
  if (typeof module !== 'undefined' && module.exports) module.exports = vehicleLocationsRefreshUiExported;
  if (global) global.PDC_VEHICLE_LOCATIONS_REFRESH_UI = vehicleLocationsRefreshUiExported;
})(typeof window !== 'undefined' ? window : globalThis);
