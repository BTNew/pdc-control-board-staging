/* r462 (F75) / r463 (F76): Vehicle slide-out panel for the Vehicle Locations "Table view" (r461).
 *
 * In Table view, clicking a vehicle opens a panel that slides in from the right over the table (the Drop-down view and
 * its cards are unchanged; this file does nothing there). The panel shows the vehicle's own drop-down card, opened
 * (incomingVehicleDetailRow HTML, so every icon, tick, parts colour and station state is exactly today's), bound with
 * r461's bindBoardHandlers (the same buttons the board binds): the station strip and status row, the vehicle details
 * (stock number, vehicle key, key number with Edit / History, job card, Tune report, parts location) and the operations
 * by category (lines, hours, sublets / PO) as the main content.
 * r463 (F76, Craig 22 Oct 09:03): the r462 "Jobs & bookings" list and drag-to-bay are withdrawn. The panel has no
 * drag handles and no bay targets, loads no planner data and never calls moveWorkshopDroppedPlan. Bay moves stay in
 * the Workshop Planner.
 * This file never calls an RPC or fetch itself and writes nothing to storage.
 * Undo: revert the r463 commit.
 */
(function vehicleSlideoutModule(root) {
  'use strict';
  const VERSION = '2026.10.22.r463';
  const api = { VERSION };
  if (typeof module === 'object' && module.exports) module.exports = api;
  const VLT = root?.PDC_VEHICLE_LOCATIONS_TABLE;
  if (!root || !root.document || !VLT || typeof VLT.setDrawerOpener !== 'function' || root.PDC_VEHICLE_SLIDEOUT) {
    if (root && !root.PDC_VEHICLE_SLIDEOUT) root.PDC_VEHICLE_SLIDEOUT = api;
    return;
  }

  // ---------- Browser ----------
  const doc = root.document;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const state = { key: '', bucket: '' };
  const vehicleFor = key => root.vehicleLocationsScreenRows().find(row => root.vehicleKey(row) === key);

  function loadStyles() {
    if (doc.querySelector('link[data-pdc-vehicle-slideout]')) return;
    const link = doc.createElement('link');
    link.rel = 'stylesheet';
    link.href = `pdc-vehicle-slideout.css?vehicle-slideout=${VERSION}`;
    link.dataset.pdcVehicleSlideout = '1';
    doc.head.appendChild(link);
  }

  function ensureShell() {
    let shell = doc.getElementById('vso-shell');
    if (shell) return shell;
    shell = doc.createElement('div');
    shell.id = 'vso-shell';
    shell.innerHTML = '<div class="vso-scrim" data-vso-close></div><aside class="vso-panel" role="dialog" aria-modal="false" aria-label="Vehicle detail"></aside><div class="vso-parity" aria-hidden="true"></div>';
    doc.body.appendChild(shell);
    shell.addEventListener('click', event => { if (event.target.closest('[data-vso-close]')) close(); });
    return shell;
  }
  const cardHtmlFor = (vehicle, bucket) => {
    const workshopProjectionAvailable = root.ensureDashboardWorkshopProjectionReady();
    const workshopPlans = workshopProjectionAvailable && typeof root.workshopLoadPlans === 'function' ? root.workshopLoadPlans() : null;
    return root.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans, workshopProjectionAvailable, subletNavigation: true })
      .replace('<details class="incoming-vehicle-card', '<details open class="incoming-vehicle-card vlt-drawer-card vso-card');
  };

  function render(key, bucket, { keepScroll = false } = {}) {
    const vehicle = vehicleFor(key);
    if (!vehicle) { close(); return false; }
    const shell = ensureShell();
    const panel = shell.querySelector('.vso-panel');
    const scroll = keepScroll ? panel.querySelector('.vso-body')?.scrollTop || 0 : 0;
    const nested = keepScroll ? [...panel.querySelectorAll('.vso-body details details')].map(d => d.open) : [];
    const tile = VLT.TILE[bucket] || [bucket, '', 'unknown', String(bucket || '').toUpperCase()];
    const cardHtml = cardHtmlFor(vehicle, bucket);
    const parts = VLT.splitCard(cardHtml);
    const text = el => (el?.inner || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    const keyNo = text(parts.key) || '—';
    const jobs = (vehicle.pdcJobCardNumbers || []).join(' · ') || vehicle.jobCardNumber || '—';
    const depts = (vehicle.pdcDepartmentCodes || []).map(d => `<em class="vso-dept">${esc(d)}</em>`).join('') || '—';
    panel.innerHTML = `<header class="vso-head">
        <div class="vso-id"><span class="vlt-pill ${esc(tile[2])}">${esc(tile[3])}</span>
          <h3>${esc(root.displayStockNumber(vehicle) || key)}</h3><p>${esc(root.displayVehicle(vehicle) || '')}</p>
          <div class="vso-facts"><span><b>Key</b> ${esc(keyNo)}</span><span><b>JC</b> ${esc(jobs)}</span><span><b>Dept</b> ${depts}</span></div></div>
        <div class="vso-head-actions"><span class="vso-open-slot"></span><button type="button" class="vso-close" data-vso-close aria-label="Close">✕</button></div>
      </header>
      <div class="vso-body">${cardHtml}</div>`;
    const card = panel.querySelector('details.vso-card');
    card.querySelector('summary')?.addEventListener('click', event => { if (!event.target.closest('button, a, input, select, label')) event.preventDefault(); });
    VLT.bindBoardHandlers(panel); // r461's export: the same listeners the board binds today
    const openButton = card.querySelector('[data-open-stock]');
    if (openButton) {
      const copy = openButton.cloneNode(true);
      copy.addEventListener('click', event => { event.stopPropagation(); root.openVehicleCardFromVisibleBoard(copy.dataset.openStock, copy); });
      panel.querySelector('.vso-open-slot').appendChild(copy);
    }
    if (keepScroll) {
      const again = [...panel.querySelectorAll('.vso-body details details')];
      nested.forEach((open, index) => { if (again[index]) again[index].open = open; });
      panel.querySelector('.vso-body').scrollTop = scroll;
    }
    watchOperations(panel);
    return true;
  }

  // Craig 22 Oct 08:07: long operation descriptions are cut with an ellipsis; the full text shows on hover and on focus.
  let opsObserver = null;
  function markTruncated(panel) {
    panel.querySelectorAll('.authenticated-email-operations li > span').forEach(span => {
      const full = span.textContent.replace(/\s+/g, ' ').trim();
      if (!full) return;
      if (!span.title) span.title = full;
      const li = span.parentElement;
      const cut = span.scrollWidth > span.clientWidth + 1;
      if (cut) { li.dataset.vsoFull = full; if (!li.hasAttribute('tabindex')) li.tabIndex = 0; }
      else if (li.dataset.vsoFull) { delete li.dataset.vsoFull; }
    });
  }
  function watchOperations(panel) {
    opsObserver?.disconnect();
    const run = () => (root.requestAnimationFrame || setTimeout)(() => markTruncated(panel));
    run();
    if (typeof root.MutationObserver === 'function') {
      opsObserver = new root.MutationObserver(run);
      const host = panel.querySelector('.vso-body');
      if (host) opsObserver.observe(host, { childList: true, subtree: true });
    }
  }

  function open(key, bucket) {
    state.key = key; state.bucket = bucket;
    if (!render(key, bucket)) return;
    const shell = ensureShell();
    doc.querySelectorAll('#vlt-table-host tr.is-open').forEach(row => row.classList.remove('is-open'));
    doc.querySelector(`#vlt-table-host tr[data-vlt-key="${CSS.escape(key)}"]`)?.classList.add('is-open');
    shell.classList.add('is-open');
    doc.body.classList.add('vso-open');
    shell.querySelector('.vso-close')?.focus({ preventScroll: true });
  }
  // Live refreshes redraw the open panel, keeping its scroll position and open sections.
  function refresh(key, bucket) {
    if (key !== state.key) return;
    state.bucket = bucket;
    render(key, bucket, { keepScroll: true });
    doc.querySelector(`#vlt-table-host tr[data-vlt-key="${CSS.escape(key)}"]`)?.classList.add('is-open');
  }
  function close() {
    if (!state.key && !doc.getElementById('vso-shell')?.classList.contains('is-open')) return;
    state.key = ''; opsObserver?.disconnect();
    const shell = doc.getElementById('vso-shell');
    shell?.classList.remove('is-open');
    doc.body.classList.remove('vso-open');
    VLT.drawerClosed();
  }

  // Parity helper for PDC_VEHICLE_LOCATIONS_TABLE.parity(): draws the panel's card off-screen inside the panel shell
  // (same CSS as the open panel) and returns its station strip. Binds nothing, loads nothing.
  function parityStrip(key, bucket) {
    const vehicle = vehicleFor(key);
    const host = ensureShell().querySelector('.vso-parity');
    if (!vehicle || !host) return null;
    host.innerHTML = `<div class="vso-panel-like"><div class="vso-body">${cardHtmlFor(vehicle, bucket)}</div></div>`;
    return host.querySelector('.vso-card .pdc-station-strip');
  }
  function parityDone() { const host = doc.querySelector('#vso-shell .vso-parity'); if (host) host.innerHTML = ''; }

  loadStyles();
  VLT.setDrawerOpener({ open, refresh, close, parityStrip, parityDone });
  root.PDC_VEHICLE_SLIDEOUT = Object.freeze({ ...api, open, close, refresh, parityStrip, state });
}(typeof window !== 'undefined' ? window : globalThis));
