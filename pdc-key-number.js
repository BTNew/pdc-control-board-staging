/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r460 (F73, change request from Craig, 22 Oct 2026): the vehicle key number, editable by controllers and administrators,
   with a full audit trail (who, when, old value, new value, source: edit / release / import).
   Builds on the existing field vehicles.key_number (filled by the service import and shown as the board's 'Key' column).
   - The vehicle drop-down gets a "Key No." cell next to Stock No.: controllers / administrators get an inline Edit (type the
     key, Enter or Save; Esc or Cancel); everyone else sees it read only. History shows the last changes from the audit.
   - Where the key is already shown (the board's Key column), the recorded key wins over the Tune job-card value.
   - Saves go through set_pdc_vehicle_key_number_460 (expected vehicle version + idempotency key); a later service import
     still updates the key as before and is audited as 'import'.
   Loads after pdc-service-locations.js and pdc-parts-eta.js. styles.css and app.js are untouched (CSS lives here).
   r472 (F85, Craig 22 Oct 10:20): saving a key tag number from the vehicle card ("Save changes") locked the card for
   about 18 s behind "Refreshing exact vehicle identity…". The card's save merged the card's own vehicle object into the
   raw staging snapshot row, so the row's id became the board key (the Tune / PMG id) instead of the vehicle UUID; the
   card could then not find its exact UUID + Stock row and re-read the whole board to rebind. This file keeps the raw
   rows raw (the server's receipt values on the exact UUID row, then the server's own read-back row) and, for a
   key-number-only save, confirms the read-back in the background instead of holding the card. The exact UUID + Stock
   checks are unchanged; a contradicting read-back still says so. Undo: revert the r472 commit. */
(() => {
  'use strict';
  const VERSION = '2026.10.22.r460';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const idKey = value => String(value ?? '').trim().toLowerCase();
  /** Key as typed -> stored form ('' clears). Mirrors the server: letters, digits, - and _, up to 32, not all zeros. */
  function normaliseKey(value) {
    return String(value ?? '').replace(/\s+/g, '').toUpperCase();
  }
  function keyProblem(value) {
    const key = normaliseKey(value);
    if (!key) return '';
    if (!/^[A-Z0-9][A-Z0-9_-]{0,31}$/.test(key)) return 'Use letters and numbers only (up to 32).';
    if (/^0+$/.test(key)) return '0 means no key. Leave it empty to clear the key.';
    return '';
  }
  /** r575: the server sentence is blue. A raw 23505 is never this text. */
  function clashMessage(value) {
    const text = String(value || '');
    return /^Key \S+ is already on stock /.test(text) ? text : '';
  }
  const when = value => {
    const d = new Date(value || '');
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }) + ' AWST';
  };
  const SOURCE = { edit: 'Edited', release: 'Set at release', import: 'Service import', system: 'System' };
  function historyHtml(history) {
    const rows = (Array.isArray(history) ? history : []).slice(0, 5);
    if (!rows.length) return '<small class="pdc-keyno-history-empty">No key changes recorded since r460.</small>';
    return '<ul class="pdc-keyno-history">' + rows.map(h => `<li><b>${esc(h.old || '—')} → ${esc(h.new || '—')}</b> `
      + `<span>${esc(SOURCE[h.source] || h.source)} by ${esc(h.by || 'unknown')} · ${esc(when(h.at))}</span></li>`).join('') + '</ul>';
  }
  /** The drop-down cell. state: {vehicleId, key, canEdit, editing, message, history} */
  function keyCellHtml(state) {
    const vid = esc(state.vehicleId || '');
    const key = String(state.key || '').trim();
    const clash = clashMessage(state.message);
    const msgClass = clash ? 'pdc-keyno-msg is-clash' : 'pdc-keyno-msg';
    if (state.editing && state.canEdit) {
      return `<div class="pdc-keyno-cell is-editing" data-pdc-key-cell="${vid}"><b>Key No.</b><span class="pdc-keyno-edit">`
        + `<input type="text" inputmode="text" maxlength="32" autocomplete="off" data-pdc-key-input="${vid}" value="${esc(key)}" aria-label="Key number" placeholder="e.g. 125" />`
        + `<button type="button" class="pdc-keyno-save" data-pdc-key-save="${vid}">Save</button><button type="button" data-pdc-key-cancel="${vid}">Cancel</button>`
        + `<small class="${msgClass}" role="status">${esc(clash || state.message || 'Leave empty to clear. Every change is recorded.')}</small></span></div>`;
    }
    return `<div class="pdc-keyno-cell" data-pdc-key-cell="${vid}"><b>Key No.</b><span><strong class="pdc-keyno-value">${esc(key || '—')}</strong>`
      + (state.canEdit && vid ? `<button type="button" class="pdc-keyno-edit-button" data-pdc-key-edit="${vid}" title="Edit the key number (recorded in the audit trail)">Edit</button>`
        + `<button type="button" class="pdc-keyno-history-button" data-pdc-key-history="${vid}">History</button>` : '')
      + (state.message ? `<small class="${clash ? msgClass : 'pdc-keyno-msg is-ok'}" role="status">${esc(state.message)}</small>` : '')
      + (state.history ? historyHtml(state.history) : '') + '</span></div>';
  }
  /** Put the Key No. cell after the Stock No. cell of a drop-down's detail grid (or first when there is none). */
  function decorateRow(html, state) {
    const text = String(html || '');
    if (!text.includes('incoming-vehicle-detail-grid') || text.includes('data-pdc-key-cell=')) return text;
    const cell = keyCellHtml(state);
    const stock = /(<div class="incoming-vehicle-detail-grid[^"]*">\s*<div><b>Stock No\.<\/b><span>[\s\S]*?<\/span><\/div>)/;
    if (stock.test(text)) return text.replace(stock, `$1${cell}`);
    return text.replace(/(<div class="incoming-vehicle-detail-grid[^"]*">)/, `$1${cell}`);
  }
  /** Identity cells (the board's Key column): the recorded key wins over a job-card value. */
  function preferRecordedKey(cells, recordedKey) {
    const key = String(recordedKey || '').trim();
    if (!key || !Array.isArray(cells)) return cells;
    return cells.map(cell => (cell && cell.label === 'Key' ? { ...cell, value: key } : cell));
  }
  const CSS = [
    '.pdc-keyno-cell>span{display:flex;flex-wrap:wrap;align-items:center;gap:6px}',
    '.pdc-keyno-cell .pdc-keyno-value{font-size:14px;letter-spacing:.02em}',
    '.pdc-keyno-cell button{font:inherit;font-size:11px;font-weight:650;padding:2px 8px;border-radius:5px;border:1px solid #94a3b8;background:#fff;color:#1e293b;cursor:pointer}',
    '.pdc-keyno-cell .pdc-keyno-save{background:#1d4ed8;border-color:#1d4ed8;color:#fff}',
    '.pdc-keyno-cell input{font:inherit;width:7.5em;padding:3px 6px;border:1px solid #64748b;border-radius:5px;text-transform:uppercase}',
    '.pdc-keyno-cell .pdc-keyno-msg{flex-basis:100%;color:#64748b;font-size:11px}.pdc-keyno-cell .pdc-keyno-msg.is-error{color:#b91c1c}.pdc-keyno-cell .pdc-keyno-msg.is-ok{color:#166534}.pdc-keyno-cell .pdc-keyno-msg.is-clash{color:#1d4ed8}',
    '.pdc-keyno-history{flex-basis:100%;margin:2px 0 0;padding:0;list-style:none;font-size:11px;color:#334155}.pdc-keyno-history li{display:flex;gap:6px;flex-wrap:wrap}',
    '.pdc-keyno-history-empty{flex-basis:100%;color:#64748b;font-size:11px}',
  ].join('');
  // r472: pure helpers (tested in test_key_save_identity_472.js).
  const rawRowId = row => [row?.id, row?.__emailVehicleId].map(idKey).find(id => UUID.test(id)) || '';
  /** Receipt applied: the exact UUID row keeps every raw field and takes only the raw receipt overlay. */
  function rawRowsAfterReceipt(rowsBefore, vehicleId, rawOverlay) {
    const id = idKey(vehicleId);
    if (!Array.isArray(rowsBefore) || !UUID.test(id) || !rawOverlay || typeof rawOverlay !== 'object') return null;
    return rowsBefore.map(row => (rawRowId(row) === id ? { ...row, ...rawOverlay, id: row.id } : row));
  }
  /** Read-back applied: the exact UUID row becomes the server's own row (nothing from the card is mixed in). */
  function rawRowsAfterReadback(rowsBefore, serverRow, overlay = rows => rows) {
    const id = idKey(serverRow?.id);
    if (!Array.isArray(rowsBefore) || !UUID.test(id)) return null;
    const fresh = overlay([{ ...serverRow }])[0] || { ...serverRow };
    return rowsBefore.map(row => (rawRowId(row) === id ? fresh : row));
  }
  /** Only a key-number-only card save (no salesperson change) confirms its read-back in the background. */
  function keyOnlySave(requestedCode, detailChanges) {
    const fields = Object.keys(detailChanges && typeof detailChanges === 'object' ? detailChanges : {});
    return !String(requestedCode || '').trim() && fields.length === 1 && fields[0] === 'key_number';
  }
  const api = { VERSION, R472: '2026.10.22.r472', R575: '2026.10.27.r575', normaliseKey, keyProblem, clashMessage, keyCellHtml, decorateRow, preferRecordedKey, historyHtml, CSS, rawRowsAfterReceipt, rawRowsAfterReadback, keyOnlySave };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_KEY_NUMBER_VERSION) return;
  window.PDC_KEY_NUMBER_VERSION = VERSION;
  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  const token = () => window.__pdcCachedAccessToken;
  async function rpc(name, body) {
    if (!token() || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    const text = await response.text();
    if (!response.ok) { let m = text; try { m = JSON.parse(text).message || text; } catch (_) { /* raw */ } throw new Error(String(m || response.status)); }
    return JSON.parse(text || 'null');
  }
  let canEdit = false, roleLoaded = false;
  const ui = new Map(); // vehicle id -> {editing, message, history, key, version}
  function vehicleId(vehicle) {
    const ids = [vehicle?.__emailVehicleId, vehicle?.id, vehicle?.permanentVehicleId];
    try { if (typeof vehicleWorkshopDetailCanonicalId === 'function') ids.unshift(vehicleWorkshopDetailCanonicalId(vehicle)); } catch (_) { /* optional */ }
    return ids.map(idKey).find(id => UUID.test(id)) || '';
  }
  const recordedKey = vehicle => String(vehicle?.keyNumber ?? vehicle?.key_number ?? '').trim();
  const vehicleVersion = vehicle => Number(vehicle?.__emailVehicleVersion || vehicle?.version || 0);
  function findVehicle(vid) {
    try { return (window.app?.data || (typeof app !== 'undefined' ? app.data : []) || []).find(v => vehicleId(v) === vid) || null; } catch (_) { return null; }
  }
  function rerender() {
    try { if (typeof refreshAllViews === 'function') refreshAllViews(); } catch (_) { /* next render */ }
  }
  /** Re-draw just the open drop-down cells (keeps the input focused state simple). */
  function paint(vid) {
    const vehicle = findVehicle(vid);
    const st = ui.get(vid) || {};
    document.querySelectorAll(`[data-pdc-key-cell="${vid}"]`).forEach(el => {
      el.outerHTML = keyCellHtml({ vehicleId: vid, key: st.key ?? recordedKey(vehicle), canEdit, editing: st.editing, message: st.message, history: st.history });
    });
    if (st.editing) { const input = document.querySelector(`[data-pdc-key-input="${vid}"]`); if (input) { input.focus(); input.select(); } }
  }
  if (typeof vehicleIdentityCells === 'function') {
    const prior = vehicleIdentityCells;
    vehicleIdentityCells = vehicle => preferRecordedKey(prior(vehicle), recordedKey(vehicle));
  }
  if (typeof incomingVehicleDetailRow === 'function') {
    const prior = incomingVehicleDetailRow;
    incomingVehicleDetailRow = (vehicle, ...args) => {
      const html = prior(vehicle, ...args);
      try {
        const vid = vehicleId(vehicle);
        const st = ui.get(vid) || {};
        return decorateRow(html, { vehicleId: vid, key: recordedKey(vehicle), canEdit: canEdit && Boolean(vid), editing: st.editing, message: st.message, history: st.history });
      } catch (_) { return html; }
    };
  }
  // r472 (F85): keep the authenticated snapshot rows raw after a card save (see the header).
  if (typeof applyAuthoritativeVehicleReceiptToState === 'function' && typeof authoritativeVehicleRawOverlay === 'function') {
    const prior = applyAuthoritativeVehicleReceiptToState;
    applyAuthoritativeVehicleReceiptToState = (...args) => {
      const before = app.emailVehicleLocationRows;
      const out = prior(...args);
      try {
        const rows = out ? rawRowsAfterReceipt(before, out.expected?.vehicleId, authoritativeVehicleRawOverlay(out.patched, out.expected)) : null;
        if (rows) app.emailVehicleLocationRows = rows;
      } catch (_) { /* leave app.js's result */ }
      return out;
    };
  }
  if (typeof applyAuthoritativeVehicleReadbackRow === 'function') {
    const prior = applyAuthoritativeVehicleReadbackRow;
    applyAuthoritativeVehicleReadbackRow = (row = {}, ...rest) => {
      const before = app.emailVehicleLocationRows;
      const mapped = prior(row, ...rest);
      try {
        const overlay = typeof applyPendingSharedWorkStateOverlays === 'function' ? applyPendingSharedWorkStateOverlays : undefined;
        const rows = mapped ? rawRowsAfterReadback(before, row, overlay) : null;
        if (rows) app.emailVehicleLocationRows = rows;
      } catch (_) { /* leave app.js's result */ }
      return mapped;
    };
  }
  if (typeof reconcileAuthoritativeVehicleReceipt === 'function') {
    const prior = reconcileAuthoritativeVehicleReceipt;
    reconcileAuthoritativeVehicleReceipt = (result, vehicle, requestedCode, detailChanges, ...rest) => {
      if (!keyOnlySave(requestedCode, detailChanges)) return prior(result, vehicle, requestedCode, detailChanges, ...rest);
      // The server's receipt already names this exact UUID and its new version. The card opens straight away
      // ("Saved online; refreshing…"); the read-back runs behind it, and a contradicting read-back still says so.
      void Promise.resolve().then(() => prior(result, vehicle, requestedCode, detailChanges, ...rest)).then(readback => {
        if (readback?.status !== 'contradictory') return;
        try { pdcNotify('The key tag number did not read back as saved. Close and reopen the vehicle to see the current key tag.'); } catch (_) { /* toast unavailable */ }
        try { if (document.querySelector('#vehicle-modal')?.hidden === false) renderDetail(); } catch (_) { /* next render */ }
      }).catch(() => { /* the next board refresh reconciles */ });
      return Promise.resolve({ status: 'pending', vehicle });
    };
  }
  async function loadRole() {
    if (String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'fitter') return; // r616 (F231): Fitters bay only
    if (!token()) return;
    try {
      const data = await rpc('get_pdc_vehicle_key_number_460', { p_vehicle_id: null });
      const next = data?.ok === true && data.can_edit === true;
      roleLoaded = true;
      if (next !== canEdit) { canEdit = next; rerender(); }
    } catch (_) { /* keep read only; the next poll retries */ }
  }
  async function save(vid) {
    const input = document.querySelector(`[data-pdc-key-input="${vid}"]`);
    const st = ui.get(vid) || {};
    const typed = input ? input.value : '';
    const problem = keyProblem(typed);
    const msg = document.querySelector(`[data-pdc-key-cell="${vid}"] .pdc-keyno-msg`);
    if (problem) { if (msg) { msg.textContent = problem; msg.classList.add('is-error'); } return; }
    const vehicle = findVehicle(vid);
    let version = vehicleVersion(vehicle);
    if (!version) { try { version = Number((await rpc('get_pdc_vehicle_key_number_460', { p_vehicle_id: vid }))?.vehicle_version || 0); } catch (_) { version = 0; } }
    if (msg) { msg.textContent = 'Saving…'; msg.classList.remove('is-error'); }
    st.pending = st.pending || (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()));
    try {
      const r = await rpc('set_pdc_vehicle_key_number_460', { p_vehicle_id: vid, p_expected_vehicle_version: version, p_key_number: normaliseKey(typed), p_idempotency_key: st.pending });
      if (r?.ok !== true) {
        st.pending = null;
        const clash = clashMessage(r?.message);
        const text = clash
          || (r?.code === 'vehicle_version_conflict' ? 'This vehicle changed since the board loaded. Close and reopen it, then try again.'
          : r?.code === 'key_number_in_use' ? 'Another active PMB vehicle already has this key tag.'
          : r?.code === 'not_authorized' ? 'Only controllers and administrators can change the key.'
          : (r?.message || `Not saved (${r?.code || 'error'}).`));
        if (msg) {
          msg.textContent = text;
          msg.classList.toggle('is-clash', Boolean(clash));
          msg.classList.toggle('is-error', !clash);
        }
        return;
      }
      const d = r.data || {};
      if (vehicle) { vehicle.keyNumber = String(d.key_number || ''); if (d.vehicle_version_after) vehicle.__emailVehicleVersion = Number(d.vehicle_version_after); }
      const also = Array.isArray(d.also_on) && d.also_on.length ? ` Also on ${d.also_on.map(x => x.stock_number).join(', ')}.` : '';
      ui.set(vid, { editing: false, key: String(d.key_number || ''), message: d.changed === false ? 'No change.' : `Saved.${also}` });
      rerender(); paint(vid);
    } catch (error) {
      const clash = clashMessage(error?.message);
      if (msg) {
        msg.textContent = clash || `Not saved: ${error.message || error}. Try again.`;
        msg.classList.toggle('is-clash', Boolean(clash));
        msg.classList.toggle('is-error', !clash);
      }
    }
  }
  async function showHistory(vid) {
    try {
      const data = await rpc('get_pdc_vehicle_key_number_460', { p_vehicle_id: vid });
      const st = ui.get(vid) || {};
      ui.set(vid, { ...st, history: Array.isArray(data?.history) ? data.history : [] });
      paint(vid);
    } catch (_) { /* leave as is */ }
  }
  for (const type of ['mousedown', 'pointerdown', 'touchstart', 'dblclick']) {
    document.addEventListener(type, event => { if (event.target?.closest?.('.pdc-keyno-cell')) event.stopPropagation(); }, true);
  }
  document.addEventListener('click', event => {
    const el = event.target?.closest?.('[data-pdc-key-edit],[data-pdc-key-save],[data-pdc-key-cancel],[data-pdc-key-history]');
    if (!el) return;
    event.preventDefault(); event.stopPropagation();
    const vid = idKey(el.dataset.pdcKeyEdit || el.dataset.pdcKeySave || el.dataset.pdcKeyCancel || el.dataset.pdcKeyHistory);
    if (!UUID.test(vid)) return;
    if (el.dataset.pdcKeyEdit) { if (!canEdit) return; ui.set(vid, { ...(ui.get(vid) || {}), editing: true, message: '', pending: null }); paint(vid); }
    else if (el.dataset.pdcKeySave) save(vid);
    else if (el.dataset.pdcKeyCancel) { ui.set(vid, { editing: false }); paint(vid); }
    else if (el.dataset.pdcKeyHistory) showHistory(vid);
  }, true);
  document.addEventListener('keydown', event => {
    const input = event.target?.closest?.('[data-pdc-key-input]');
    if (!input) return;
    event.stopPropagation();
    const vid = idKey(input.dataset.pdcKeyInput);
    if (event.key === 'Enter') { event.preventDefault(); save(vid); }
    else if (event.key === 'Escape') { event.preventDefault(); ui.set(vid, { editing: false }); paint(vid); }
  }, true);
  // Typing in the summary must not toggle the <details> drop-down (space / enter on a summary child).
  document.addEventListener('keyup', event => { if (event.target?.closest?.('[data-pdc-key-input]')) event.stopPropagation(); }, true);
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);
  // r490: skip the 4 s retry once the role has loaded, and do not poll while the tab is hidden
  // (coming back to the tab reloads the role straight away).
  loadRole();
  setTimeout(() => { if (!roleLoaded) loadRole(); }, 4000);
  setInterval(() => { if (document.visibilityState !== 'hidden') loadRole(); }, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') loadRole(); });
})();
