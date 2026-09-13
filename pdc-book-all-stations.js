/* Book outstanding workshop stations as one server-validated transaction. */
(() => {
  'use strict';
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || window.PDC_BOOK_ALL_STATIONS) return;

  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const writable = () => ['operator', 'administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const pending = new Map();
  let sessionGeneration = 0;
  const vehicleId = vehicle => String(vehicle?.__emailVehicleId || '');
  function currentVehicle(id, requireSnapshot = false) {
    const mapped = (app.data || []).filter(vehicle => vehicleId(vehicle) === id);
    if (mapped.length !== 1) return null;
    if (requireSnapshot) {
      // The snapshot stores raw server fields; app.data contains reconciled board rows.
      const raw = (app.emailVehicleLocationRows || []).filter(row => String(row.id || '') === id);
      if (raw.length !== 1 || Number(raw[0].version) !== Number(mapped[0].__emailVehicleVersion)) return null;
    }
    return mapped[0];
  }
  function eligible(vehicle = {}) {
    if (!writable() || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(vehicleId(vehicle))) return false;
    if (!Number.isInteger(Number(vehicle.__emailVehicleVersion)) || Number(vehicle.__emailVehicleVersion) < 1 || vehicle.__locationIdentityReadOnly === true) return false;
    if (typeof sharedNavisionLocationAuthorityReady !== 'function' || !sharedNavisionLocationAuthorityReady()) return false;
    if (vehicle.deleted_at || vehicle.deletedAt || vehicle.pdcSheetVisible === false || String(vehicle.lifecycle_state || vehicle.lifecycleState || 'active').toLowerCase() !== 'active') return false;
    const location = vehicle.pdcLocationOverride || vehicle.current_location || vehicle.pdcAutomaticLocation || vehicle.currentLocation || vehicle.pdcLocation;
    return window.PDC_WORKSHOP_ELIGIBILITY?.scheduleEligibility({ ...vehicle, current_location: location }).enabled === true;
  }
  function actionHtml(vehicle, existingAction = '') {
    if (!eligible(vehicle)) return existingAction;
    // Keep transfer, QC and Open controls; replace only the old source-only badge.
    const retained = existingAction.replace(/<span class="badge neutral">(?:[^<]*Read only|Pilbara Service Review · R\/O loaded)<\/span>/g, '');
    const active = pending.get(vehicleId(vehicle));
    return `${retained}<button class="primary incoming-book-all-stations" type="button" data-book-all-stations="${esc(vehicleId(vehicle))}" ${active ? 'disabled aria-busy="true"' : ''} title="Book each outstanding workshop station in its next available bay, with 5 hours between this vehicle’s jobs. Sublet is excluded."><span>${active ? (active.refreshing ? 'Updating board…' : 'Booking stations…') : 'Book all stations'}</span></button>`;
  }
  const dialog = document.createElement('dialog');
  dialog.className = 'book-all-stations-dialog';
  dialog.setAttribute('aria-labelledby', 'book-all-stations-title');
  dialog.innerHTML = '<h2 id="book-all-stations-title">Book all stations</h2><p data-book-all-vehicle></p><div data-book-all-result role="status" aria-live="polite"></div><footer><button type="button" class="small-button" data-book-all-close>Close</button></footer>';
  document.body.appendChild(dialog);
  const resultHost = dialog.querySelector('[data-book-all-result]');
  const closeButton = dialog.querySelector('[data-book-all-close]');
  let saving = false;
  let owner = null;
  closeButton.addEventListener('click', () => dialog.close());
  dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  const stageLabel = value => window.PDC_WORKSHOP_ELIGIBILITY?.workshopStageDefinition(value)?.label || String(value || 'Workshop');
  function timeLabel(value) {
    const time = new Date(value);
    return Number.isNaN(time.getTime()) ? 'Time unavailable' : time.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
  }
  function summaryHtml(result) {
    const bookings = Array.isArray(result.bookings) ? result.bookings : [];
    const skipped = Array.isArray(result.skipped) ? result.skipped : [];
    const count = bookings.length;
    const summary = `<p><strong>${count ? `${count} station${count === 1 ? '' : 's'} booked.` : 'No new bookings were needed.'}</strong></p>`;
    const rows = bookings.length ? `<div class="book-all-stations-table"><table><thead><tr><th>Station / bay</th><th>Start</th><th>Finish</th></tr></thead><tbody>${bookings.map(booking => `<tr><th scope="row">${esc(stageLabel(booking.stage))}<small>Bay ${esc(booking.bay)}</small></th><td>${esc(timeLabel(booking.start_at))}</td><td>${esc(timeLabel(booking.end_at))}</td></tr>`).join('')}</tbody></table></div>` : '';
    const skippedHtml = skipped.length ? `<p class="subtle">${skipped.map(item => `${esc(stageLabel(item.stage))}: ${esc(item.reason || 'already booked')}`).join('<br>')}</p>` : '';
    return `${summary}${rows}${skippedHtml}<p class="subtle">Sublet is excluded. A 5-hour gap is allowed between this vehicle’s jobs.</p>`;
  }
  function authorityCurrent(request) {
    return request.generation === sessionGeneration && request.actor === window.PDC_AUTH_CONTEXT?.userId &&
      request.token === getPdcSupabaseAccessToken() && request.config === window.PDC_SUPABASE_CONFIG &&
      request.service === app.emailVehicleLocationService && writable();
  }
  function ownsDialog(request) { return owner === request && authorityCurrent(request); }
  async function bounded(work, milliseconds) {
    let timer;
    try {
      return await Promise.race([work, new Promise((_, reject) => {
        timer = setTimeout(() => reject(Error('request_timeout')), milliseconds);
      })]);
    } finally { clearTimeout(timer); }
  }
  function matchedVehicle(id) {
    const vehicle = currentVehicle(id, true);
    if (!vehicle) return null;
    const raw = app.emailVehicleLocationRows.find(row => String(row.id || '') === id);
    // Use the canonical snapshot for location, ETA and lifecycle. Display overlays
    // must not override these server fields when authorizing the request.
    if (!eligible(vehicle) || raw.visible_on_board === false || raw.deleted_at ||
      String(raw.lifecycle_state || 'active').toLowerCase() !== 'active' ||
      window.PDC_WORKSHOP_ELIGIBILITY?.scheduleEligibility({ ...raw,
        current_location: String(raw.location_override || '').trim() || raw.current_location,
      }).enabled !== true) throw Error('This vehicle is no longer eligible for workshop booking. Check its location and ETA.');
    return vehicle;
  }
  async function refreshAfterResult(request, saved) {
    request.refreshing = true;
    const planner = window.__workshopDataService;
    try {
      const results = await bounded(Promise.allSettled([
        Promise.resolve().then(() => authorityCurrent(request) ? refreshEmailVehicleLocations() : false),
        Promise.resolve().then(() => authorityCurrent(request) ? planner?.loadSnapshot?.('book_all_stations') : false),
      ]), 60000);
      const plannerFailed = typeof planner?.loadSnapshot === 'function' &&
        (results[1].value === null || results[1].value === false ||
          (typeof planner.getState === 'function' && !['connected_editable', 'connected_read_only'].includes(planner.getState())));
      if (ownsDialog(request) && (results.some(result => result.status === 'rejected') || results[0].value !== true || plannerFailed)) {
        resultHost.insertAdjacentHTML('beforeend', `<p class="book-all-stations-error">${saved ? 'The bookings were saved. ' : ''}Refresh the board to load the updated status.</p>`);
      }
    } catch (_error) {
      if (ownsDialog(request)) resultHost.insertAdjacentHTML('beforeend', `<p class="book-all-stations-error">${saved ? 'The bookings were saved. ' : ''}Refresh the board to load the updated status.</p>`);
    } finally {
      if (pending.get(request.id) === request) pending.delete(request.id);
      if (authorityCurrent(request)) renderIncomingDashboardBoard();
    }
  }
  async function book(id) {
    if (saving || pending.has(id) || !writable()) return;
    const before = currentVehicle(id);
    if (!before || !eligible(before)) return;
    const request = { id, generation: sessionGeneration, actor: window.PDC_AUTH_CONTEXT?.userId,
      token: getPdcSupabaseAccessToken(), config: window.PDC_SUPABASE_CONFIG, service: app.emailVehicleLocationService };
    if (!request.actor || !request.token) return;
    owner = request;
    saving = true;
    pending.set(id, request);
    closeButton.disabled = true;
    dialog.querySelector('[data-book-all-vehicle]').textContent = `Stock ${displayStockNumber(before)} · ${vehicleCustomerName(before)}`;
    resultHost.textContent = 'Finding available bays and booking each station…';
    dialog.showModal();
    renderIncomingDashboardBoard();
    let backgroundRefresh = false;
    try {
      // The server validates this snapshot version under the vehicle lock. Avoid
      // downloading the entire board before every already-loaded vehicle booking.
      let selected = matchedVehicle(id);
      if (!selected) {
        const refreshed = await bounded(Promise.resolve().then(() => refreshEmailVehicleLocations()), 60000);
        if (!ownsDialog(request)) return;
        if (refreshed !== true) throw Error('The vehicle could not be refreshed. No booking request was sent. Refresh the board and try again.');
        selected = matchedVehicle(id);
      }
      if (!selected) throw Error('The refreshed vehicle could not be matched safely. No booking request was sent. Refresh the board and try again.');
      if (!ownsDialog(request)) return;
      let response, result;
      try {
        await bounded((async () => {
          response = await fetch(request.config.url.replace(/\/$/, '') + '/rest/v1/rpc/book_all_vehicle_stations', {
            method: 'POST',
            headers: { apikey: request.config.publishableKey, Authorization: `Bearer ${request.token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ p_vehicle_id: id, p_expected_version: Number(selected.__emailVehicleVersion) }),
          });
          result = await response.json();
        })(), 90000);
      } catch (_error) {
        throw Error('The booking result could not be confirmed. Refresh the board before trying again.');
      }
      if (!ownsDialog(request)) return;
      if (result?.error === 'vehicle_version_conflict') {
        resultHost.innerHTML = '<p class="book-all-stations-error" role="alert">This vehicle changed since the board loaded. No new bookings were saved. The board is refreshing; try again once it has updated.</p>';
        backgroundRefresh = true;
        void refreshAfterResult(request, false);
        return;
      }
      if (!response.ok || result?.ok !== true) throw Error(result?.message || result?.error || 'The stations could not be booked. Refresh the board and try again.');
      resultHost.innerHTML = summaryHtml(result);
      backgroundRefresh = true;
      void refreshAfterResult(request, true);
    } catch (error) {
      const message = error.message === 'request_timeout' ? 'The vehicle could not be refreshed. No booking request was sent. Refresh the board and try again.' : error.message;
      if (ownsDialog(request)) resultHost.innerHTML = `<p class="book-all-stations-error" role="alert">${esc(message)}</p>`;
    } finally {
      if (!backgroundRefresh && pending.get(id) === request) pending.delete(id);
      if (ownsDialog(request)) {
        saving = false;
        closeButton.disabled = false;
        renderIncomingDashboardBoard();
        closeButton.focus();
      } else if (owner === request) {
        owner = null;
        saving = false;
        closeButton.disabled = false;
        dialog.close();
      }
    }
  }
  function resetSession() {
    sessionGeneration++;
    owner = null;
    saving = false;
    pending.clear();
    closeButton.disabled = false;
    dialog.close();
  }
  window.addEventListener?.('pdc-auth-locked', resetSession);
  window.addEventListener?.('pdc-auth-ready', resetSession);
  document.addEventListener('click', event => {
    const button = event.target.closest?.('[data-book-all-stations]');
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    if (!button.disabled) void book(button.dataset.bookAllStations);
  }, true);
  window.PDC_BOOK_ALL_STATIONS = Object.freeze({ eligible, actionHtml });
  if (typeof renderIncomingDashboardBoard === 'function') renderIncomingDashboardBoard();
})();
