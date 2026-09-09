/* Shared Board/Planner presentation: server booking colours and precise Admin input.
 * Does not create local bookings, change completion flags, or widen permissions. */
(() => {
  'use strict';
  function bookingPlans(vehicle = {}) {
    if (vehicle.__emailVehicleServerAuthoritative !== true || !Array.isArray(vehicle.salesWorkshopBookings)) return null;
    return vehicle.salesWorkshopBookings.filter(b => ['queued','planned','started','stoppage'].includes(String(b.status || '').toLowerCase()))
      .map(b => ({ id: b.bookingId, sharedVehicleId: vehicle.__emailVehicleId, vehicleKey: vehicle.stock || vehicle.id,
        stage: b.stageCode, status: b.status, startAt: b.scheduledStartAt, endAt: b.scheduledEndAt,
        actualStartAt: b.actualStartAt, actualEndAt: b.actualEndAt, stoppageReason: b.stoppageReason,
        bayName: b.bayName, sharedVersion: b.version, __serverEndAt: b.scheduledEndAt }));
  }
  function inputMinutes(value, unit, dayMinutes, increment = 15, maximum = 60000) {
    if (String(value).trim() === '') return null;
    const n = Number(value), raw = n * (unit === 'working_days' ? dayMinutes : 60);
    if (!Number.isFinite(n) || n <= 0 || !Number.isFinite(raw) || raw > maximum || raw < increment) return null;
    return Math.round(raw / increment) * increment;
  }
  const api = { bookingPlans, inputMinutes };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd'
      || typeof vehicleWorkshopBookingProjection !== 'function' || window.PDC_WORKSHOP_USABILITY_VERSION) return;
  const oldProjection = vehicleWorkshopBookingProjection;
  vehicleWorkshopBookingProjection = function (v = {}, options = {}) {
    const plans = bookingPlans(v);
    // An unloaded or differently scoped station planner must not replace a
    // complete authenticated Board booking list with an empty local array.
    const result = oldProjection(v, plans === null ? options : { ...options, available: true, plans });
    if (plans !== null) {
      const ends = plans.map(b => Date.parse(b.__serverEndAt)).filter(Number.isFinite);
      result.latestEnd = ends.length ? new Date(Math.max(...ends)) : null;
      result.label = result.latestEnd
        ? `${result.missingStages.length ? 'Latest booking' : 'Est. complete'} ${result.latestEnd.toLocaleString('en-AU', { timeZone:'Australia/Perth',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit' })}`
        : result.bookingRequired ? 'Booking required' : '';
    }
    return result;
  };
  let installed = false;
  function installPlanner() {
    if (installed || typeof bindWorkshopAdminPalette !== 'function' || typeof workshopDispatchSharedAction !== 'function') return;
    const oldDispatch = workshopDispatchSharedAction;
    workshopDispatchSharedAction = async function (...args) {
      const result = await oldDispatch(...args);
      if (result?.ok === true) {
        // Also update other stations' orange icons and post-repair QC readiness.
        // A failed refresh never invents state or turns a failed write into success.
        try { await refreshEmailVehicleLocations(); } catch (_) { /* Existing Refresh control remains available. */ }
      }
      return result;
    };
    bindWorkshopAdminPalette = function (root) {
      const palette = root.querySelector('[data-workshop-admin-palette]');
      if (!palette) return;
      const input = palette.querySelector('[data-workshop-admin-palette-duration]');
      const unit = palette.querySelector('[data-workshop-admin-palette-unit]');
      const tile = palette.querySelector('[data-workshop-admin-palette-tile]');
      const label = palette.querySelector('[data-workshop-admin-palette-label]');
      const update = (normalise = false) => {
        const units = unit?.value || 'hours';
        const minutes = inputMinutes(input?.value, units, WORKSHOP_PLANNER_CONFIG.dayLengthMinutes,
          WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, workshopAdminSafeDurationMinutes());
        input?.setAttribute('aria-invalid', String(minutes === null));
        if (tile) { tile.draggable = minutes !== null; tile.setAttribute('aria-disabled', String(minutes === null)); }
        if (minutes === null) {
          if (label) label.textContent = 'Enter a valid Admin duration';
          return false;
        }
        workshopAdminPaletteDurationMinutes = minutes;
        // Do not rewrite the number on each keystroke: typing 1.5 must not
        // collapse the decimal point and silently become 15 or 5 hours.
        if (normalise && input) input.value = String(Number((minutes / (units === 'working_days' ? WORKSHOP_PLANNER_CONFIG.dayLengthMinutes : 60)).toFixed(4)));
        if (label) label.textContent = `Admin · ${Number((minutes / 60).toFixed(2))} h`;
        if (tile) tile.dataset.adminPaletteDuration = String(minutes);
        return true;
      };
      input?.addEventListener('input', () => update(false));
      input?.addEventListener('change', () => update(true));
      unit?.addEventListener('change', () => update(true));
      tile?.addEventListener('dragstart', event => {
        if (!update(true)) { event.preventDefault(); return; }
        event.dataTransfer.effectAllowed = 'copy';
        event.dataTransfer.setData('application/x-workshop-admin-palette', 'admin');
        event.dataTransfer.setData('application/x-workshop-admin-duration-minutes', String(workshopAdminPaletteDurationMinutes));
        workshopSetDragPreview({ type: 'admin-block', hours: workshopAdminPaletteDurationMinutes / 60 });
      });
      tile?.addEventListener('keydown', event => {
        if (!['Enter',' '].includes(event.key)) return;
        event.preventDefault(); if (update(true)) openWorkshopAdminBlockModal();
      });
      update(false);
    };
    installed = true;
  }
  const oldRender = renderQualityControlPage;
  renderQualityControlPage = function (...args) { installPlanner(); return oldRender(...args); };
  document.addEventListener('load', installPlanner, true);
  installPlanner();
  window.PDC_WORKSHOP_USABILITY_VERSION = '2026.09.09.13';
  window.PDC_WORKSHOP_USABILITY = api;
  if (app.currentView === 'dashboard') renderIncomingDashboardBoard();
})();
