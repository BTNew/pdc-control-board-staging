(() => {
  'use strict';
  const VERSION = '2026.09.10.03';

  const filled = value => value !== null && value !== undefined && String(value).trim() !== '';
  const useful = value => {
    if (!filled(value)) return false;
    const text = String(value).trim().toLowerCase();
    return !['—', '-', 'unknown', 'unknown customer', 'vehicle description unavailable',
      'customer unavailable', 'job card unavailable', 'not recorded', 'n/a'].includes(text);
  };

  function shouldHideSelectionPanel(entry, focused) {
    return Boolean(entry) && focused !== true;
  }

  function mergeVehicle(primary = {}, fallback = {}) {
    const merged = { ...fallback, ...primary };
    for (const [key, value] of Object.entries(fallback || {})) {
      if (!useful(merged[key]) && useful(value)) merged[key] = value;
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
    if (useful(vehicle.jobCardNumber) || useful(vehicle.jobcard)) score += 4;
    if (useful(vehicle.vehicleDescription) || useful(vehicle.vehicle) || useful(vehicle.description)) score += 2;
    if (useful(vehicle.customerName) || useful(vehicle.client)) score += 1;
    return score;
  }

  function mergeMatch(current = {}, incoming = {}, forcedIdentity = '') {
    const preferred = canonicalPreference(incoming) > canonicalPreference(current) ? incoming : current;
    const fallback = preferred === incoming ? current : incoming;
    const candidateAvailable = Boolean(current?.candidateAvailable || incoming?.candidateAvailable);
    const rankValues = [current?.rank, incoming?.rank].map(value => Number(value)).filter(Number.isFinite);
    return {
      ...fallback,
      ...preferred,
      vehicleIdentity: forcedIdentity || String(preferred?.vehicleIdentity || fallback?.vehicleIdentity || '').trim(),
      vehicle: mergeVehicle(preferred?.vehicle, fallback?.vehicle),
      bookings: mergeBookings(current?.bookings, incoming?.bookings),
      rank: rankValues.length ? Math.min(...rankValues) : Number.POSITIVE_INFINITY,
      archived: Boolean(current?.archived && incoming?.archived),
      candidateInLane: Boolean(current?.candidateInLane || incoming?.candidateInLane),
      candidateAvailable,
      candidateDisabledReason: candidateAvailable ? '' : (preferred?.candidateDisabledReason || fallback?.candidateDisabledReason || ''),
    };
  }

  function normalizedStock(match = {}) {
    const vehicle = match.vehicle || {};
    return String(vehicle.stockNumber ?? vehicle.stock_number ?? vehicle.stock ?? vehicle.batch ?? match.stockNumber ?? '')
      .trim().toUpperCase();
  }

  function normalizedIdentityField(vehicle = {}, names = []) {
    for (const name of names) {
      if (useful(vehicle?.[name])) return String(vehicle[name]).trim().toUpperCase();
    }
    return '';
  }

  function strongIdentityConflicts(left = {}, right = {}) {
    const groups = [
      ['vin', 'vinNormalized', 'vin_normalized'],
      ['sourceRecordId', 'source_record_id', 'sourceRecordID'],
      ['permanentVehicleId', 'permanent_vehicle_id'],
    ];
    return groups.some(names => {
      const a = normalizedIdentityField(left, names);
      const b = normalizedIdentityField(right, names);
      return Boolean(a && b && a !== b);
    });
  }

  // Search can see the same canonical vehicle through app.data, the trusted
  // workshop snapshot, the eligibility snapshot, and (after QC rejection) a
  // rework/unallocated fallback row. First collapse exact shared identities.
  // Then, only when an exact Stock has one and only one shared identity, fold
  // weak legacy/fallback rows into that canonical result unless a VIN/source/
  // permanent identity conflicts. Two distinct shared identities are never
  // collapsed merely because their Stock text is equal.
  function dedupeSearchMatches(matches = []) {
    const firstPass = [];
    const indexByIdentity = new Map();
    for (const match of Array.isArray(matches) ? matches : []) {
      const identity = String(match?.vehicleIdentity || '').trim();
      if (!identity || !indexByIdentity.has(identity)) {
        if (identity) indexByIdentity.set(identity, firstPass.length);
        firstPass.push(match);
        continue;
      }
      const index = indexByIdentity.get(identity);
      firstPass[index] = mergeMatch(firstPass[index], match, identity);
    }

    const indexesByStock = new Map();
    firstPass.forEach((match, index) => {
      const stock = normalizedStock(match);
      if (!stock) return;
      if (!indexesByStock.has(stock)) indexesByStock.set(stock, []);
      indexesByStock.get(stock).push(index);
    });

    const drop = new Set();
    for (const indexes of indexesByStock.values()) {
      if (indexes.length < 2) continue;
      const sharedIdentities = [...new Set(indexes.map(index => String(firstPass[index]?.vehicleIdentity || '').trim())
        .filter(identity => identity.startsWith('shared:')))];
      if (sharedIdentities.length !== 1) continue;

      const canonicalIdentity = sharedIdentities[0];
      const canonicalIndex = indexes.find(index => String(firstPass[index]?.vehicleIdentity || '').trim() === canonicalIdentity);
      if (canonicalIndex === undefined) continue;
      const mergeable = indexes.filter(index => {
        if (index === canonicalIndex) return true;
        const identity = String(firstPass[index]?.vehicleIdentity || '').trim();
        if (identity.startsWith('shared:')) return false;
        return !strongIdentityConflicts(firstPass[canonicalIndex]?.vehicle, firstPass[index]?.vehicle);
      });
      if (mergeable.length < 2) continue;

      const hostIndex = Math.min(...mergeable);
      let combined = firstPass[canonicalIndex];
      for (const index of mergeable) {
        if (index !== canonicalIndex) combined = mergeMatch(combined, firstPass[index], canonicalIdentity);
      }
      firstPass[hostIndex] = combined;
      for (const index of mergeable) if (index !== hostIndex) drop.add(index);
    }
    return firstPass.filter((_, index) => !drop.has(index));
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
    module.exports = { VERSION, shouldHideSelectionPanel, dedupeSearchMatches, mergeBookings, strongIdentityConflicts };
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
