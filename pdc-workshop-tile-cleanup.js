(() => {
  'use strict';
  const VERSION = '2026.09.10.02';

  const filled = value => value !== null && value !== undefined && String(value).trim() !== '';

  function shouldHideSelectionPanel(entry, focused) {
    return Boolean(entry) && focused !== true;
  }

  function mergeVehicle(primary = {}, fallback = {}) {
    const merged = { ...fallback, ...primary };
    for (const [key, value] of Object.entries(fallback || {})) {
      if (!filled(merged[key]) && filled(value)) merged[key] = value;
    }
    return merged;
  }

  function bookingIdentity(booking = {}) {
    const direct = String(booking.sharedBookingId || booking.id || '').trim();
    if (direct) return direct;
    return [booking.stage, booking.bay, booking.startAt, booking.endAt, booking.vehicleKey]
      .map(value => String(value || '').trim()).join('|');
  }

  function mergeBookings(left = [], right = []) {
    const merged = new Map();
    for (const booking of [...(Array.isArray(left) ? left : []), ...(Array.isArray(right) ? right : [])]) {
      const key = bookingIdentity(booking);
      if (key && !merged.has(key)) merged.set(key, booking);
    }
    return [...merged.values()];
  }

  function canonicalPreference(match = {}) {
    const vehicle = match.vehicle || {};
    let score = 0;
    if (filled(vehicle.sharedVehicleId)) score += 8;
    if (filled(vehicle.jobCardNumber) || filled(vehicle.jobcard)) score += 4;
    if (filled(vehicle.vehicleDescription) || filled(vehicle.vehicle) || filled(vehicle.description)) score += 2;
    if (filled(vehicle.customerName) || filled(vehicle.client)) score += 1;
    return score;
  }

  // Search can see the same canonical vehicle through app.data, the trusted
  // workshop snapshot and the eligibility snapshot. Those rows can carry
  // different temporary/local IDs even though workshopSharedVehicleRef resolves
  // them to one shared UUID. Collapse only identical canonical identities; never
  // collapse two genuinely different vehicles merely because Stock text matches.
  function dedupeSearchMatches(matches = []) {
    const output = [];
    const indexByIdentity = new Map();
    for (const match of Array.isArray(matches) ? matches : []) {
      const identity = String(match?.vehicleIdentity || '').trim();
      if (!identity || !indexByIdentity.has(identity)) {
        if (identity) indexByIdentity.set(identity, output.length);
        output.push(match);
        continue;
      }
      const index = indexByIdentity.get(identity);
      const current = output[index];
      const preferred = canonicalPreference(match) > canonicalPreference(current) ? match : current;
      const fallback = preferred === match ? current : match;
      const candidateAvailable = Boolean(current?.candidateAvailable || match?.candidateAvailable);
      output[index] = {
        ...fallback,
        ...preferred,
        vehicleIdentity: identity,
        vehicle: mergeVehicle(preferred?.vehicle, fallback?.vehicle),
        bookings: mergeBookings(current?.bookings, match?.bookings),
        rank: Math.min(Number.isFinite(Number(current?.rank)) ? Number(current.rank) : Number.POSITIVE_INFINITY,
          Number.isFinite(Number(match?.rank)) ? Number(match.rank) : Number.POSITIVE_INFINITY),
        archived: Boolean(current?.archived && match?.archived),
        candidateInLane: Boolean(current?.candidateInLane || match?.candidateInLane),
        candidateAvailable,
        candidateDisabledReason: candidateAvailable ? '' : (preferred?.candidateDisabledReason || fallback?.candidateDisabledReason || ''),
      };
    }
    return output;
  }

  function install() {
    if (typeof window === 'undefined') return false;
    if (window.PDC_WORKSHOP_TILE_CLEANUP_VERSION === VERSION) return true;
    if (typeof workshopStationSelectionHtml !== 'function' || typeof workshopState !== 'function'
        || typeof workshopSearchMatches !== 'function') return false;

    if (!window.PDC_WORKSHOP_TILE_PANEL_PATCHED) {
      const previousSelection = workshopStationSelectionHtml;
      workshopStationSelectionHtml = function(entry = null) {
        const state = workshopState();
        // A single click on an existing tile should not open the large duplicate
        // operation/schedule panel above the board. The chip itself already owns
        // Start / STOPPAGE / Complete and drag/resize. Keep the detailed panel for
        // explicit focused-booking links outside the planner, where editing it is
        // intentional.
        if (shouldHideSelectionPanel(entry, state?.focusedBookingMode)) return '';
        return previousSelection(entry);
      };
      window.PDC_WORKSHOP_TILE_PANEL_PATCHED = true;
    }

    if (!window.PDC_WORKSHOP_SEARCH_DEDUPE_PATCHED) {
      const previousSearch = workshopSearchMatches;
      workshopSearchMatches = function(query = '', plans) {
        return dedupeSearchMatches(previousSearch(query, plans));
      };
      window.PDC_WORKSHOP_SEARCH_DEDUPE_PATCHED = true;
    }

    window.PDC_WORKSHOP_TILE_CLEANUP_VERSION = VERSION;
    return true;
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { VERSION, shouldHideSelectionPanel, dedupeSearchMatches, mergeBookings };
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
