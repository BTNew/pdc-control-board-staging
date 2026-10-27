/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r564 (F178): a parts ETA and a short stoppage note typed on the vehicle.
 * A typed date wins over the parts-staff email. The email chip's detail and the JITA date stay visible
 * as the source they came from. Parts (importer), workshop controllers (operator) and administrators edit.
 * Everyone else reads. The editor is not drawn until get_pdc_parts_stoppage_board_564 exists, so a board
 * without this migration keeps the email chip exactly as it is.
 * One date per vehicle. A GP chip on a PD line is a sublet purchase order, not the DMS part line, so
 * there is no per-order date here.
 * Loads after the key number and before the Vehicle Locations table. styles.css and app.js are untouched.
 * r573 (F187): the form can place that date as a vehicle STOPPAGE. The planner lists it
 * in the Stoppage section. Clearing the date, or leaving the tick off, lifts it. Blue, not orange.
 * r589 (F203): the Vehicle Locations Parts ETA cell is read-only. The date is set only in the
 * vehicle side panel. That section offers Place as STOPPAGE without rebuilding the board.
 */
(() => {
  'use strict';
  const VERSION = '2026.10.28.r589';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const BOARD_RPC = 'get_pdc_parts_stoppage_board_564';
  const SET_RPC = 'set_pdc_parts_stoppage_564';
  const HISTORY_RPC = 'get_pdc_parts_stoppage_history_564';
  const PLACE_RPC = 'place_parts_eta_stoppage_573';
  const PLACE_BOARD_RPC = 'get_pdc_parts_eta_stoppage_board_573';
  const JITA_RPC = 'get_pdc_jita_eta_board';
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const CHIP = /<span class="pdc-parts-eta pdc-parts-eta-(?:ok|due|overdue)"[^>]*>(?:<span class="pdc-parts-eta-k">[^<]*<\/span>)?[^<]*<\/span>/;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const iso = value => /^\d{4}-\d{2}-\d{2}/.test(String(value || '')) ? String(value).slice(0, 10) : '';
  const clean = value => String(value ?? '').replace(/\s+/g, ' ').trim();
  const clip = (value, n = 42) => { const s = clean(value); return s.length > n ? `${s.slice(0, n - 1)}…` : s; };
  const ddmm = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}` : ''; };
  const ddmmyy = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(2, 4)}` : ''; };

  function perthToday(now = new Date()) {
    try {
      const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Perth', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
      const get = type => parts.find(p => p.type === type)?.value || '';
      const out = `${get('year')}-${get('month')}-${get('day')}`;
      return /^\d{4}-\d{2}-\d{2}$/.test(out) ? out : '';
    } catch (_) { return ''; }
  }
  function perthDate(value) {
    const d = value instanceof Date ? value : new Date(value || '');
    if (!value || Number.isNaN(d.getTime())) return '';
    return perthToday(d);
  }
  function daysUntil(eta, today) {
    const a = iso(eta), b = iso(today);
    if (!a || !b) return null;
    return Math.round((Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10)) - Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10))) / 86400000);
  }
  function countdown(eta, today) {
    const days = daysUntil(eta, today);
    if (days === null) return { days, text: '', state: '' };
    if (days < 0) return { days, text: `${-days} day${days === -1 ? '' : 's'} overdue`, state: 'overdue' };
    if (days === 0) return { days, text: 'today', state: 'due' };
    return { days, text: `${days} day${days === 1 ? '' : 's'}`, state: 'ok' };
  }
  /** The date the column shows. A typed date wins. A cleared manual date falls back to the email. */
  function shownEta(manual, emailEta) {
    return iso(manual?.eta_date) || iso(emailEta) || '';
  }
  function whenLabel(value) {
    const d = new Date(value || '');
    if (!value || Number.isNaN(d.getTime())) return '';
    try {
      return d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }) + ' AWST';
    } catch (_) { return ''; }
  }
  function hasManual(manual) {
    return Boolean(manual && (iso(manual.eta_date) || clean(manual.note) || iso(manual.last_checked_on)));
  }
  const emailFromHtml = html => { const m = /data-parts-eta="(\d{4}-\d{2}-\d{2})/.exec(String(html || '')); return m ? m[1] : ''; };

  function slotHtml(state) {
    const vid = esc(state.vehicleId || '');
    const email = iso(state.emailEta);
    const manualDate = iso(state.manual?.eta_date);
    const shown = shownEta(state.manual, email);
    const left = countdown(shown, state.today);
    const note = clean(state.manual?.note);
    const checked = ddmmyy(state.manual?.last_checked_on);
    const who = clean(state.manual?.set_by_actor);
    const title = [
      manualDate ? `Manual parts ETA ${ddmmyy(manualDate)}` : email ? `Email parts ETA ${ddmmyy(email)}` : 'No parts ETA yet',
      left.text,
      note && `Waiting on ${note}`,
      checked && `Last checked ${checked}${who ? ` by ${who}` : ''}`,
      email && manualDate && email !== manualDate ? `Email ${ddmmyy(email)} is kept` : ''
    ].filter(Boolean).join(' · ');
    // r589: the table lifts this slot. It is a date, never a button and never a form.
    const label = shown ? `${ddmm(shown)}${left.text ? ` · ${left.text}` : ''}` : '—';
    const open = `<span class="pdc-parts-stoppage-open is-${left.state || 'empty'}" title="${esc(title)}">${esc(label)}${note ? `<small class="pdc-parts-stoppage-note">${esc(clip(note))}</small>` : ''}</span>`;
    const secondary = email && manualDate && email !== manualDate ? `<small class="pdc-parts-stoppage-email">Email ${esc(ddmm(email))}</small>` : '';
    const placed = state.placed ? `<small class="pdc-parts-stoppage-placed">STOPPAGE</small>` : '';
    return `<div class="pdc-parts-stoppage-slot" data-parts-eta="${esc(shown)}" data-pdc-stoppage-slot="${vid}">${open}${placed}${secondary}</div>`;
  }

  function editorHtml(state) {
    const vid = esc(state.vehicleId || '');
    const manualDate = iso(state.manual?.eta_date);
    const note = clean(state.manual?.note);
    return `<form class="pdc-parts-stoppage-form" data-pdc-stoppage-form="${vid}">`
      + `<input type="date" data-pdc-stoppage-date="${vid}" value="${esc(state.draftEta ?? manualDate)}" aria-label="Parts ETA date" />`
      + `<input type="text" maxlength="180" data-pdc-stoppage-note="${vid}" value="${esc(state.draftNote ?? note)}" placeholder="Waiting on (part)" aria-label="Parts stoppage note" />`
      + `<button type="submit">Save</button>`
      + `<button type="button" data-pdc-stoppage-clear="${vid}">Clear</button>`
      + `<button type="button" data-pdc-stoppage-checked="${vid}">Checked</button>`
      + `<button type="button" data-pdc-stoppage-cancel="${vid}">Cancel</button>`
      + `<label class="pdc-parts-stoppage-place"><input type="checkbox" data-pdc-stoppage-place="${vid}"${state.placed ? ' checked' : ''}/> Place as STOPPAGE</label>`
      + `<small class="pdc-parts-stoppage-msg" role="status">${esc(state.message || 'A typed date wins over the email. Tick Place as STOPPAGE to hold the vehicle until that date.')}</small>`
      + `</form>`;
  }

  function historyHtml(history) {
    const rows = Array.isArray(history) ? history.slice(0, 8) : [];
    if (!rows.length) return '<small class="pdc-parts-stoppage-history-empty">No manual changes recorded yet.</small>';
    return '<ul class="pdc-parts-stoppage-history">' + rows.map(row => {
      const from = ddmmyy(row.old_eta) || '—';
      const to = ddmmyy(row.new_eta) || '—';
      const note = clean(row.new_note);
      return `<li><b>${esc(from)} → ${esc(to)}</b> <span>${esc(row.action || 'set')} by ${esc(row.by || 'unknown')} · ${esc(whenLabel(row.at))}${note ? ` · ${esc(clip(note, 80))}` : ''}</span></li>`;
    }).join('') + '</ul>';
  }

  function detailHtml(state) {
    const vid = esc(state.vehicleId || '');
    const email = iso(state.emailEta);
    const jita = iso(state.jitaEta);
    const manualDate = iso(state.manual?.eta_date);
    const checked = ddmmyy(state.manual?.last_checked_on);
    const who = clean(state.manual?.set_by_actor);
    const lines = [];
    if (email) lines.push(`<small class="pdc-parts-stoppage-email">Email ${esc(ddmmyy(email))} · parts staff email${manualDate ? ' (kept)' : ''}</small>`);
    if (jita) lines.push(`<small class="pdc-parts-stoppage-jita">JITA ETA ${esc(ddmmyy(jita))} · JITA paste</small>`);
    if (checked) lines.push(`<small class="pdc-parts-stoppage-checked">Last checked ${esc(checked)}${who ? ` · ${esc(who)}` : ''}</small>`);
    const form = state.editing && state.canEdit ? editorHtml(state) : '';
    const button = !state.editing && state.canEdit
      ? `<button type="button" data-pdc-stoppage-edit="${vid}">${manualDate || email || clean(state.manual?.note) ? 'Change' : 'Set date'}</button>`
      : '';
    const placeNow = !state.editing && state.canEdit
      ? `<label class="pdc-parts-stoppage-place"><input type="checkbox" data-pdc-stoppage-place-now="${vid}"${state.placed ? ' checked' : ''}/> Place as STOPPAGE</label>`
      : '';
    const badge = state.placed && !state.editing ? `<small class="pdc-parts-stoppage-placed">STOPPAGE</small>` : '';
    const read = !state.editing ? `<strong class="pdc-parts-stoppage-read is-${countdown(shownEta(state.manual, email), state.today).state || 'empty'}">${esc(shownEta(state.manual, email) ? ddmmyy(shownEta(state.manual, email)) : 'No date')}</strong> `
      + (clean(state.manual?.note) ? `<span class="pdc-parts-stoppage-note">${esc(clean(state.manual.note))}</span>` : '') : '';
    return `<div class="tune-service-location-job pdc-parts-stoppage-detail" data-pdc-stoppage-detail="${vid}"><b>Parts ETA</b>`
      + `<span class="pdc-parts-stoppage-lead">${read}${badge}${button}${placeNow}${form}</span>`
      + lines.join('')
      + `<button type="button" data-pdc-stoppage-history="${vid}">History</button>`
      + (state.history ? historyHtml(state.history) : '')
      + (state.message && !state.editing ? `<small class="pdc-parts-stoppage-msg" role="status">${esc(state.message)}</small>` : '')
      + `<small class="pdc-parts-stoppage-scope">One date for the vehicle. A typed date wins over the email.</small></div>`;
  }

  function closeDivAt(html, classToken) {
    const marker = String(html).indexOf(classToken);
    if (marker < 0) return -1;
    const open = html.lastIndexOf('<div', marker);
    if (open < 0) return -1;
    let i = open;
    let depth = 0;
    while (i < html.length) {
      if (html.startsWith('<div', i)) { depth += 1; i += 4; continue; }
      if (html.startsWith('</div>', i)) {
        depth -= 1;
        if (depth === 0) return i + 6;
        i += 6;
        continue;
      }
      i += 1;
    }
    return -1;
  }

  /** Put the read-only date on the summary (the table lifts it) and the editor in the detail grid (the side panel). */
  function decorateCard(html, state) {
    const text = String(html || '');
    if (!state?.vehicleId || text.includes('data-pdc-stoppage-slot=') || text.includes('data-pdc-stoppage-detail=')) return text;
    const emailEta = state.emailEta || emailFromHtml(text);
    const full = { ...state, emailEta };
    if (!full.canEdit && !hasManual(full.manual)) return text;
    const slot = slotHtml(full);
    const detail = detailHtml(full);
    let out = CHIP.test(text) ? text.replace(CHIP, slot) : text.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)/, `$1${slot}`);
    const at = closeDivAt(out, 'pdc-parts-eta-detail');
    if (at >= 0) return out.slice(0, at) + detail + out.slice(at);
    return out.replace(/(<div class="incoming-vehicle-detail-grid[^"]*">)/, `$1${detail}`);
  }

  /** Bookings that start before a typed parts ETA. Null when the email date should be used instead. */
  function manualWarning(manual, bookings, vehicleLabel, today) {
    const eta = iso(manual?.eta_date);
    if (!eta) return null;
    const before = (Array.isArray(bookings) ? bookings : []).map(row => ({ ...row, date: perthDate(row?.start) })).filter(row => row.date && row.date < eta);
    if (!before.length) return null;
    return {
      eta,
      etaLabel: ddmmyy(eta),
      vehicle: clean(vehicleLabel),
      count: 1,
      parts: [{ part: clean(manual.note) || 'Parts stoppage', eta_date: eta }],
      before,
      bookAll: false,
      today: iso(today)
    };
  }
  function manualBookAllWarning(manual, today, vehicleLabel) {
    const eta = iso(manual?.eta_date), day = iso(today);
    if (!eta || !day || eta <= day) return null;
    return { eta, etaLabel: ddmmyy(eta), vehicle: clean(vehicleLabel), count: 1, parts: [], before: [], bookAll: true, today: day };
  }

  /** What to send after the typed date is saved. Null means the stoppage is left as it is. */
  function placePayload(mode, fields, ticked, wasPlaced) {
    const eta = iso(fields?.eta);
    const note = clean(fields?.note);
    if (mode === 'clear' || (mode !== 'check' && !eta)) return wasPlaced ? { p_place: false } : null;
    if (mode === 'check') return null;
    if (ticked) return { p_place: true, p_eta: eta, p_note: note };
    if (wasPlaced) return { p_place: false };
    return null;
  }
  function placeMessage(result) {
    const code = result?.error || result?.code || 'error';
    if (code === 'eta_reached') return 'That ETA is already here, so no stoppage was placed.';
    if (code === 'vehicle_running') return 'A job already running on this vehicle covers that date.';
    if (code === 'bay_running') return 'A running job is in the way. Nothing was moved.';
    if (code === 'push_failed') return 'The later jobs could not be moved. Nothing was placed.';
    if (code === 'not_authorized') return 'Parts and workshop controllers can place this.';
    if (code === 'eta_required') return 'Set a parts ETA before placing a STOPPAGE.';
    return `Stoppage was not placed (${code}).`;
  }
  function plannerSectionHtml(rows) {
    const list = Array.isArray(rows) ? rows : [];
    const cards = list.map(row => {
      const eta = ddmmyy(row?.eta_date);
      const note = clean(row?.note);
      const reason = clean(row?.reason) || `STOPPAGE · Parts ETA ${eta || '—'}${note ? ` · ${note}` : ''}`;
      const who = clean(row?.set_by_actor);
      const stock = clean(row?.stock_number) || 'Vehicle';
      const key = clean(row?.key_number);
      return `<article class="workshop-parts-stoppage-card"><strong>STOPPAGE</strong><span>${esc(stock)}${key ? ` · Key ${esc(key)}` : ''}</span><b>${esc(reason)}</b><small>Until ${esc(eta || 'the ETA')}${who ? ` · ${esc(who)}` : ''}</small></article>`;
    }).join('');
    const body = cards || '<div class="workshop-empty">No parts ETA is placed as STOPPAGE.</div>';
    return `<section class="workshop-parts-stoppage" aria-label="Stoppage"><div class="workshop-side-heading"><strong>Stoppage</strong><span>Parts ETA</span></div><div class="workshop-parts-stoppage-list">${body}</div></section>`;
  }

  const api = {
    VERSION, BOARD_RPC, SET_RPC, HISTORY_RPC, JITA_RPC, PLACE_RPC, PLACE_BOARD_RPC,
    shownEta, countdown, daysUntil, perthToday, slotHtml, editorHtml, detailHtml, decorateCard, historyHtml,
    manualWarning, manualBookAllWarning, clip, hasManual, emailFromHtml, placePayload, placeMessage, plannerSectionHtml
  };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_PARTS_STOPPAGE_VERSION) return;
  window.PDC_PARTS_STOPPAGE_VERSION = VERSION;

  const byId = new Map();
  const byStock = new Map();
  const placedById = new Map();
  const jitaById = new Map();
  const jitaByStock = new Map();
  const ui = new Map();
  let canEdit = false;
  let serverToday = '';
  let installed = false;
  let missing = false;
  const idKey = value => String(value ?? '').trim().toLowerCase();
  const vehicleId = vehicle => [vehicle?.__emailVehicleId, vehicle?.id, vehicle?.permanentVehicleId].map(idKey).find(id => UUID.test(id)) || '';
  const stockKey = vehicle => String(vehicle?.stock || vehicle?.stock_number || '').trim().toUpperCase();
  const today = () => perthToday() || serverToday || '';
  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  const token = () => window.__pdcCachedAccessToken;

  function rowFor(vehicle) {
    const id = vehicleId(vehicle);
    if (id && byId.has(id)) return byId.get(id);
    const stock = stockKey(vehicle);
    return stock && byStock.get(stock) || null;
  }
  function jitaFor(vehicle) {
    const id = vehicleId(vehicle);
    if (id && jitaById.has(id)) return jitaById.get(id);
    const stock = stockKey(vehicle);
    return stock && jitaByStock.get(stock) || '';
  }
  function stateFor(vehicle) {
    const vid = vehicleId(vehicle);
    const st = ui.get(vid) || {};
    return {
      vehicleId: vid,
      canEdit: canEdit && Boolean(vid),
      editing: Boolean(st.editing),
      message: st.message || '',
      history: st.history,
      manual: rowFor(vehicle),
      placed: placedById.has(vid),
      jitaEta: jitaFor(vehicle),
      today: today(),
      draftEta: st.draftEta,
      draftNote: st.draftNote
    };
  }
  function emailFor(vehicle) {
    try { return iso(window.PDC_PARTS_ETA?.entryFor?.(vehicle)?.latest_eta); } catch (_) { return ''; }
  }
  function withEmail(vehicle) {
    const state = stateFor(vehicle);
    return state.emailEta ? state : { ...state, emailEta: emailFor(vehicle) };
  }
  function findVehicle(vid) {
    const rows = typeof vehicleLocationsScreenRows === 'function' ? vehicleLocationsScreenRows() : [];
    return rows.find(row => vehicleId(row) === vid) || null;
  }
  function replaceOuter(node, html) {
    if (!node?.parentNode) return;
    const holder = document.createElement('div');
    holder.innerHTML = html;
    const next = holder.children?.[0];
    if (next) node.replaceWith(next);
  }
  function rememberPlaced(vid, placed, want) {
    if (want !== true || placed?.ok !== true) { placedById.delete(vid); return; }
    const prev = placedById.get(vid) || {};
    const vehicle = findVehicle(vid);
    const manual = byId.get(vid);
    placedById.set(vid, {
      ...prev,
      vehicle_id: vid,
      stock_number: clean(placed.stock_number || prev.stock_number || vehicle?.stock_number || vehicle?.stock || ''),
      key_number: clean(placed.key_number || prev.key_number || vehicle?.key_number || ''),
      eta_date: iso(placed.eta_date || prev.eta_date || manual?.eta_date),
      note: clean(placed.note != null ? placed.note : (prev.note || manual?.note || '')),
      reason: clean(placed.reason || prev.reason || ''),
      set_by_actor: clean(placed.set_by_actor || prev.set_by_actor || ''),
      booking_id: placed.booking_id || prev.booking_id || ''
    });
  }
  function paintPlanner() {
    const section = document.querySelector('.workshop-parts-stoppage');
    if (section) replaceOuter(section, plannerSectionHtml([...placedById.values()]));
  }
  function paint(vid) {
    const vehicle = findVehicle(vid);
    const state = vehicle ? withEmail(vehicle) : {
      vehicleId: vid, canEdit, editing: Boolean(ui.get(vid)?.editing), message: ui.get(vid)?.message || '',
      history: ui.get(vid)?.history, manual: byId.get(vid) || null, placed: placedById.has(vid),
      jitaEta: jitaById.get(vid) || '', today: today(), draftEta: ui.get(vid)?.draftEta, draftNote: ui.get(vid)?.draftNote, emailEta: ''
    };
    const detail = detailHtml(state);
    const slot = slotHtml(state);
    document.querySelectorAll(`[data-pdc-stoppage-detail="${vid}"]`).forEach(node => replaceOuter(node, detail));
    document.querySelectorAll(`[data-pdc-stoppage-slot="${vid}"]`).forEach(node => replaceOuter(node, slot));
    paintPlanner();
  }
  function paintVisible() {
    const host = document.getElementById('vlt-table-host');
    const rows = typeof vehicleLocationsScreenRows === 'function' ? vehicleLocationsScreenRows() : [];
    const keyOf = typeof vehicleKey === 'function' ? vehicleKey : null;
    if (host && keyOf) {
      host.querySelectorAll('tr[data-vlt-key]').forEach(tr => {
        const vehicle = rows.find(row => keyOf(row) === (tr.getAttribute('data-vlt-key') || ''));
        if (!vehicle) return;
        const state = withEmail(vehicle);
        if (!state.vehicleId || (!state.canEdit && !hasManual(state.manual) && !state.placed)) return;
        const cell = tr.querySelector('td.c-eta');
        if (!cell) return;
        const slot = slotHtml(state);
        const existing = cell.querySelector('[data-pdc-stoppage-slot]');
        if (existing) { if (existing.outerHTML !== slot) replaceOuter(existing, slot); return; }
        const chip = cell.querySelector('.pdc-parts-eta');
        if (chip) replaceOuter(chip, slot);
        else cell.insertAdjacentHTML('afterbegin', slot);
      });
    }
    document.querySelectorAll('[data-pdc-stoppage-detail]').forEach(node => {
      const vid = node.getAttribute('data-pdc-stoppage-detail') || '';
      if (UUID.test(vid)) paint(vid);
    });
  }
  function rerender(vid) {
    if (vid && UUID.test(String(vid))) paint(vid);
    else paintVisible();
  }
  function install() {
    if (installed) return;
    installed = true;
    if (typeof incomingVehicleDetailRow === 'function') {
      const prior = incomingVehicleDetailRow;
      incomingVehicleDetailRow = (vehicle, ...args) => {
        try { return decorateCard(prior(vehicle, ...args), stateFor(vehicle)); }
        catch (_) { return prior(vehicle, ...args); }
      };
    }
    const prior = window.PDC_PARTS_ETA;
    if (prior && typeof prior.confirmBookings === 'function') {
      const vehicleText = vehicle => clean(vehicle?.stock || vehicle?.stock_number) ? `Stock ${clean(vehicle.stock || vehicle.stock_number)}` : '';
      window.PDC_PARTS_ETA = Object.freeze({
        ...prior,
        beforeEta(vehicle, start) {
          const manual = rowFor(vehicle);
          if (iso(manual?.eta_date)) {
            const date = perthDate(start);
            return date && date < iso(manual.eta_date) ? iso(manual.eta_date) : '';
          }
          return prior.beforeEta(vehicle, start);
        },
        async confirmBookings(groups) {
          const emailGroups = [];
          const warnings = [];
          for (const group of Array.isArray(groups) ? groups : []) {
            const manual = rowFor(group?.vehicle);
            if (iso(manual?.eta_date)) {
              const warning = manualWarning(manual, group.bookings, vehicleText(group.vehicle), today());
              if (warning) warnings.push(warning);
            } else emailGroups.push(group);
          }
          const emailAnswer = emailGroups.length ? await prior.confirmBookings(emailGroups) : { ok: true, warnings: [] };
          if (!emailAnswer?.ok) return emailAnswer;
          if (!warnings.length) return emailAnswer;
          const ok = typeof prior.ask === 'function' ? await prior.ask(warnings) : true;
          return { ok, warnings: [...(emailAnswer.warnings || []), ...warnings] };
        },
        bookAllWarningFor(vehicle) {
          const manual = rowFor(vehicle);
          if (iso(manual?.eta_date)) return manualBookAllWarning(manual, today(), vehicleText(vehicle));
          return prior.bookAllWarningFor(vehicle);
        },
        async confirmBookAll(vehicle) {
          const manual = rowFor(vehicle);
          if (iso(manual?.eta_date)) {
            const warning = manualBookAllWarning(manual, today(), vehicleText(vehicle));
            if (!warning) return { ok: true, warnings: [] };
            return { ok: typeof prior.ask === 'function' ? await prior.ask([warning]) : true, warnings: [warning] };
          }
          return prior.confirmBookAll(vehicle);
        }
      });
    }
    rerender();
  }

  async function rpc(name, body) {
    if (!token() || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {})
    });
    const text = await response.text();
    if (response.status === 404) { const error = new Error('missing'); error.status = 404; throw error; }
    if (!response.ok) {
      let message = text;
      try { message = JSON.parse(text).message || text; } catch (_) { /* raw */ }
      throw new Error(String(message || response.status));
    }
    return JSON.parse(text || 'null');
  }
  function indexBoard(payload) {
    byId.clear(); byStock.clear();
    serverToday = iso(payload?.today);
    canEdit = payload?.can_edit === true;
    for (const row of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      if (!row) continue;
      const stored = {
        eta_date: iso(row.eta_date),
        note: clean(row.note),
        last_checked_on: iso(row.last_checked_on),
        set_by_actor: clean(row.set_by_actor),
        set_at: row.set_at || ''
      };
      const id = idKey(row.vehicle_id);
      if (UUID.test(id)) byId.set(id, stored);
      if (clean(row.stock_number)) byStock.set(clean(row.stock_number).toUpperCase(), stored);
    }
  }
  function indexPlaced(payload) {
    placedById.clear();
    for (const row of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      const id = idKey(row?.vehicle_id);
      if (UUID.test(id)) placedById.set(id, row);
    }
  }
  function indexJita(payload) {
    jitaById.clear(); jitaByStock.clear();
    for (const row of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      const date = iso(row?.eta_date);
      if (!date) continue;
      const id = idKey(row.vehicle_id);
      if (UUID.test(id)) jitaById.set(id, date);
      if (clean(row.stock_number)) jitaByStock.set(clean(row.stock_number).toUpperCase(), date);
    }
  }
  let loading = false;
  async function load() {
    if (loading || missing || !token() || base() !== `https://${PROJECT}.supabase.co` || document.visibilityState === 'hidden') return;
    loading = true;
    try {
      const data = await rpc(BOARD_RPC, {});
      if (!data || data.can_edit == null && !Array.isArray(data.vehicles)) return;
      indexBoard(data);
      try { indexJita(await rpc(JITA_RPC, {})); } catch (_) { /* JITA stays as last read. The email path is untouched. */ }
      try {
        const placed = await rpc(PLACE_BOARD_RPC, {});
        if (placed && Array.isArray(placed.vehicles)) indexPlaced(placed);
      } catch (_) { /* The Stoppage section stays empty until the place read exists. */ }
      install();
    } catch (error) {
      if (error?.status === 404) missing = true;
    } finally { loading = false; }
  }
  function fields(vid) {
    const date = document.querySelector(`[data-pdc-stoppage-date="${vid}"]`);
    const note = document.querySelector(`[data-pdc-stoppage-note="${vid}"]`);
    const st = ui.get(vid) || {};
    // The table cell and the side panel can both be open. The last keystroke is the one that is saved.
    return {
      eta: iso(st.draftEta != null ? st.draftEta : (date ? date.value : '')),
      note: clean(st.draftNote != null ? st.draftNote : (note ? note.value : ''))
    };
  }
  async function save(vid, mode) {
    const st = ui.get(vid) || {};
    const current = fields(vid);
    const msg = document.querySelector(`[data-pdc-stoppage-slot="${vid}"] .pdc-parts-stoppage-msg, [data-pdc-stoppage-detail="${vid}"] .pdc-parts-stoppage-msg`);
    if (msg) msg.textContent = 'Saving…';
    const clear = mode === 'clear' || (mode !== 'check' && !current.eta && !current.note);
    try {
      const result = await rpc(SET_RPC, {
        p_vehicle_id: vid,
        p_eta_date: clear ? null : (current.eta || null),
        p_note: mode === 'clear' ? '' : current.note,
        p_clear: mode === 'clear' || (mode !== 'check' && !current.eta),
        p_mark_checked: mode === 'check'
      });
      if (result?.ok !== true) {
        const text = result?.code === 'not_authorized' ? 'Parts and workshop controllers can change this.'
          : result?.code === 'eta_date_out_of_range' ? 'Use a date within a year of today.'
          : result?.code === 'note_too_long' ? 'Keep the note under 180 characters.'
          : result?.code === 'vehicle_not_found' ? 'This vehicle is not on the board.'
          : `Not saved (${result?.code || 'error'}).`;
        ui.set(vid, { ...st, editing: true, message: text, draftEta: current.eta, draftNote: current.note });
        rerender(vid);
        return;
      }
      byId.set(vid, {
        eta_date: iso(result.eta_date),
        note: clean(result.note),
        last_checked_on: iso(result.last_checked_on) || today(),
        set_by_actor: clean(result.set_by_actor),
        set_at: result.set_at || new Date().toISOString()
      });
      const ticked = Boolean(document.querySelector(`[data-pdc-stoppage-place="${vid}"]`)?.checked);
      const follow = placePayload(mode, current, ticked, placedById.has(vid));
      let extra = '';
      if (follow) {
        try {
          const placed = await rpc(PLACE_RPC, { p_vehicle_id: vid, p_eta: follow.p_eta || null, p_note: follow.p_note || '', p_place: follow.p_place === true });
          if (placed?.ok === true) {
            rememberPlaced(vid, placed, follow.p_place === true);
            extra = follow.p_place ? ' Placed as STOPPAGE.' : ' STOPPAGE lifted.';
          } else extra = ` ${placeMessage(placed)}`;
        } catch (error) {
          extra = error?.status === 404
            ? ' Place as STOPPAGE is not on this database yet. The date was saved.'
            : ` Stoppage was not changed: ${error.message || error}`;
        }
      }
      ui.set(vid, { editing: false, message: (result.changed === false ? 'No change.' : 'Saved.') + extra, history: null });
      rerender(vid);
    } catch (error) {
      ui.set(vid, { ...st, editing: true, message: `Not saved: ${error.message || error}`, draftEta: current.eta, draftNote: current.note });
      rerender(vid);
    }
  }
  async function placeNow(vid, want) {
    const st = ui.get(vid) || {};
    const manual = byId.get(vid);
    const eta = iso(manual?.eta_date);
    if (want && !eta) {
      ui.set(vid, { ...st, editing: true, message: 'Set a parts ETA before placing a STOPPAGE.' });
      paint(vid);
      return;
    }
    if (!want && !placedById.has(vid)) { paint(vid); return; }
    try {
      const placed = await rpc(PLACE_RPC, { p_vehicle_id: vid, p_eta: eta || null, p_note: clean(manual?.note), p_place: want === true });
      if (placed?.ok === true) {
        rememberPlaced(vid, placed, want === true);
        ui.set(vid, { ...st, editing: false, message: want ? 'Placed as STOPPAGE.' : 'STOPPAGE lifted.', history: null });
      } else ui.set(vid, { ...st, message: placeMessage(placed) });
    } catch (error) {
      ui.set(vid, { ...st, message: error?.status === 404 ? 'Place as STOPPAGE is not on this database yet.' : `Stoppage was not changed: ${error.message || error}` });
    }
    paint(vid);
  }
  async function showHistory(vid) {
    const st = ui.get(vid) || {};
    try {
      const data = await rpc(HISTORY_RPC, { p_vehicle_id: vid });
      ui.set(vid, { ...st, history: Array.isArray(data?.history) ? data.history : [] });
      rerender(vid);
    } catch (_) { /* leave the cell as it is */ }
  }

  const style = document.createElement('style');
  style.textContent = [
    '.pdc-parts-stoppage-slot{display:flex;flex-direction:column;align-items:flex-start;gap:2px;max-width:100%;min-width:0}',
    '.pdc-parts-stoppage-open{font:inherit;font-size:11px;font-weight:700;line-height:1.15;text-align:left;padding:2px 5px;border-radius:4px;border:1px solid #bae6fd;background:#e0f2fe;color:#075985;max-width:100%}',
    'span.pdc-parts-stoppage-open{cursor:default}',
    '.pdc-parts-stoppage-open.is-due{background:#fef3c7;border-color:#fcd34d;color:#92400e}',
    '.pdc-parts-stoppage-open.is-overdue,.pdc-parts-stoppage-read.is-overdue{background:#fee2e2;border-color:#fca5a5;color:#b91c1c}',
    '.pdc-parts-stoppage-open.is-empty{background:#f8fafc;border-color:#cbd5e1;color:#334155;font-weight:650}',
    '.pdc-parts-stoppage-note{display:block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:550;font-size:10px}',
    '.pdc-parts-stoppage-email,.pdc-parts-stoppage-jita,.pdc-parts-stoppage-checked,.pdc-parts-stoppage-scope{display:block;color:#64748b;font-size:10.5px}',
    '.incoming-vehicle-detail-grid > .pdc-parts-stoppage-detail{grid-column:1/-1}',
    '.pdc-parts-stoppage-detail .pdc-parts-stoppage-lead{display:flex;flex-wrap:wrap;gap:6px;align-items:center}',
    '.pdc-parts-stoppage-form{display:flex;flex-wrap:wrap;gap:4px;align-items:center}',
    '.pdc-parts-stoppage-form input[type="date"]{font:inherit;font-size:12px}',
    '.pdc-parts-stoppage-form input[type="text"]{font:inherit;font-size:12px;width:14em;max-width:100%}',
    '.pdc-parts-stoppage-form button,.pdc-parts-stoppage-detail button{font:inherit;font-size:11px;font-weight:650;padding:2px 8px;border-radius:5px;border:1px solid #94a3b8;background:#fff;color:#1e293b;cursor:pointer}',
    '.pdc-parts-stoppage-form button[type="submit"]{background:#1d4ed8;border-color:#1d4ed8;color:#fff}',
    '.pdc-parts-stoppage-place{display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border:1px solid #1d4ed8;border-radius:5px;background:#dbeafe;color:#1d4ed8;font-size:11px;font-weight:700}',
    '.pdc-parts-stoppage-placed{display:inline-block;padding:1px 5px;border-radius:4px;background:#dbeafe;color:#1d4ed8;font-size:10px;font-weight:800}',
    '.pdc-parts-stoppage-msg{flex-basis:100%;color:#64748b;font-size:11px}',
    '.pdc-parts-stoppage-history{margin:2px 0 0;padding:0;list-style:none;font-size:11px;color:#334155}',
    '.pdc-parts-stoppage-history li{display:flex;gap:6px;flex-wrap:wrap}',
    '.vlt-table td.c-eta .pdc-parts-stoppage-slot{max-width:100%}',
    '.vlt-table td.c-eta .pdc-parts-stoppage-note{max-width:11em}'
  ].join('');
  document.head.appendChild(style);

  for (const type of ['mousedown', 'pointerdown', 'touchstart', 'dblclick']) {
    document.addEventListener(type, event => { if (event.target?.closest?.('.pdc-parts-stoppage-detail, .pdc-parts-stoppage-form')) event.stopPropagation(); }, true);
  }
  document.addEventListener('click', event => {
    const el = event.target?.closest?.('[data-pdc-stoppage-edit],[data-pdc-stoppage-cancel],[data-pdc-stoppage-clear],[data-pdc-stoppage-checked],[data-pdc-stoppage-history]');
    if (!el) return;
    event.preventDefault();
    event.stopPropagation();
    const vid = idKey(el.dataset.pdcStoppageEdit || el.dataset.pdcStoppageCancel || el.dataset.pdcStoppageClear || el.dataset.pdcStoppageChecked || el.dataset.pdcStoppageHistory);
    if (!UUID.test(vid)) return;
    const st = ui.get(vid) || {};
    if (el.dataset.pdcStoppageEdit) { if (!canEdit) return; ui.set(vid, { ...st, editing: true, message: '', draftEta: undefined, draftNote: undefined }); rerender(vid); }
    else if (el.dataset.pdcStoppageCancel) { ui.set(vid, { ...st, editing: false, message: '' }); rerender(vid); }
    else if (el.dataset.pdcStoppageClear) save(vid, 'clear');
    else if (el.dataset.pdcStoppageChecked) save(vid, 'check');
    else showHistory(vid);
  }, true);
  document.addEventListener('change', event => {
    const box = event.target?.closest?.('[data-pdc-stoppage-place-now]');
    if (!box) return;
    event.stopPropagation();
    const vid = idKey(box.dataset.pdcStoppagePlaceNow);
    if (UUID.test(vid)) placeNow(vid, box.checked === true);
  }, true);
  document.addEventListener('submit', event => {
    const form = event.target?.closest?.('[data-pdc-stoppage-form]');
    if (!form) return;
    event.preventDefault();
    event.stopPropagation();
    const vid = idKey(form.dataset.pdcStoppageForm);
    if (UUID.test(vid)) save(vid, 'save');
  }, true);
  document.addEventListener('input', event => {
    const field = event.target?.closest?.('[data-pdc-stoppage-date],[data-pdc-stoppage-note]');
    if (!field) return;
    const vid = idKey(field.dataset.pdcStoppageDate || field.dataset.pdcStoppageNote);
    if (!UUID.test(vid)) return;
    const st = ui.get(vid) || {};
    ui.set(vid, { ...st, draftEta: field.dataset.pdcStoppageDate ? field.value : st.draftEta, draftNote: field.dataset.pdcStoppageNote ? field.value : st.draftNote });
  });

  window.workshopPartsEtaStoppageSectionHtml = () => plannerSectionHtml([...placedById.values()]);
  window.PDC_PARTS_STOPPAGE = Object.freeze({ VERSION, reload: load, shownEta, plannerSectionHtml });
  load();
  setInterval(load, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setTimeout(() => { if (!installed && !missing) load(); }, 4000);
})();
