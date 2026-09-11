/* Book outstanding workshop stations as one server-validated transaction. */
(() => {
  'use strict';
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || window.PDC_BOOK_ALL_STATIONS) return;

  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const writable = () => ['operator', 'administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const pending = new Set();
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
    if (vehicle.deleted_at || vehicle.deletedAt || String(vehicle.lifecycle_state || vehicle.lifecycleState || 'active').toLowerCase() !== 'active') return false;
    const location = vehicle.current_location || vehicle.pdcAutomaticLocation || vehicle.currentLocation || vehicle.pdcLocation;
    return window.PDC_WORKSHOP_ELIGIBILITY?.scheduleEligibility({ ...vehicle, current_location: location }).enabled === true;
  }
  function actionHtml(vehicle, existingAction = '') {
    if (!eligible(vehicle)) return existingAction;
    // Keep transfer, QC and Open controls; replace only the old source-only badge.
    const retained = existingAction.replace(/<span class="badge neutral">(?:[^<]*Read only|Pilbara Service Review · R\/O loaded)<\/span>/g, '');
    const busy = pending.has(vehicleId(vehicle));
    return `${retained}<button class="primary incoming-book-all-stations" type="button" data-book-all-stations="${esc(vehicleId(vehicle))}" ${busy ? 'disabled aria-busy="true"' : ''} title="Book each outstanding workshop station in its next available bay, with 5 hours between this vehicle’s jobs. Sublet is excluded."><span>${busy ? 'Booking stations…' : 'Book all stations'}</span></button>`;
  }
  const dialog = document.createElement('dialog');
  dialog.className = 'book-all-stations-dialog';
  dialog.setAttribute('aria-labelledby', 'book-all-stations-title');
  dialog.innerHTML = '<h2 id="book-all-stations-title">Book all stations</h2><p data-book-all-vehicle></p><div data-book-all-result role="status" aria-live="polite"></div><footer><button type="button" class="small-button" data-book-all-close>Close</button></footer>';
  document.body.appendChild(dialog);
  const resultHost = dialog.querySelector('[data-book-all-result]');
  const closeButton = dialog.querySelector('[data-book-all-close]');
  let saving = false;
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
  async function book(id) {
    if (saving || pending.has(id) || !writable()) return;
    const before = currentVehicle(id);
    if (!before || !eligible(before)) return;
    saving = true;
    pending.add(id);
    closeButton.disabled = true;
    dialog.querySelector('[data-book-all-vehicle]').textContent = `Stock ${displayStockNumber(before)} · ${vehicleCustomerName(before)}`;
    resultHost.textContent = 'Finding available bays and booking each station…';
    dialog.showModal();
    renderIncomingDashboardBoard();
    try {
      if (await refreshEmailVehicleLocations() !== true) throw Error('The vehicle could not be refreshed. No booking request was sent. Refresh the board and try again.');
      const selected = currentVehicle(id, true);
      if (!selected) throw Error('The refreshed vehicle could not be matched safely. No booking request was sent. Refresh the board and try again.');
      if (!eligible(selected)) throw Error('This vehicle is no longer eligible for workshop booking. Check its location and ETA.');
      const config = window.PDC_SUPABASE_CONFIG;
      const token = getPdcSupabaseAccessToken();
      if (!token) throw Error('Please sign in again.');
      let response, result;
      try {
        response = await fetch(config.url.replace(/\/$/, '') + '/rest/v1/rpc/book_all_vehicle_stations', {
          method: 'POST',
          headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_vehicle_id: id, p_expected_version: Number(selected.__emailVehicleVersion) }),
        });
        result = await response.json();
      } catch (_error) {
        throw Error('The booking result could not be confirmed. Refresh the board before trying again.');
      }
      if (!response.ok || result?.ok !== true) throw Error(result?.message || result?.error || 'The stations could not be booked. Refresh the board and try again.');
      resultHost.innerHTML = summaryHtml(result);
      try {
        const refreshed = await refreshEmailVehicleLocations();
        if (window.__workshopDataService?.loadSnapshot) await window.__workshopDataService.loadSnapshot('book_all_stations');
        if (refreshed !== true) throw Error('refresh_failed');
      } catch (_error) {
        resultHost.insertAdjacentHTML('beforeend', '<p class="book-all-stations-error">The bookings were saved. Refresh the board to load the updated status.</p>');
      }
    } catch (error) {
      resultHost.innerHTML = `<p class="book-all-stations-error" role="alert">${esc(error.message)}</p>`;
    } finally {
      saving = false;
      pending.delete(id);
      closeButton.disabled = false;
      renderIncomingDashboardBoard();
      closeButton.focus();
    }
  }
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
