/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
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
 * r473 (F86, Craig 22 Oct 10:2x): the top of the panel loses the station-icon strip and the PMB status / PMB stream /
 * Book all stations box (the card's summary row; the table row keeps all of them). An "Open Vehicle" button under the
 * stock / key / JC line opens the vehicle card (what clicking the stock number did); the stock number is plain text.
 * When the vehicle card closes, the open panel and the table are drawn again from the data, so nothing the card drew
 * (for example its drop-downs) can stay painted over the panel's operation lines or a table row. Display only.
 * This file never calls an RPC or fetch itself and writes nothing to storage.
 * Undo: revert the r473 commit (r463's panel comes back).
 *
 * r485 (F98, Craig 22 Oct: approved hiding the Drop-down view on condition that Clear stoppage is not lost): a vehicle
 * with an active stoppage shows a "STOPPAGE" box at the top of the panel: each reason row (the label and detail the
 * drop-down's STOPPAGES / Fix First list shows) with that list's own action button, taken verbatim from app.js
 * fixFirstRowsHtml() (as wrapped by pdc-qc-rework.js, so an eligible PMB stoppage shows "Return to QC" instead of
 * "Clear stoppage"). The buttons are bound with app.js bindFixFirstRows(), so Clear stoppage runs the same
 * clearPriorityStoppage() (same note prompt, same clear_vehicle_stoppage_422 call and messages); Return to QC is
 * handled by pdc-qc-rework.js's own document listener (markVehicleReadyForQualityControl). The action buttons are
 * shown only to the roles the server lets clear a stoppage (operator, administrator: clear_vehicle_stoppage_422);
 * everyone else sees the reasons only. This file still calls no RPC or fetch itself and writes nothing to storage.
 */
(function vehicleSlideoutModule(root) {
  'use strict';
  const VERSION = '2026.10.22.r485'; // r485 (F98): stoppage box with Clear stoppage / Return to QC
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

  // ---- r485 (F98): the drop-down's STOPPAGES / Fix First rows for this vehicle, with their own action buttons ----
  // Same roles as the server check in clear_vehicle_stoppage_422 (pdc_user_roles operator / administrator).
  const STOPPAGE_ACTION_ROLES = Object.freeze(['operator', 'administrator']);
  const canActOnStoppage = () => STOPPAGE_ACTION_ROLES.includes(String(root.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase());
  function stoppageRowsFor(key) {
    if (typeof root.workflowPriorityRows !== 'function' || typeof root.fixFirstRowsHtml !== 'function') return [];
    try { return root.workflowPriorityRows().filter(row => row?.vehicle && root.vehicleKey(row.vehicle) === key); } catch (_) { return []; }
  }
  // The action buttons are taken verbatim from fixFirstRowsHtml(); they are flat <button>…</button> tags (app.js and
  // pdc-qc-rework.js), one row wrap per row, in row order, so a string split keeps this pure and testable.
  const ACTION_BUTTON = /<button\b[^>]*\bclass="[^"]*\bfix-first-clear\b[^"]*"[^>]*>[^<]*<\/button>/g;
  function stoppageHtml(key) {
    const rows = stoppageRowsFor(key);
    if (!rows.length) return '';
    const wraps = String(root.fixFirstRowsHtml(rows) || '').split('<div class="fix-first-row-wrap">').slice(1);
    const act = canActOnStoppage();
    const items = rows.map((row, index) => {
      const severity = /^(danger|warning|info)$/.test(row.severity) ? row.severity : 'warning';
      const actions = act ? ((wraps[index] || '').match(ACTION_BUTTON) || []).join('') : '';
      return `<li class="vso-stoppage-row fix-first-${severity}"><div><strong>${esc(row.label || 'Action needed')}</strong>${row.detail ? `<span>${esc(row.detail)}</span>` : ''}</div>${actions ? `<div class="vso-stoppage-actions">${actions}</div>` : ''}</li>`;
    });
    const note = act ? '' : '<p class="vso-stoppage-note">Only an operator or administrator can clear a stoppage.</p>';
    return `<section class="vso-stoppages" aria-label="Stoppage"><h4>STOPPAGE</h4><ul>${items.join('')}</ul>${note}</section>`;
  }

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
          <div class="vso-facts"><span><b>Key</b> ${esc(keyNo)}</span><span><b>JC</b> ${esc(jobs)}</span><span><b>Dept</b> ${depts}</span></div>
          <div class="vso-open-row"></div></div>
        <div class="vso-head-actions"><button type="button" class="vso-close" data-vso-close aria-label="Close">✕</button></div>
      </header>
      ${stoppageHtml(key)}<div class="vso-body">${cardHtml}</div>`;
    const card = panel.querySelector('details.vso-card');
    card.querySelector('summary')?.addEventListener('click', event => { if (!event.target.closest('button, a, input, select, label')) event.preventDefault(); });
    VLT.bindBoardHandlers(panel); // r461's export: the same listeners the board binds today
    // r485: Clear stoppage -> app.js clearPriorityStoppage() via bindFixFirstRows(), exactly as on the drop-down list.
    const stoppages = panel.querySelector('.vso-stoppages');
    if (stoppages && typeof root.bindFixFirstRows === 'function') root.bindFixFirstRows(stoppages);
    // r473: the card's own stock button tells the Open Vehicle button which vehicle to open; then every stock number in
    // the panel becomes plain text and the summary row (station strip, PMB status / stream, Book all stations) goes.
    const openStock = card.querySelector('[data-open-stock]')?.dataset.openStock || '';
    if (openStock) {
      const button = doc.createElement('button');
      button.type = 'button'; button.className = 'vso-open-vehicle'; button.dataset.vsoOpenVehicle = '';
      button.textContent = 'Open Vehicle'; button.title = 'Open this vehicle';
      button.addEventListener('click', event => { event.stopPropagation(); root.openVehicleCardFromVisibleBoard(openStock, button); });
      panel.querySelector('.vso-open-row').appendChild(button);
    }
    panel.querySelectorAll('.vso-body [data-open-stock]').forEach(stockButton => {
      const plain = doc.createElement('span');
      plain.className = 'vso-stock-text'; plain.textContent = stockButton.textContent;
      stockButton.replaceWith(plain);
    });
    const summary = card.querySelector(':scope > summary');
    if (summary) { summary.replaceChildren(); summary.hidden = true; summary.classList.add('vso-summary-removed'); }
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

  // r473: when the vehicle card (#vehicle-modal) closes, draw the open panel and the table again from the data.
  function watchVehicleCard() {
    const modal = doc.getElementById('vehicle-modal');
    if (!modal || typeof root.MutationObserver !== 'function') return;
    let wasOpen = modal.hidden === false;
    new root.MutationObserver(() => {
      const isOpen = modal.hidden === false;
      if (wasOpen && !isOpen) {
        try { if (VLT.state?.view === 'table' && typeof VLT.render === 'function') VLT.render(); } catch (_) { /* next render */ }
        if (state.key) refresh(state.key, state.bucket);
      }
      wasOpen = isOpen;
    }).observe(modal, { attributes: true, attributeFilter: ['hidden'] });
  }

  loadStyles();
  watchVehicleCard();
  VLT.setDrawerOpener({ open, refresh, close, parityStrip, parityDone });
  root.PDC_VEHICLE_SLIDEOUT = Object.freeze({ ...api, open, close, refresh, parityStrip, state });
}(typeof window !== 'undefined' ? window : globalThis));
