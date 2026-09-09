(() => {
  'use strict';
  const VERSION = '2026.09.10.01';

  function install() {
    if (typeof window === 'undefined') return false;
    if (window.PDC_WORKSHOP_TILE_CLEANUP_VERSION) return true;
    if (typeof workshopStationSelectionHtml !== 'function' || typeof workshopState !== 'function') return false;

    const previous = workshopStationSelectionHtml;
    workshopStationSelectionHtml = function(entry = null) {
      const state = workshopState();
      // A single click on an existing tile should not open the large duplicate
      // operation/schedule panel above the board. The chip itself already owns
      // Start / STOPPAGE / Complete and drag/resize. Keep the detailed panel for
      // explicit focused-booking links outside the planner, where editing it is
      // intentional.
      if (entry && state?.focusedBookingMode !== true) return '';
      return previous(entry);
    };

    window.PDC_WORKSHOP_TILE_CLEANUP_VERSION = VERSION;
    return true;
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { VERSION, shouldHideSelectionPanel: (entry, focused) => Boolean(entry) && focused !== true };
    return;
  }

  if (install()) return;
  let attempts = 0;
  const retry = () => {
    attempts += 1;
    if (install() || attempts >= 40) return;
    window.setTimeout(retry, 250);
  };
  retry();
})();
