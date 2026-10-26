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
 *
 * r496 (F109, Craig 22 Oct 19:16): edit hours and move lines between jobs inside the panel, instead of the separate
 * Vehicle detail window. The operations heading's "Edit jobs & hours" button becomes "Edit" (inline) plus a small
 * "Open full editor" link (the old window, unchanged and still there for Add line, Edit line and Best slot). "Edit" draws
 * app.js's own Work & bookings rows (renderVehicleWorkshopWorkPage, the same inputs and data attributes the window uses)
 * in place of the read-only list, with every button stripped, so only the hours inputs and the Work category / Station
 * selectors are live. Changes are staged in the panel; Save runs the window's own save paths in order:
 * saveVehicleWorkshopLineHoursBatch (Save all hours, save_vehicle_workshop_line_hours_batch_768), then for each moved line
 * saveVehicleWorkCategory (set_vehicle_work_category) or moveVehicleWorkshopLineStage, each followed by app.js's own
 * reload of this one vehicle. Cancel drops the drafts. Same role gate (vehicleWorkshopCanEditLines: operator,
 * administrator), same server checks, no new SQL.
 * Speed: nothing runs per vehicle when the board or the panel is drawn. The one extra read
 * (loadVehicleWorkshopDetail, get_vehicle_workshop_detail_scoped) happens only when "Edit" is pressed, for that one
 * vehicle; after a save only this panel is drawn again (never the table or the board).
 * Undo: revert the r496 commit (the "Edit jobs & hours" button and the window come back exactly as before).
 */
(function vehicleSlideoutModule(root) {
  'use strict';
  const VERSION = '2026.10.27.r558'; // r558 (F172): "More details" opens the vehicle card (SP, label, override location, …)
  // r496: the panel's slim copy of the Work & bookings rows. Every <button> is removed (Add line, Edit line, Best slot,
  // Remove, Mark done, Split, drag handles, booking links); a drag handle's line number stays as plain text. What is left
  // live is only the hours inputs and the Work category / Station selectors, with app.js's own data attributes.
  function slimWorkPage(html) {
    return String(html || '')
      .replace(/<button\b[^>]*\bclass="vehicle-workshop-line-number"[^>]*>([^<]*)<\/button>/g, '<span class="vehicle-workshop-line-number">$1</span>')
      .replace(/<button\b[^>]*>[\s\S]*?<\/button>/g, '')
      .replace(/\sdraggable="true"/g, '');
  }
  const api = { VERSION, slimWorkPage };
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

  // ---- r496 (F109): edit hours and move lines between jobs inside the panel ----
  // Every write is one of app.js's own Work & bookings functions; this file only stages the changes and calls them.
  const EDIT_NEEDS = Object.freeze(['vehicleWorkshopCanEditLines', 'vehicleWorkshopDetailCanonicalId', 'loadVehicleWorkshopDetail',
    'renderVehicleWorkshopWorkPage', 'saveVehicleWorkshopLineHoursBatch', 'vehicleWorkshopHoursBatchSyncDrafts',
    'vehicleWorkshopHoursBatchDirty', 'saveVehicleWorkCategory', 'moveVehicleWorkshopLineStage', 'selectedVehicle']);
  const MOVE_SELECT = '[data-vehicle-workshop-line-category], [data-vehicle-workshop-line-stage]';
  const HOURS_INPUT = '[data-vehicle-workshop-hours-batch-input]';
  const edit = { key: '', moves: new Map(), busy: false, loading: false, note: '', loads: 0 };
  const editReady = () => {
    if (!root.app || !EDIT_NEEDS.every(name => typeof root[name] === 'function')) return false;
    try { return root.vehicleWorkshopCanEditLines() === true; } catch (_) { return false; }
  };
  const editVehicle = key => { try { return root.selectedVehicle(key) || vehicleFor(key) || null; } catch (_) { return vehicleFor(key) || null; } };
  const canonicalIdFor = vehicle => { try { return vehicle ? String(root.vehicleWorkshopDetailCanonicalId(vehicle) || '') : ''; } catch (_) { return ''; } };
  // app.js's save functions act on the selected vehicle (selectedVehicle() with no argument), exactly as in the window.
  // They are only called while the vehicle card is closed (no vehicleModalIdentity), and only for this panel's vehicle.
  function selectForEdit(key) {
    const app = root.app;
    if (!app || app.vehicleModalIdentity) return false;
    app.selectedStock = key;
    try { return root.vehicleKey(root.selectedVehicle() || {}) === key; } catch (_) { return false; }
  }
  const editPage = () => doc.querySelector('#vso-shell .vso-panel .vso-edit [data-vehicle-workshop-hours-batch-page]');
  const moveKey = select => `${select.matches('[data-vehicle-workshop-line-category]') ? 'category' : 'stage'}|${select.dataset.lineKey || ''}`;
  const defaultValue = select => ([...select.options].find(option => option.defaultSelected) || select.options[0] || {}).value ?? '';
  function editDirty(page = editPage()) {
    if (edit.moves.size) return true;
    if (!page) return false;
    try { return root.vehicleWorkshopHoursBatchDirty(page) === true; } catch (_) { return false; }
  }
  function discardEdit() {
    const vehicle = edit.key ? editVehicle(edit.key) : null;
    const id = canonicalIdFor(vehicle);
    if (id) root.app?.vehicleWorkshopHoursBatchDrafts?.delete?.(id);
    if (edit.key && root.app) root.app.vehicleWorkshopHoursBatchMessage = '';
    edit.key = ''; edit.moves.clear(); edit.loading = false;
  }
  // true when it is fine to leave the vehicle being edited (nothing typed, or the user agrees to drop it).
  function leaveEdit() {
    if (!edit.key) return true;
    if (edit.busy) return false;
    if (editDirty() && typeof root.confirm === 'function' && !root.confirm('Discard the hours and job moves you have not saved?')) return false;
    discardEdit();
    return true;
  }
  const redraw = key => { if (state.key === key) render(key, state.bucket, { keepScroll: true }); };
  function startEdit(key) {
    if (edit.busy || !editReady()) return false;
    const vehicle = editVehicle(key);
    const id = canonicalIdFor(vehicle);
    if (!id || !selectForEdit(key)) return false;
    discardEdit();
    edit.key = key; edit.note = '';
    root.app.vehicleWorkshopHoursBatchDrafts?.delete?.(id);
    root.app.vehicleWorkshopHoursBatchMessage = '';
    // "Loading…" goes into the drawn block in place (no new card, so the card's own open/toggle summary read is not
    // triggered again while this read is in flight).
    edit.loading = true;
    const block = state.key === key ? doc.querySelector('#vso-shell .vso-panel .vso-body .authenticated-email-operations[data-vso-edit-ready]') : null;
    if (block) {
      block.querySelectorAll('.vso-edit, .vso-edit-msg.is-done, [data-vso-edit-toggle]').forEach(node => node.remove());
      mountEditor(block, key, vehicle, block.dataset.vsoIdentity || key);
    } else redraw(key);
    // The only extra read: this one vehicle's current lines and versions, the same call the window makes when it opens.
    edit.loads += 1;
    const pending = root.loadVehicleWorkshopDetail(vehicle, { force: true });
    Promise.resolve(pending).catch(() => null).then(() => { edit.loading = false; if (edit.key === key && !edit.busy) redraw(key); });
    return true;
  }
  function cancelEdit(key) {
    if (edit.busy) return false;
    discardEdit(); edit.note = '';
    redraw(key);
    return true;
  }
  function openFullEditor(identity) {
    if (!leaveEdit()) return false;
    edit.note = '';
    return typeof root.openAuthenticatedOperationWorkshop === 'function' ? root.openAuthenticatedOperationWorkshop(identity) : false;
  }
  async function saveEdit(key) {
    const page = editPage();
    if (edit.busy || edit.key !== key || !page || !editDirty(page)) return false;
    if (!selectForEdit(key)) { edit.note = 'Close the vehicle card first. Nothing was saved.'; redraw(key); return false; }
    edit.busy = true; edit.note = 'Saving…';
    let ok = true; const notes = [];
    try {
      redraw(key); // panel only: shows the busy state
      const hoursPage = editPage();
      if (hoursPage && root.vehicleWorkshopHoursBatchDirty(hoursPage) === true) {
        const button = hoursPage.querySelector('[data-vso-edit-act="save"]');
        const changed = hoursPage.querySelectorAll(`${HOURS_INPUT}.vso-changed`).length;
        ok = (await root.saveVehicleWorkshopLineHoursBatch(button)) === true;
        // app.js's own message on a refusal (conflict, invalid hours); a short count when it worked.
        notes.push(ok ? `${changed} hour${changed === 1 ? '' : 's'} change${changed === 1 ? '' : 's'}.` : String(root.app.vehicleWorkshopHoursBatchMessage || ''));
      }
      let moved = 0;
      for (const [id, move] of ok ? [...edit.moves] : []) {
        redraw(key); // fresh selectors carry the versions app.js has just reloaded
        const select = [...(editPage()?.querySelectorAll(MOVE_SELECT) || [])].find(candidate => moveKey(candidate) === id);
        if (!select || ![...select.options].some(option => option.value === move.value)) { ok = false; notes.push('A line changed in another session. Check it and try again.'); break; }
        select.value = move.value;
        if (!selectForEdit(key)) { ok = false; notes.push('Close the vehicle card first.'); break; }
        const done = move.kind === 'category' ? await root.saveVehicleWorkCategory(select) : await root.moveVehicleWorkshopLineStage(select);
        if (done !== true) { ok = false; break; }
        edit.moves.delete(id); moved += 1;
      }
      if (moved) notes.push(`${moved} line${moved === 1 ? '' : 's'} moved.`);
    } catch (_) {
      ok = false;
    } finally {
      edit.busy = false;
    }
    if (ok) {
      discardEdit();
      edit.note = ['Saved.', ...notes].filter(Boolean).join(' ');
    } else {
      edit.note = notes.filter(Boolean).join(' ') || 'Not everything was saved. Check the lines and try again.';
    }
    redraw(key);
    return ok;
  }
  const barHtml = (busy, dirty) => `<div class="vso-edit-bar" role="group" aria-label="Edit hours and jobs">
      <div class="vso-edit-title"><strong>Edit hours and jobs</strong><small>Type the hours or pick another job for a line. Nothing changes until you press Save.</small></div>
      <div class="vso-edit-actions"><button type="button" class="vso-edit-save" data-vso-edit-act="save"${busy || !dirty ? ' disabled' : ''}>${busy ? 'Saving…' : 'Save'}</button><button type="button" class="vso-edit-cancel" data-vso-edit-act="cancel"${busy ? ' disabled' : ''}>Cancel</button></div>
      ${edit.note ? `<span class="vso-edit-msg" role="status" aria-live="polite">${esc(edit.note)}</span>` : ''}
    </div>`;
  const moreHtml = '<p class="vso-edit-more">Add line, Edit line and Best slot: <button type="button" class="vso-link" data-vso-edit-act="full">Open full editor</button></p>';
  function mountEditor(block, key, vehicle, identity) {
    const grid = block.querySelector('.authenticated-operation-station-grid');
    if (grid) grid.hidden = true;
    const wrap = doc.createElement('div');
    wrap.className = 'vso-edit';
    wrap.dataset.vsoEdit = key;
    const cached = root.app.vehicleWorkshopDetailCache?.get?.(canonicalIdFor(vehicle));
    if (edit.loading || !cached || cached.status === 'loading') {
      wrap.innerHTML = `<div data-vehicle-workshop-hours-batch-page>${barHtml(true, false)}<p class="vso-edit-wait" role="status">Loading this vehicle's jobs and hours…</p></div>${moreHtml}`;
    } else if (cached.status !== 'ready') {
      wrap.innerHTML = `<div data-vehicle-workshop-hours-batch-page>${barHtml(true, false)}<p class="vso-edit-wait" role="alert">${esc(cached.message || 'This vehicle\'s jobs could not be loaded. Nothing was changed.')}</p></div>${moreHtml}`;
    } else {
      wrap.innerHTML = `${slimWorkPage(root.renderVehicleWorkshopWorkPage(vehicle))}${moreHtml}`;
      const page = wrap.querySelector('[data-vehicle-workshop-hours-batch-page]');
      if (page) page.insertAdjacentHTML('afterbegin', barHtml(edit.busy, false));
    }
    // Anything still clickable that is not ours goes (belt and braces: slimWorkPage already removed every button).
    wrap.querySelectorAll('button:not([data-vso-edit-act])').forEach(button => button.remove());
    const heading = block.querySelector('.authenticated-email-operations-heading');
    if (heading) heading.after(wrap); else block.prepend(wrap);
    const page = wrap.querySelector('[data-vehicle-workshop-hours-batch-page]');
    const save = wrap.querySelector('[data-vso-edit-act="save"]');
    const sync = () => { if (save) save.disabled = edit.busy || !editDirty(page); };
    page.querySelectorAll(HOURS_INPUT).forEach(input => {
      const mark = () => input.classList.toggle('vso-changed', String(input.value ?? '').trim() !== String(input.dataset.originalHours ?? '').trim());
      mark();
      input.disabled = edit.busy;
      input.addEventListener('input', () => {
        if (selectForEdit(key)) root.vehicleWorkshopHoursBatchSyncDrafts(page); // app.js keeps the draft, as in the window
        mark(); sync();
      });
    });
    page.querySelectorAll(MOVE_SELECT).forEach(select => {
      const id = moveKey(select);
      const original = defaultValue(select);
      const staged = edit.moves.get(id);
      if (staged && [...select.options].some(option => option.value === staged.value)) select.value = staged.value;
      const mark = () => select.classList.toggle('vso-changed', select.value !== original);
      mark();
      select.disabled = edit.busy;
      select.addEventListener('change', event => {
        event.stopPropagation();
        if (select.value === original) edit.moves.delete(id);
        else edit.moves.set(id, { kind: id.startsWith('category|') ? 'category' : 'stage', value: select.value });
        mark(); sync();
      });
    });
    sync();
    save?.addEventListener('click', event => { event.stopPropagation(); void saveEdit(key); });
    wrap.querySelector('[data-vso-edit-act="cancel"]')?.addEventListener('click', event => { event.stopPropagation(); cancelEdit(key); });
    wrap.querySelector('[data-vso-edit-act="full"]')?.addEventListener('click', event => { event.stopPropagation(); openFullEditor(identity); });
  }
  // The operations heading: "Edit jobs & hours" (which opened the window) becomes "Edit" + "Open full editor". Shown only
  // where app.js drew that button (the same vehicleWorkshopCanEditLines() role check). Idempotent per drawn block.
  function decorateOperations(panel, key) {
    const block = panel.querySelector('.vso-body .authenticated-email-operations');
    if (!block || block.hasAttribute('data-vso-edit-ready')) return;
    block.setAttribute('data-vso-edit-ready', '');
    const old = block.querySelector('[data-auth-operation-work]');
    if (!old) return;
    const identity = old.dataset.authOperationWork || key;
    block.dataset.vsoIdentity = identity;
    const vehicle = editVehicle(key);
    const inline = editReady() && !!canonicalIdFor(vehicle);
    const editing = inline && edit.key === key;
    const tools = doc.createElement('span');
    tools.className = 'vso-ops-tools';
    tools.innerHTML = `${inline && !editing ? '<button type="button" class="vso-edit-toggle" data-vso-edit-toggle>Edit</button>' : ''}<button type="button" class="vso-link" data-vso-full-editor>Open full editor</button>`;
    old.replaceWith(tools);
    tools.querySelector('[data-vso-edit-toggle]')?.addEventListener('click', event => { event.stopPropagation(); startEdit(key); });
    tools.querySelector('[data-vso-full-editor]').addEventListener('click', event => { event.stopPropagation(); openFullEditor(identity); });
    if (editing) mountEditor(block, key, vehicle, identity);
    else if (edit.note) block.querySelector('.authenticated-email-operations-heading')?.insertAdjacentHTML('afterend', `<p class="vso-edit-msg is-done" role="status">${esc(edit.note)}</p>`);
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
      button.textContent = 'More details'; button.title = 'SP, key tag, label, email update, override location, blocked vehicle and team notes';
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
    decorateOperations(panel, key); // r496: Edit / Open full editor; the inline editor when this vehicle is being edited
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
    // r496: a block another script draws again gets its Edit / Open full editor (and the open editor) back.
    const run = () => (root.requestAnimationFrame || setTimeout)(() => { if (state.key) decorateOperations(panel, state.key); markTruncated(panel); });
    run();
    if (typeof root.MutationObserver === 'function') {
      opsObserver = new root.MutationObserver(run);
      const host = panel.querySelector('.vso-body');
      if (host) opsObserver.observe(host, { childList: true, subtree: true });
    }
  }

  function open(key, bucket) {
    if (edit.key && edit.key !== key && !leaveEdit()) return; // r496: unsaved edits on another vehicle
    if (state.key !== key) edit.note = '';
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
    if (!leaveEdit()) return; // r496: unsaved hours / job moves: ask before dropping them
    edit.note = '';
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
  root.PDC_VEHICLE_SLIDEOUT = Object.freeze({ ...api, open, close, refresh, parityStrip, state, edit });
}(typeof window !== 'undefined' ? window : globalThis));
