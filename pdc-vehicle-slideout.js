/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r462 (F75) / r463 (F76): Vehicle slide-out panel for the Vehicle Locations "Table view" (r461).
 *
 * In Table view, clicking a vehicle opens a panel that slides in from the right over the table (the Drop-down view and
 * its cards are unchanged; this file does nothing there). The panel shows the vehicle's own drop-down card, opened
 * (incomingVehicleDetailRow HTML, so every icon, tick, parts colour and station state is exactly today's), bound with
 * r461's bindBoardHandlers (the same buttons the board binds): the station strip and status row, the vehicle details
 * (stock number, vehicle key, key number with Edit / History, job card, Tune report, parts location) and the operations
 * by category (lines, hours, sublets / PO) as the main content.
 * r463 (F76, Craig 22 Oct 09:03): the r462 "Jobs & bookings" list and its pointer drag-to-bay are withdrawn.
 * r565 (F179) drags a chip in edit mode and calls moveWorkshopDroppedPlan on a bay drop. Bay rules stay in
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
 * r496 (F109, Craig 22 Oct 19:16): edit hours and move lines between jobs inside the panel. "Edit" plus
 * "Open full editor" (the old window, still there for Add line, Edit line and Best slot).
 * r565 (F179, Craig 27 Oct 08:08): Edit keeps this same chip list. It does not open the Work & bookings
 * layout. In edit mode a line or job chip can be dragged onto another station or bay. The line's hours go
 * with it: a station drop calls saveVehicleWorkCategory (set_vehicle_work_category, which extends or shortens
 * the job). A bay drop then calls moveWorkshopDroppedPlan or scheduleWorkshopVehicle, so bay, technician and
 * close-gaps rules stay in those functions. Save still writes hour edits through saveVehicleWorkshopLineHoursBatch.
 * A completed line is green, with who and when. A controller (operator or administrator) can tick a
 * line completed; the tick is setPanelLineCompletion (set_panel_line_completion_565). The same roles can
 * override a whole station (setStationCompletionOverride). This file still calls no RPC or fetch itself.
 * Speed: drawing the board reads nothing extra. Opening the panel may read the completion list once
 * (loadPanelLineCompletions) when that function exists. loadVehicleWorkshopDetail runs only when Edit is pressed,
 * for that one vehicle. A save redraws only this panel.
 * Undo: revert the r565 commit (r496's editor comes back).
 */
(function vehicleSlideoutModule(root) {
  'use strict';
  const VERSION = '2026.10.27.r578'; // r578 (F192): compact green complete tick and station override. r565 (F179): edit stays on the chip list. r560 (F174): More details opens the vehicle card.
  // r496: the panel's slim copy of the Work & bookings rows. Kept so the full editor's markup can still be reduced.
  // r565 does not use it for Edit: Edit stays on the chip list.
  function slimWorkPage(html) {
    return String(html || '')
      .replace(/<button\b[^>]*\bclass="vehicle-workshop-line-number"[^>]*>([^<]*)<\/button>/g, '<span class="vehicle-workshop-line-number">$1</span>')
      .replace(/<button\b[^>]*>[\s\S]*?<\/button>/g, '')
      .replace(/\sdraggable="true"/g, '');
  }
  // Pure description of a chip drop. The browser half calls the existing save and planner functions with this plan.
  // Hours travel on the plan. Completed chips do not move. Overlap and close-gaps are not decided here.
  function chipHours(value) {
    if (value == null || value === '') return null;
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? n : null;
  }
  function chipMovePlan(chip, target) {
    const kind = chip?.kind === 'job' ? 'job' : 'line';
    const hours = chipHours(chip?.hours);
    const fromCategory = String(chip?.category || '');
    const category = String(target?.category || fromCategory);
    const stage = String(target?.stage || chip?.stage || '');
    const bay = Number(target?.bay);
    if (chip?.completed === true) return { action: 'none', reason: 'completed', hours };
    if (!target || (target.kind !== 'station' && target.kind !== 'bay')) return { action: 'none', reason: 'target', hours };
    if (kind === 'job') {
      if (target.kind !== 'bay' || !Number.isInteger(bay) || bay < 1) return { action: 'none', reason: 'bay', hours };
      return { action: 'move-booking', hours, category, stage, bay, categoryChanged: false, planId: String(chip.planId || ''), bookingId: String(chip.bookingId || ''), lineKey: '' };
    }
    const lineKey = String(chip?.lineKey || '');
    if (!/^(source|manual):[0-9a-f-]{36}$/i.test(lineKey)) return { action: 'none', reason: 'line', hours };
    if (target.kind === 'station') {
      if (!category || category === fromCategory) return { action: 'none', reason: 'same', hours, lineKey, category, stage };
      return { action: 'category', lineKey, hours, category, stage, bay: 0, categoryChanged: true };
    }
    if (!Number.isInteger(bay) || bay < 1) return { action: 'none', reason: 'bay', hours, lineKey };
    return { action: 'bay', lineKey, hours, category, stage, bay, categoryChanged: category !== fromCategory, planId: String(chip.planId || ''), bookingId: String(chip.bookingId || '') };
  }
  const api = { VERSION, slimWorkPage, chipMovePlan };
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

  // ---- r496 / r565: edit hours in the chip list, and drag a line onto another job or bay ----
  // Writes go through app.js and the planner. This file does not decide overlaps or close-gaps.
  const EDIT_NEEDS = Object.freeze(['vehicleWorkshopCanEditLines', 'vehicleWorkshopDetailCanonicalId', 'loadVehicleWorkshopDetail',
    'saveVehicleWorkshopLineHoursBatch', 'vehicleWorkshopHoursBatchSyncDrafts',
    'vehicleWorkshopHoursBatchDirty', 'saveVehicleWorkCategory', 'selectedVehicle']);
  const HOURS_INPUT = '[data-vehicle-workshop-hours-batch-input]';
  const CONTROLLER_ROLES = Object.freeze(['operator', 'administrator']);
  const STATION_MOVE = Object.freeze({
    bus_mechanical: { category: 'BUS_MECHANICAL', stage: 'BUS_4X4' },
    bus_accessories: { category: 'BUS_ACCESSORIES', stage: 'BUS_4X4' },
    bus_electrical: { category: 'BUS_ELECTRICAL', stage: 'BUS_4X4' },
    bus_qa: { category: 'BUS_QA', stage: 'BUS_4X4' },
    bus_pit: { category: 'BUS_PIT', stage: 'PIT_INSPECTION' },
    pitinspection: { category: 'BUS_PIT', stage: 'PIT_INSPECTION' },
    tint: { category: 'TINT', stage: 'TINT' },
    hoist: { category: 'HOIST', stage: 'HOIST' },
    fitting: { category: 'FITTING', stage: 'FITTING' },
    fabrication: { category: 'FABRICATION', stage: 'FABRICATION' },
    electrical: { category: 'ELECTRICAL', stage: 'ELECTRICAL' },
    tyre: { category: 'TYRE', stage: 'TYRE' },
    sublet: { category: 'SUBLET', stage: 'SUBLET' },
  });
  const edit = { key: '', moves: new Map(), busy: false, loading: false, note: '', loads: 0, completionFor: '', completionRows: [], stationRows: [], completionGen: 0 };
  const WORK_KEY_FOR_STAGE = Object.freeze({
    BUS_4X4: 'bus4x4', BUS_MECHANICAL: 'bus4x4', BUS_ACCESSORIES: 'bus4x4', BUS_ELECTRICAL: 'bus4x4', BUS_QA: 'bus4x4',
    TINT: 'tint', HOIST: 'hoist', FITTING: 'fitting', FABRICATION: 'fabrication', ELECTRICAL: 'electrical', TYRE: 'tyre', SUBLET: 'sublet', PARTS: 'parts',
  });
  const workKeyFor = stage => WORK_KEY_FOR_STAGE[String(stage || '').toUpperCase()] || '';
  let dragChip = null;
  const isController = () => CONTROLLER_ROLES.includes(String(root.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase());
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
    if (editDirty() && typeof root.confirm === 'function' && !root.confirm('Discard the hours you have not saved?')) return false;
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
    const changed = page.querySelectorAll(`${HOURS_INPUT}.vso-changed`).length;
    edit.busy = true; edit.note = 'Saving…';
    let ok = true; const notes = [];
    try {
      if (root.vehicleWorkshopHoursBatchDirty(page) === true) {
        const button = page.querySelector('[data-vso-edit-act="save"]');
        ok = (await root.saveVehicleWorkshopLineHoursBatch(button)) === true;
        notes.push(ok ? `${changed} hour${changed === 1 ? '' : 's'} change${changed === 1 ? '' : 's'}.` : String(root.app.vehicleWorkshopHoursBatchMessage || ''));
      }
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
      <div class="vso-edit-title"><strong>Edit hours and jobs</strong><small>Drag a line onto another job or bay. The hours move with it. Hour changes wait for Save.</small></div>
      <div class="vso-edit-actions"><button type="button" class="vso-edit-save" data-vso-edit-act="save"${busy || !dirty ? ' disabled' : ''}>${busy ? 'Saving…' : 'Save'}</button><button type="button" class="vso-edit-cancel" data-vso-edit-act="cancel"${busy ? ' disabled' : ''}>Cancel</button></div>
      ${edit.note ? `<span class="vso-edit-msg" role="status" aria-live="polite">${esc(edit.note)}</span>` : ''}
    </div>`;
  const moreHtml = '<p class="vso-edit-more">Add line, Edit line and Best slot: <button type="button" class="vso-link" data-vso-edit-act="full">Open full editor</button></p>';
  function mountEditor(block, key, vehicle, identity) {
    const grid = block.querySelector('.authenticated-operation-station-grid');
    if (grid) grid.hidden = false;
    const wrap = doc.createElement('div');
    wrap.className = 'vso-edit';
    wrap.dataset.vsoEdit = key;
    const cached = root.app.vehicleWorkshopDetailCache?.get?.(canonicalIdFor(vehicle));
    const waiting = edit.loading || !cached || cached.status === 'loading';
    const failed = !waiting && cached.status !== 'ready';
    const note = failed
      ? `<p class="vso-edit-wait" role="alert">${esc(cached.message || 'This vehicle\'s jobs could not be loaded. Nothing was changed.')}</p>`
      : waiting ? '<p class="vso-edit-wait" role="status">Loading this vehicle\'s jobs and hours…</p>' : '';
    wrap.innerHTML = `<div data-vehicle-workshop-hours-batch-page>${barHtml(edit.busy || waiting, false)}${note}${moreHtml}</div>`;
    const heading = block.querySelector('.authenticated-email-operations-heading');
    if (heading) heading.after(wrap); else block.prepend(wrap);
    const page = wrap.querySelector('[data-vehicle-workshop-hours-batch-page]');
    if (grid && page) {
      page.appendChild(grid);
      const more = page.querySelector('.vso-edit-more');
      if (more) page.appendChild(more);
    }
    const save = wrap.querySelector('[data-vso-edit-act="save"]');
    const sync = () => { if (save) save.disabled = edit.busy || waiting || !editDirty(page); };
    wrap._vsoSync = sync;
    save?.addEventListener('click', event => { event.stopPropagation(); void saveEdit(key); });
    wrap.querySelector('[data-vso-edit-act="cancel"]')?.addEventListener('click', event => { event.stopPropagation(); cancelEdit(key); });
    wrap.querySelector('[data-vso-edit-act="full"]')?.addEventListener('click', event => { event.stopPropagation(); openFullEditor(identity); });
    sync();
  }
  function whenLabel(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    try {
      return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
    } catch (_) { return ''; }
  }
  function hoursText(value) {
    if (value == null || value === '' || !Number.isFinite(Number(value)) || Number(value) < 0) return '';
    return String(Number(value));
  }
  function detailFor(vehicle) {
    const id = canonicalIdFor(vehicle);
    const cached = id ? root.app?.vehicleWorkshopDetailCache?.get?.(id) : null;
    return cached?.status === 'ready' ? cached.detail : null;
  }
  function lineRecords(vehicle) {
    const map = new Map();
    const detail = detailFor(vehicle);
    const sources = [];
    if (Array.isArray(detail?.job_card_lines)) sources.push(...detail.job_card_lines);
    if (Array.isArray(vehicle?.pdcQcOperationLines)) sources.push(...vehicle.pdcQcOperationLines);
    if (Array.isArray(vehicle?.pdcEmailOperationLines)) sources.push(...vehicle.pdcEmailOperationLines);
    for (const line of sources) {
      const sourceId = String(line.source_line_id || line.operation_line_id || line.sourceLineId || '').trim();
      const identity = String(line.line_identity || line.workshopLineKey || line.lineIdentity || (sourceId ? `source:${sourceId}` : ''));
      const key = sourceId || identity.replace(/^(source|manual):/, '');
      if (!key) continue;
      const prev = map.get(key) || {};
      const hours = line.estimated_hours ?? line.estimatedHours;
      map.set(key, {
        lineKey: identity || prev.lineKey || '',
        hours: hours == null || hours === '' ? prev.hours : Number(hours),
        category: line.work_category || prev.category || '',
        stage: line.stage_code || line.stageCode || prev.stage || '',
        categoryVersion: line.category_version ?? prev.categoryVersion ?? 0,
        workKey: line.work_key || line.summaryStationKey || prev.workKey || '',
        adjustmentId: line.adjustmentId || line.adjustment_id || prev.adjustmentId || '',
        adjustmentVersion: line.adjustmentVersion ?? line.adjustment_version ?? prev.adjustmentVersion ?? 0,
        completed: line.completed === true || prev.completed === true,
        completedBy: line.completed_by || line.completedBy || prev.completedBy || '',
        completedAt: line.completed_at || line.completedAt || prev.completedAt || '',
      });
    }
    const bookings = Array.isArray(detail?.bookings) ? detail.bookings : [];
    return { lines: map, bookings };
  }
  function tickRow(lineKey) {
    return (edit.completionRows || []).find(row => row.line_identity === lineKey) || null;
  }
  function bookingPerson(booking) {
    if (!booking) return '';
    return [booking.technician_name, booking.assignee_name, booking.assignee, booking.technician_email, booking.completed_by]
      .map(value => String(value || '').trim()).find(Boolean) || '';
  }
  function stationBookings(bookings, category, stage) {
    return bookings.filter(booking => {
      const status = String(booking?.status || '').toLowerCase();
      if (['cancelled', 'deleted'].includes(status)) return false;
      const cat = String(booking.work_category || '');
      const stg = String(booking.stage_code || booking.stage || '').toUpperCase();
      if (category && cat && cat !== category) return false;
      if (stage && stg && stg !== stage) return false;
      return true;
    });
  }
  function readChip(el) {
    const input = el.querySelector?.(HOURS_INPUT);
    const hours = input && String(input.value ?? '').trim() !== '' ? input.value : el.dataset.vsoHours;
    return {
      kind: el.dataset.vsoKind || 'line',
      lineKey: el.dataset.vsoLineKey || '',
      hours,
      category: el.dataset.vsoCategory || '',
      stage: el.dataset.vsoStage || '',
      categoryVersion: el.dataset.vsoCategoryVersion || '0',
      planId: el.dataset.vsoPlanId || '',
      bookingId: el.dataset.vsoBookingId || '',
      completed: el.classList.contains('is-complete'),
      el,
    };
  }
  function perthParts(iso) {
    const date = iso ? new Date(iso) : new Date();
    const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Perth', year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    const clock = new Intl.DateTimeFormat('en-GB', { timeZone: 'Australia/Perth', hour: '2-digit', minute: '2-digit', hour12: false }).format(date);
    const [hour, minute] = clock.split(':').map(Number);
    return { dateKey: day, startMinutes: iso ? (hour * 60 + minute) : (8 * 60) };
  }
  function planFor(plan) {
    if (typeof root.workshopLoadPlans !== 'function') return null;
    let rows = [];
    try { rows = root.workshopLoadPlans() || []; } catch (_) { return null; }
    const id = canonicalIdFor(editVehicle(state.key));
    return rows.find(row => {
      if (!row || row.status === 'completed') return false;
      if (plan.planId && row.id === plan.planId) return true;
      if (plan.bookingId && (row.sharedBookingId === plan.bookingId || row.id === plan.bookingId)) return true;
      const sameVehicle = row.vehicleKey === state.key || row.vehicleId === id;
      const sameStage = String(row.stage || '').toUpperCase() === String(plan.stage || '').toUpperCase();
      const sameCat = !plan.category || !row.workCategory || row.workCategory === plan.category;
      return Boolean(sameVehicle && sameStage && sameCat && (row.sharedBookingId || row.id));
    }) || null;
  }
  async function placeOnBay(plan) {
    const found = planFor(plan);
    const when = perthParts(found?.startAt);
    if (found && typeof root.moveWorkshopDroppedPlan === 'function') {
      const moved = await root.moveWorkshopDroppedPlan(found.id, plan.stage, plan.bay, when.dateKey, when.startMinutes);
      if (moved === false) { edit.note = 'That bay did not take the job.'; return false; }
      return true;
    }
    if (typeof root.scheduleWorkshopVehicle === 'function') {
      const scheduled = await root.scheduleWorkshopVehicle({
        planId: found?.id || '',
        vehicleKeyValue: state.key,
        stage: plan.stage,
        bay: plan.bay,
        dateKey: when.dateKey,
        startMinutes: when.startMinutes,
        hoursValue: plan.hours,
        workCategoryValue: plan.category,
      });
      if (scheduled === false) { edit.note = 'That bay did not take the job.'; return false; }
      return true;
    }
    if (plan.categoryChanged) { edit.note = 'Moved. The hours stay with the line. Bay placement stays in Workshop Planner.'; return true; }
    edit.note = 'Nothing was moved.';
    return false;
  }
  async function applyDrop(chip, target) {
    const plan = chipMovePlan(chip, target);
    if (plan.action === 'none') {
      edit.note = plan.reason === 'same' ? 'That line is already in this job.' : plan.reason === 'completed' ? 'Completed work stays where it is.' : 'Nothing was moved.';
      dragChip = null;
      redraw(state.key);
      return false;
    }
    if (edit.busy || !selectForEdit(state.key)) return false;
    edit.busy = true;
    edit.note = 'Moving…';
    let ok = true;
    try {
      const page = editPage();
      if (page && root.vehicleWorkshopHoursBatchDirty(page) === true) {
        ok = (await root.saveVehicleWorkshopLineHoursBatch(page.querySelector('[data-vso-edit-act="save"]'))) === true;
        if (!ok) edit.note = String(root.app?.vehicleWorkshopHoursBatchMessage || 'The hours were not saved, so the line stayed put.');
      }
      if (ok && plan.lineKey && (plan.action === 'category' || plan.categoryChanged)) {
        const select = {
          value: plan.category,
          disabled: false,
          dataset: { lineKey: plan.lineKey, categoryVersion: String(chip.categoryVersion || 0) },
          closest() { return editPage(); },
        };
        ok = (await root.saveVehicleWorkCategory(select)) === true;
        if (!ok) edit.note = 'The line was not moved.';
      }
      if (ok && (plan.action === 'bay' || plan.action === 'move-booking')) ok = await placeOnBay(plan);
    } catch (_) {
      ok = false;
      edit.note = 'The line was not moved.';
    } finally {
      edit.busy = false;
      dragChip = null;
    }
    if (ok && (!edit.note || edit.note === 'Moving…')) edit.note = 'Moved. The hours stay with the line.';
    redraw(state.key);
    return ok;
  }
  function currentDragChip() {
    const el = dragChip?.el;
    if (el?.isConnected) return readChip(el);
    return dragChip?.chip || null;
  }
  function bindDrop(el, targetFor) {
    el.addEventListener('dragover', event => {
      if (!dragChip) return;
      if (el.dataset.vsoBay == null && event.target?.closest?.('[data-vso-bay]')) return;
      event.preventDefault();
      if (el.dataset.vsoBay != null) event.stopPropagation();
      el.classList.add('is-drop');
    });
    el.addEventListener('dragleave', () => el.classList.remove('is-drop'));
    el.addEventListener('drop', event => {
      if (el.dataset.vsoBay == null && event.target?.closest?.('[data-vso-bay]')) return;
      event.preventDefault();
      event.stopPropagation();
      el.classList.remove('is-drop');
      const chip = currentDragChip();
      if (!chip) return;
      void applyDrop(chip, targetFor());
    });
  }
  function bindHours(input, page) {
    const mark = () => input.classList.toggle('vso-changed', String(input.value ?? '').trim() !== String(input.dataset.originalHours ?? '').trim());
    mark();
    input.disabled = edit.busy;
    input.addEventListener('input', () => {
      if (selectForEdit(edit.key)) root.vehicleWorkshopHoursBatchSyncDrafts(page);
      mark();
      page.closest('.vso-edit')?._vsoSync?.();
    });
  }
  async function toggleCompletion(vehicleId, lineKey, completed) {
    if (!isController() || edit.busy || typeof root.setPanelLineCompletion !== 'function') return false;
    edit.completionGen += 1;
    edit.busy = true;
    let result = null;
    try { result = await root.setPanelLineCompletion(vehicleId, lineKey, completed); }
    catch (_) { result = { ok: false }; }
    finally { edit.busy = false; }
    if (result?.ok === true) {
      const prev = tickRow(lineKey) || {};
      edit.completionRows = (edit.completionRows || []).filter(row => row.line_identity !== lineKey).concat([{
        line_identity: lineKey,
        completed: result.completed === true,
        actor_email: result.actor_email || prev.actor_email || '',
        actor_role: result.actor_role || prev.actor_role || '',
        acted_at: result.acted_at || prev.acted_at || '',
        version: result.version || prev.version || 0,
      }]);
      edit.note = completed ? 'Line marked completed.' : 'Completion removed.';
    } else {
      edit.note = result?.error === 'controller_required' ? 'Only a workshop controller can tick a line.' : 'The tick was not saved.';
    }
    redraw(state.key);
    return result?.ok === true;
  }
  async function toggleStation(vehicleId, workKey, completed) {
    if (!isController() || edit.busy || !workKey || typeof root.setStationCompletionOverride !== 'function') return false;
    edit.completionGen += 1;
    edit.busy = true;
    let result = null;
    try { result = await root.setStationCompletionOverride(vehicleId, workKey, completed); }
    catch (_) { result = { ok: false }; }
    finally { edit.busy = false; }
    if (result?.ok === true) {
      edit.stationRows = (edit.stationRows || []).filter(row => row.work_key !== workKey).concat([{
        work_key: workKey,
        complete: result.completed === true,
        override: result.completed === true,
        override_email: result.actor_email || '',
        acted_at: result.acted_at || '',
      }]);
      edit.note = completed ? 'Station marked complete.' : 'Station override removed.';
    } else {
      edit.note = result?.error === 'controller_required' ? 'Only a workshop controller can override a station.' : 'The station override was not saved.';
    }
    redraw(state.key);
    return result?.ok === true;
  }
  function bayNumbers(move) {
    const depts = root.PDC_WORKSHOP_DEPARTMENTS;
    const allowed = depts?.allowedBays?.(move.category);
    if (Array.isArray(allowed)) return allowed.map(Number).filter(n => n > 0);
    const count = Number(depts?.PMB_BAY_COUNTS?.[move.stage] || 0);
    return count > 0 ? Array.from({ length: count }, (_, index) => index + 1) : [];
  }
  function armChips(block, key, editing) {
    const vehicle = editVehicle(key);
    const vehicleId = canonicalIdFor(vehicle);
    const { lines, bookings } = lineRecords(vehicle);
    const page = block.querySelector('[data-vehicle-workshop-hours-batch-page]') || block;
    block.querySelectorAll('li[data-operation-source-id]').forEach(li => {
      const sourceId = String(li.dataset.operationSourceId || '');
      const record = lines.get(sourceId) || {};
      const section = li.closest('[data-operation-station]');
      const stationKey = section?.dataset.operationCategory || '';
      const move = STATION_MOVE[stationKey] || { category: record.category || '', stage: section?.dataset.operationStation || record.stage || '' };
      const lineKey = record.lineKey || (sourceId ? `source:${sourceId}` : '');
      const tick = tickRow(lineKey);
      const matched = stationBookings(bookings, move.category, move.stage);
      const doneBooking = matched.find(booking => String(booking.status || '').toLowerCase() === 'completed') || null;
      const completed = tick?.completed === true || record.completed === true || !!doneBooking;
      const who = (tick?.completed && tick.actor_email) || record.completedBy || bookingPerson(doneBooking);
      const when = whenLabel((tick?.completed && tick.acted_at) || record.completedAt || doneBooking?.actual_end_at || '');
      li.classList.add('vso-chip');
      li.classList.toggle('vso-done', completed);
      li.classList.toggle('is-complete', completed);
      li.dataset.vsoKind = 'line';
      li.dataset.vsoLineKey = lineKey;
      li.dataset.vsoCategory = record.category || move.category;
      li.dataset.vsoStage = move.stage;
      li.dataset.vsoHours = hoursText(record.hours);
      li.dataset.vsoCategoryVersion = String(record.categoryVersion || 0);
      li.dataset.vsoPlanId = '';
      li.dataset.vsoBookingId = '';
      const canDrag = editing && !completed && /^(source|manual):[0-9a-f-]{36}$/i.test(lineKey);
      if (canDrag) li.setAttribute('draggable', 'true'); else li.removeAttribute('draggable');
      li.querySelectorAll('.vso-done-meta, .vso-tick').forEach(node => node.remove());
      const em = li.querySelector('em');
      if (editing && em && /^[0-9a-f-]{36}$/i.test(sourceId) && /^source:[0-9a-f-]{36}$/i.test(lineKey)) {
        const original = hoursText(record.hours);
        const drafted = typeof root.vehicleWorkshopHoursBatchDraftValue === 'function'
          ? root.vehicleWorkshopHoursBatchDraftValue(vehicleId, sourceId, original) : original;
        em.innerHTML = `<input type="number" min="0" max="999.99" step="0.01" value="${esc(drafted ?? '')}" data-vehicle-workshop-hours-batch-input data-operation-line-id="${esc(sourceId)}" data-line-key="${esc(lineKey)}" data-original-hours="${esc(original)}" data-stage="${esc(move.stage)}" data-work-key="${esc(record.workKey || stationKey)}" data-adjustment-id="${esc(record.adjustmentId || '')}" data-adjustment-version="${esc(String(record.adjustmentVersion || 0))}" aria-label="Hours">`;
        bindHours(em.querySelector('input'), page);
      }
      if (completed) {
        const override = tick?.completed === true;
        const phrase = override ? `Complete (override by ${who || 'controller'})` : 'Complete';
        const rest = [override ? '' : who, when].filter(Boolean).join(' · ');
        const text = rest ? `${phrase} · ${rest}` : phrase;
        li.insertAdjacentHTML('beforeend', `<small class="vso-done-meta" title="${esc(text)}">${esc(text)}</small>`);
      }
      const checked = tick?.completed === true;
      const control = isController();
      li.insertAdjacentHTML('beforeend', `<label class="vso-tick"><input type="checkbox" data-vso-tick="${esc(lineKey)}" aria-checked="${checked ? 'true' : 'false'}"${checked ? ' checked' : ''}${control ? '' : ' disabled'} title="${control ? (checked ? 'Remove the completed tick' : 'Mark this line completed') : 'Read-only for your role'}"><span>${checked ? 'Complete' : 'Tick'}</span></label>`);
      const box = li.querySelector('[data-vso-tick]');
      box?.addEventListener('click', event => {
        event.stopPropagation();
        if (box.disabled || !isController()) return;
        const next = box.getAttribute('aria-checked') !== 'true';
        void toggleCompletion(vehicleId, lineKey, next);
      });
      if (canDrag) {
        li.addEventListener('dragstart', event => {
          dragChip = { el: li, chip: readChip(li) };
          li.classList.add('is-dragging');
          event.dataTransfer?.setData?.('text/plain', lineKey);
        });
        li.addEventListener('dragend', () => {
          li.classList.remove('is-dragging');
          block.querySelectorAll('.is-drop').forEach(node => node.classList.remove('is-drop'));
          dragChip = null;
        });
      }
    });
    block.querySelectorAll('[data-operation-station]').forEach(section => {
      const stationKey = section.dataset.operationCategory || '';
      const move = STATION_MOVE[stationKey] || { category: '', stage: section.dataset.operationStation || '' };
      section.querySelectorAll('.vso-bays, .vso-job').forEach(node => node.remove());
      const matched = stationBookings(bookings, move.category, move.stage);
      const header = section.querySelector('header');
      let jobAnchor = header;
      matched.forEach(booking => {
        const status = String(booking.status || '').toLowerCase();
        const done = status === 'completed';
        const minutes = Number(booking.default_duration_minutes);
        const hours = Number.isFinite(minutes) && minutes > 0 ? minutes / 60 : '';
        const who = bookingPerson(booking);
        const when = whenLabel(booking.actual_end_at || '');
        const meta = done ? `Completed${[who, when].filter(Boolean).map(part => ` · ${part}`).join('')}` : `${hours === '' ? 'Hours not stated' : `${Number(hours).toFixed(2)} h`}`;
        const button = doc.createElement('button');
        button.type = 'button';
        button.className = done ? 'vso-job vso-done is-complete' : 'vso-job';
        button.dataset.vsoKind = 'job';
        button.dataset.vsoLineKey = '';
        button.dataset.vsoCategory = booking.work_category || move.category;
        button.dataset.vsoStage = move.stage;
        button.dataset.vsoHours = hours === '' ? '' : String(hours);
        button.dataset.vsoPlanId = String(booking.plan_id || '');
        button.dataset.vsoBookingId = String(booking.booking_id || booking.id || '');
        button.textContent = `${move.category || move.stage} · ${meta}`;
        if (editing && !done) {
          button.setAttribute('draggable', 'true');
          button.addEventListener('dragstart', event => {
            dragChip = { el: button, chip: readChip(button) };
            button.classList.add('is-dragging');
            event.stopPropagation();
          });
          button.addEventListener('dragend', () => { button.classList.remove('is-dragging'); dragChip = null; });
        }
        if (jobAnchor) { jobAnchor.after(button); jobAnchor = button; }
      });
      if (editing) {
        const numbers = bayNumbers(move);
        if (numbers.length && header) {
          const row = doc.createElement('div');
          row.className = 'vso-bays';
          row.setAttribute('aria-label', 'Bays');
          numbers.forEach(bay => {
            const button = doc.createElement('button');
            button.type = 'button';
            button.className = 'vso-bay';
            button.dataset.vsoBay = String(bay);
            button.dataset.vsoStage = move.stage;
            button.dataset.vsoCategory = move.category;
            button.textContent = root.PDC_WORKSHOP_DEPARTMENTS?.bayLabel?.(move.stage, bay) || `Bay ${String(bay).padStart(2, '0')}`;
            bindDrop(button, () => ({ kind: 'bay', bay, stage: move.stage, category: move.category }));
            row.appendChild(button);
          });
          const jobs = [...section.querySelectorAll('.vso-job')];
          const after = jobs.length ? jobs[jobs.length - 1] : header;
          after.after(row);
        }
      }
      if (editing && move.category) {
        bindDrop(section, () => ({ kind: 'station', category: move.category, stage: move.stage, bay: 0 }));
      }
      const workKey = workKeyFor(move.stage);
      if (isController() && workKey && header && typeof root.setStationCompletionOverride === 'function') {
        const row = (edit.stationRows || []).find(item => item.work_key === workKey && item.override === true);
        const button = doc.createElement('button');
        button.type = 'button';
        button.className = row ? 'vso-station-override is-on' : 'vso-station-override';
        button.dataset.vsoStationOverride = workKey;
        button.textContent = row ? 'Undo override' : 'Override';
        const acted = whenLabel(row?.acted_at || '');
        button.title = row
          ? `Complete (override by ${row.override_email || 'controller'})${acted ? ` · ${acted}` : ''}`
          : 'Mark this station complete';
        button.addEventListener('click', event => {
          event.stopPropagation();
          void toggleStation(vehicleId, workKey, !row);
        });
        header.appendChild(button);
      }
    });
  }
  function ensureCompletions(vehicle) {
    const id = canonicalIdFor(vehicle);
    const canLines = typeof root.loadPanelLineCompletions === 'function';
    const canStations = typeof root.loadStationIconDetail === 'function';
    if (!id || edit.completionFor === id || (!canLines && !canStations)) return;
    edit.completionFor = id;
    const gen = ++edit.completionGen;
    const linesPromise = canLines ? Promise.resolve(root.loadPanelLineCompletions(id)) : Promise.resolve([]);
    const stationsPromise = canStations ? Promise.resolve(root.loadStationIconDetail(id)) : Promise.resolve([]);
    Promise.all([linesPromise, stationsPromise]).then(([lines, stations]) => {
      if (gen !== edit.completionGen || !state.key || canonicalIdFor(editVehicle(state.key)) !== id) return;
      const nextLines = Array.isArray(lines) ? lines : [];
      const nextStations = Array.isArray(stations) ? stations : [];
      const changed = JSON.stringify(nextLines) !== JSON.stringify(edit.completionRows || [])
        || JSON.stringify(nextStations) !== JSON.stringify(edit.stationRows || []);
      edit.completionRows = nextLines;
      edit.stationRows = nextStations;
      if (changed) redraw(state.key);
    }).catch(() => {});
  }
  // The operations heading's "Edit jobs & hours" becomes "Edit" + "Open full editor" for the same roles as the window.
  // Completed lines and controller ticks are shown for every role. Edit keeps the chip list.
  function decorateOperations(panel, key) {
    const block = panel.querySelector('.vso-body .authenticated-email-operations');
    if (!block || block.hasAttribute('data-vso-edit-ready')) return;
    block.setAttribute('data-vso-edit-ready', '');
    const old = block.querySelector('[data-auth-operation-work]');
    const identity = old?.dataset.authOperationWork || key;
    block.dataset.vsoIdentity = identity;
    const vehicle = editVehicle(key);
    const inline = editReady() && !!canonicalIdFor(vehicle);
    const editing = inline && edit.key === key;
    if (old) {
      const tools = doc.createElement('span');
      tools.className = 'vso-ops-tools';
      tools.innerHTML = `${inline && !editing ? '<button type="button" class="vso-edit-toggle" data-vso-edit-toggle>Edit</button>' : ''}<button type="button" class="vso-link" data-vso-full-editor>Open full editor</button>`;
      old.replaceWith(tools);
      tools.querySelector('[data-vso-edit-toggle]')?.addEventListener('click', event => { event.stopPropagation(); startEdit(key); });
      tools.querySelector('[data-vso-full-editor]').addEventListener('click', event => { event.stopPropagation(); openFullEditor(identity); });
    }
    if (editing) mountEditor(block, key, vehicle, identity);
    else if (edit.note) block.querySelector('.authenticated-email-operations-heading')?.insertAdjacentHTML('afterend', `<p class="vso-edit-msg is-done" role="status">${esc(edit.note)}</p>`);
    armChips(block, key, editing);
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
    const openCards = typeof root.pdcOpenJobCards === 'function' ? root.pdcOpenJobCards(vehicle) : [];
    const jobs = openCards.length ? openCards.join(' · ') : ((vehicle.pdcJobCardNumbers || []).join(' · ') || vehicle.jobCardNumber || '—');
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
    decorateOperations(panel, key); // r565: Edit keeps this chip list; completed lines and controller ticks
    if (typeof root.PdcLineHandoff?.mount === 'function') root.PdcLineHandoff.mount(panel, vehicle); // r583: handed-off lines for the controller
    ensureCompletions(vehicle);
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
    if (state.key !== key) { edit.note = ''; edit.completionFor = ''; edit.completionRows = []; }
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
    edit.completionFor = '';
    edit.completionRows = [];
    edit.stationRows = [];
    edit.completionGen += 1;
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
