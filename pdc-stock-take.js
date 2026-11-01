/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/*
 * Stock take. r720 (F330) Craig, 29 Oct 2026; r808 (F443) Craig, 1 Nov 2026 18:36-18:40.
 * Every car at PMB with a key, key number lowest to highest. Tap a car: it drops down and is marked Seen (blue) for
 * everyone. Every item on the car shows (no station picking): a green ✓ says it is there (ticks the line on the board,
 * set_panel_line_completion_565, the same tick as the vehicle side panel) and a red ✗ says it is missing (r723 stock take
 * cross). Close at the bottom marks the car Processed (orange). Missing (whole car not found) and "Found a car not on the
 * list" stay. Other people's changes show within about 5 seconds (get_pdc_stock_take_rev_808 marker, list reloaded only
 * on change). An administrator can start a New stock take: every car goes back to Not seen (old rounds are kept).
 * pmgpdc.au/stocktake opens it, also on an iPad.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.11.01.r808';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const POLL_MS = 5000;
  const FULL_MS = 120000;
  const STATION_LABEL = Object.freeze({
    FITTING: 'Fitting', FABRICATION: 'Fabrication', ELECTRICAL: 'Electrical', HOIST: 'Hoist', TYRE: 'Tyres', TINT: 'Tint',
    SUBLET: 'Sublet', PARTS: 'Parts', BUS_4X4: 'Bus 4x4', BUS_MECHANICAL: 'Bus 4x4', BUS_ACCESSORIES: 'Bus 4x4',
    BUS_ELECTRICAL: 'Bus 4x4', BUS_QA: 'Bus 4x4', PIT_INSPECTION: 'Pit', UNALLOCATED_MAPPING_REVIEW: 'Other',
  });
  const ERRORS = Object.freeze({
    controller_required: 'Only a controller login can tick items.',
    administrator_required: 'Only an administrator can start a new stock take.',
    operation_not_found: 'That item is no longer on this car. Reloaded.',
    invalid_line: 'That item could not be ticked.',
    completion_unavailable: 'Not saved. Check the connection and try again.',
  });
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const hhmm = iso => {
    const t = Date.parse(iso || '');
    if (!Number.isFinite(t)) return '';
    const d = new Date(t + 8 * 3600 * 1000);
    return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
  };
  const dayTime = iso => {
    const t = Date.parse(iso || '');
    if (!Number.isFinite(t)) return '';
    const d = new Date(t + 8 * 3600 * 1000);
    return `${d.getUTCDate()}/${d.getUTCMonth() + 1} ${hhmm(iso)}`;
  };
  const keyMatch = (car, q) => {
    const key = String(car.k ?? '').replace(/^0+/, '').toLowerCase();
    const qKey = q.replace(/^k(ey)?\s*/, '').replace(/^0+/, '');
    return (qKey && key === qKey) || String(car.s ?? '').toLowerCase().includes(q);
  };
  /** A car's stock take state: missing > processed (Close pressed) > seen (opened) > not seen. */
  function carStatus(car) {
    if (car?.missing) return ['missing', 'Missing'];
    if (car?.processed_at) return ['processed', 'Processed'];
    if (car?.seen_at) return ['seen', 'Seen'];
    return ['todo', 'Not seen'];
  }
  /** Cars to show for the search and the switches. */
  function visibleCars(payload, view) {
    const q = String(view?.search || '').trim().toLowerCase();
    return (payload?.cars || []).filter(car => {
      if (q && !keyMatch(car, q)) return false;
      if (view?.hideProcessed && car.processed_at && !car.missing) return false;
      if (view?.missingOnly && !car.missing) return false;
      return true;
    });
  }
  function totals(payload) {
    // each car counts once, by the colour it shows (missing > processed > seen > not seen)
    const t = { cars: 0, todo: 0, seen: 0, processed: 0, missing: 0 };
    for (const car of payload?.cars || []) { t.cars += 1; t[carStatus(car)[0]] += 1; }
    return t;
  }
  function lineHtml(car, line, canTick, now) {
    const id = `${car.id}|${line.id}`;
    const xed = line.x === true && !line.done;
    const fresh = (line.done && line.at && now - Date.parse(line.at) < 120000) || (xed && line.x_at && now - Date.parse(line.x_at) < 120000);
    const who = line.done ? `✓ ${line.by ? `${esc(line.by)}${line.at ? ` ${esc(hhmm(line.at))}` : ''}` : 'Done'}`
      : xed ? `✗ Missing${line.x_by ? ` · ${esc(line.x_by)}${line.x_at ? ` ${esc(hhmm(line.x_at))}` : ''}` : ''}` : '';
    const label = STATION_LABEL[line.st] || (line.st ? String(line.st).replace(/_/g, ' ').toLowerCase() : '');
    const dis = canTick ? '' : ' disabled';
    return `<li class="st-line${line.done ? ' is-done' : ''}${xed ? ' is-x' : ''}${fresh ? ' is-fresh' : ''}">`
      + `<div class="st-item"><span class="st-d">${esc(line.d)}</span>`
      + `<span class="st-meta">${label ? `<em>${esc(label)}</em>` : ''}${who ? `<b>${who}</b>` : ''}</span></div>`
      + `<div class="st-btns"><button type="button" class="st-yes" data-st-yes="${esc(id)}" aria-pressed="${line.done === true}"${dis} aria-label="${esc(line.d)}: it is there" title="It is there (ticks it on the board)">✓</button>`
      + `<button type="button" class="st-no" data-st-no="${esc(id)}" aria-pressed="${xed}"${dis} aria-label="${esc(line.d)}: missing" title="It is missing">✗</button></div></li>`;
  }
  function itemsHtml(car, detail, canTick, view, now) {
    if (!detail) return '<p class="st-loading">Loading the items…</p>';
    if (detail.ok === false) return `<p class="st-error">${esc(detail.error === 'not_authorized' ? 'This login cannot see the items.' : 'Could not load the items. Close and open it again.')}</p>`;
    const lines = detail.l || [];
    const notes = (detail.n || []).length ? `<p class="st-notes">${detail.n.map(esc).join(' · ')}</p>` : '';
    const there = lines.filter(line => line.done).length;
    const gone = lines.filter(line => line.x && !line.done).length;
    const left = lines.length - there - gone;
    const list = lines.length ? `<ul class="st-lines">${lines.map(line => lineHtml(car, line, canTick, now)).join('')}</ul>` : '<p class="st-empty">No work items on this car.</p>';
    const tally = `<span class="st-tally"><b class="st-t-yes">✓ ${there}</b><b class="st-t-no">✗ ${gone}</b>${left ? `<b class="st-t-left">${left} not checked</b>` : ''}</span>`;
    const done = car.processed_at ? `<span class="st-closed-by">Processed${car.processed_by ? ` by ${esc(car.processed_by)}` : ''} ${esc(hhmm(car.processed_at))}${canTick ? ` · <button type="button" class="st-link" data-st-reopen="${esc(car.id)}">Undo</button>` : ''}</span>` : '';
    const close = canTick ? `<button type="button" class="st-close" data-st-close="${esc(car.id)}"${view?.pending?.has(`close|${car.id}`) ? ' disabled' : ''}>Close</button>` : `<button type="button" class="st-close st-close-view" data-st-toggle="${esc(car.id)}">Close</button>`;
    return `${notes}${list}<div class="st-foot">${tally}${done}${close}</div>`;
  }
  function carHtml(car, canTick, view, now) {
    const open = view?.openCar === car.id;
    const status = carStatus(car);
    const error = view?.errors?.get(car.id);
    // Craig 29 Oct 13:15: "if we go to a bay and that vehicle isn't here, put down missing so we have to find it later".
    const missBtn = canTick ? `<button type="button" class="st-missing" data-st-missing="${esc(car.id)}" aria-pressed="${car.missing === true}"${view?.pending?.has(`miss|${car.id}`) ? ' disabled' : ''}>${car.missing ? 'Found it' : 'Missing'}</button>` : '';
    const who = car.missing ? (car.missing_by ? `${esc(car.missing_by)} ${esc(hhmm(car.missing_at))}` : '')
      : car.processed_at ? (car.processed_by ? `${esc(car.processed_by)} ${esc(hhmm(car.processed_at))}` : '')
      : car.seen_at ? (car.seen_by ? `${esc(car.seen_by)} ${esc(hhmm(car.seen_at))}` : '') : '';
    const missNote = car.missing ? `<p class="st-miss-note">CAR MISSING${car.missing_by ? ` · flagged by ${esc(car.missing_by)}${car.missing_at ? ` ${esc(hhmm(car.missing_at))}` : ''}` : ''}. Find it, then tap Found it.</p>` : '';
    return `<section class="st-car is-${status[0]}${open ? ' is-open' : ''}" data-st-car="${esc(car.id)}">`
      + `<h3><button type="button" class="st-toggle" data-st-toggle="${esc(car.id)}" aria-expanded="${open}"><span class="st-key">Key ${esc(car.k)}</span>`
      + `<span class="st-stock">${esc(car.s || '')}</span><span class="st-veh">${esc(car.v || '')}</span>`
      + `<span class="st-status">${esc(status[1])}</span>${who ? `<span class="st-who">${who}</span>` : ''}<span class="st-chev" aria-hidden="true">${open ? '▲' : '▼'}</span></button>${missBtn}</h3>`
      + `${missNote}${error ? `<p class="st-error" role="alert">${esc(error)}</p>` : ''}`
      + `${open ? `<div class="st-body">${itemsHtml(car, view?.details?.get(car.id), canTick, view, now)}</div>` : ''}</section>`;
  }
  function sumHtml(payload, view) {
    const t = totals(payload);
    return `${t.cars} cars at PMB · <b class="st-s-todo">${t.todo} not seen</b> · <b class="st-s-seen">${t.seen} seen</b> · <b class="st-s-done">${t.processed} processed</b>`
      + `${t.missing ? ` · <b class="st-sum-miss">${t.missing} missing</b>` : ''}${payload?.can_tick === true ? '' : ' · <b>view only: a controller login ticks items</b>'}`
      + `${payload?.round_at ? `<span class="st-round">Stock take started ${esc(dayTime(payload.round_at))}</span>` : ''}`
      + `<span class="st-live" title="Other people's changes show here within about 5 seconds">Live${view?.updated ? ` · ${esc(hhmm(view.updated))}` : ''}</span>`;
  }
  function panelHtml(payload, view, now = Date.now()) {
    const canTick = payload?.can_tick === true;
    const cars = visibleCars(payload, view);
    const reset = payload?.can_reset === true ? `<button type="button" class="st-reset" data-st-reset${view?.armReset ? ' aria-pressed="true"' : ''}>${view?.armReset ? 'Tap again: every car back to Not seen' : 'New stock take'}</button>` : '';
    return `<div class="st-bar"><div class="st-tools"><input type="search" data-st-search placeholder="Key or stock number" aria-label="Find key or stock" value="${esc(view.search || '')}">`
      + `<label class="st-open"><input type="checkbox" data-st-hide${view.hideProcessed ? ' checked' : ''}> Hide processed</label>`
      + `<label class="st-open st-open-miss"><input type="checkbox" data-st-missing-only${view.missingOnly ? ' checked' : ''}> Missing only</label>${reset}</div>`
      + `<p class="st-sum">${sumHtml(payload, view)}</p></div>`
      + foundBoxHtml(view, canTick)
      + `<div class="st-list-wrap">${listHtml(cars, canTick, view, now)}</div>`;
  }
  function listHtml(cars, canTick, view, now) {
    return cars.length ? `<div class="st-list">${cars.map(car => carHtml(car, canTick, view, now)).join('')}</div>` : '<p class="st-empty">No cars match.</p>';
  }
  // r724 (F334, Craig 13:53): a box for a car that is out there but not on the list: key and stock number (and a note).
  // Shared list with who added it and where the board has that stock now; "Sorted" takes it off.
  function foundListHtml(found, canTick) {
    const rows = Array.isArray(found) ? found : [];
    if (!rows.length) return '<p class="st-found-none">No extra cars logged.</p>';
    return `<ul class="st-found-rows">${rows.map(f => {
      const b = f.board;
      const where = !b ? '<b class="st-fb-none">Not on the board</b>'
        : b.on_board ? `On the board: <b>${esc(b.where)}</b>${b.key && b.key !== f.k ? ` (board key ${esc(b.key)})` : ''}`
        : `On the board as <b>${esc(b.state)}</b> (not active)`;
      return `<li><span class="st-fk">${f.k ? `Key ${esc(f.k)}` : 'No key'}</span><span class="st-fs">${esc(f.s || 'no stock')}</span>`
        + `<span class="st-fw">${where}</span>${f.note ? `<span class="st-fn">${esc(f.note)}</span>` : ''}`
        + `<small>${esc(f.by || '')} ${esc(hhmm(f.at))}</small>`
        + `${canTick ? `<button type="button" class="st-sorted" data-st-sorted="${esc(f.id)}">Sorted</button>` : ''}</li>`;
    }).join('')}</ul>`;
  }
  function foundBoxHtml(view, canTick) {
    if (!Array.isArray(view?.found)) return ''; // the box shows once the server has the found list (r724 DB)
    const rows = view.found;
    const form = canTick ? `<form class="st-found-form" data-st-found-form autocomplete="off">`
      + `<input data-st-found-key inputmode="numeric" maxlength="32" placeholder="Key number" aria-label="Key number">`
      + `<input data-st-found-stock maxlength="40" placeholder="Stock number" aria-label="Stock number">`
      + `<input data-st-found-note maxlength="300" placeholder="Where / note (optional)" aria-label="Note">`
      + `<button type="submit">Add car</button><span class="st-found-msg" data-st-found-msg role="status"></span></form>` : '';
    return `<details class="st-found" data-st-found${rows.length ? ' open' : ''}><summary>Found a car not on the list?${rows.length ? ` <b>${rows.length} logged</b>` : ''}</summary>`
      + `${form}<div class="st-found-list">${foundListHtml(rows, canTick)}</div></details>`;
  }

  const api = { VERSION, STATION_LABEL, carStatus, visibleCars, totals, panelHtml, carHtml, itemsHtml, keyMatch, foundListHtml };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.PdcStockTake = api;
  if (typeof document === 'undefined') return;
  // The sidebar override (pdc-sidebar-compact.css) must stay the last <link> in index.html, so the page adds its own.
  if (!document.querySelector('link[data-pdc-stock-take]')) {
    const link = document.createElement('link');
    link.rel = 'stylesheet'; link.href = `pdc-stock-take.css?r808=${VERSION}`; link.dataset.pdcStockTake = '1';
    document.head.appendChild(link);
  }

  const state = { payload: null, error: '', loading: false, rev: '', timer: null, lastFull: 0, open: false,
    view: { search: '', hideProcessed: false, missingOnly: false, openCar: '', armReset: false, pending: new Set(), errors: new Map(), details: new Map(), updated: '' } };
  const host = () => document.getElementById('stock-take-content');
  const me = () => root.PDC_AUTH_CONTEXT?.displayName || 'You';

  async function rpc(name, body) {
    const config = root.PDC_SUPABASE_CONFIG;
    const token = typeof root.getPdcSupabaseAccessToken === 'function' ? root.getPdcSupabaseAccessToken() : '';
    if (!root.PDC_AUTH_CONTEXT?.userId || !token || config?.projectRef !== PROJECT) throw Error('Sign in to see the stock take.');
    const response = await fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(() => ({}));
    if (response.status === 404) throw Error('The stock take is not on this database yet.');
    if (!response.ok) throw Error(data?.message || 'Could not load the stock take.');
    return data;
  }
  function render() {
    const el = host();
    if (!el) return;
    if (state.error && !state.payload) { el.innerHTML = `<p class="st-error">${esc(state.error)}</p>`; return; }
    if (!state.payload) { el.innerHTML = '<p class="st-empty">Loading the cars at PMB…</p>'; return; }
    if (state.payload.ok === false) { el.innerHTML = `<p class="st-error">${state.payload.error === 'not_authorized' ? 'This login cannot see the stock take.' : 'Not available.'}</p>`; return; }
    const scroll = root.scrollY;
    // Craig 29 Oct 13:13: an update must never reload or jump anyone's screen while they walk around. After the first
    // draw the bar (search, switches) and the found-a-car box are never redrawn, so typing and focus are kept; only the
    // summary, the found list and the cars that changed are swapped in place.
    if (!el.querySelector('.st-bar') || state.barDirty) {
      state.barDirty = false;
      el.innerHTML = panelHtml(state.payload, state.view);
    } else {
      const next = document.createElement('div');
      next.innerHTML = panelHtml(state.payload, state.view);
      const swap = sel => { const a = el.querySelector(sel); const b = next.querySelector(sel); if (a && b && a.innerHTML !== b.innerHTML) a.innerHTML = b.innerHTML; };
      swap('.st-sum'); swap('.st-found-list');
      const reset = el.querySelector('[data-st-reset]'); const newReset = next.querySelector('[data-st-reset]');
      if (reset && newReset && reset.outerHTML !== newReset.outerHTML) reset.replaceWith(newReset.cloneNode(true));
      const summary = el.querySelector('.st-found > summary'); const newSummary = next.querySelector('.st-found > summary');
      if (summary && newSummary && summary.innerHTML !== newSummary.innerHTML) summary.innerHTML = newSummary.innerHTML;
      const list = el.querySelector('.st-list'); const fresh = next.querySelector('.st-list');
      const ids = nodes => [...nodes].map(node => node.dataset.stCar).join(',');
      if (list && fresh && ids(list.children) === ids(fresh.children)) {
        [...fresh.children].forEach((car, i) => { const old = list.children[i]; if (old.innerHTML !== car.innerHTML || old.className !== car.className) old.replaceWith(car.cloneNode(true)); });
      } else swap('.st-list-wrap');
    }
    if (Math.abs(root.scrollY - scroll) > 2) root.scrollTo(0, scroll);
  }
  async function loadCar(id) {
    try {
      const detail = await rpc('get_pdc_stock_take_car_808', { p_vehicle_id: id });
      if (detail && (detail.ok === false || detail.id === id)) state.view.details.set(id, detail);
    } catch (_) { if (!state.view.details.has(id)) state.view.details.set(id, { ok: false, error: 'load_failed' }); }
    render();
  }
  async function load() {
    if (state.loading) return;
    state.loading = true; const gen = saveGen;
    try {
      const [payload, found] = await Promise.all([
        rpc('get_pdc_stock_take_808', {}),
        rpc('get_pdc_stock_take_found_724', {}).catch(() => null),
      ]);
      if (found?.ok === true) { if (!Array.isArray(state.view.found)) state.barDirty = true; state.view.found = found.found || []; }
      if (gen !== saveGen) return; // a change landed while this was loading; keep it, settle() loads again
      if (state.payload && payload?.can_reset !== state.payload.can_reset) state.barDirty = true;
      state.payload = payload; state.error = ''; state.rev = payload?.rev || ''; state.lastFull = Date.now(); state.view.updated = payload?.now || '';
      const openCar = state.view.openCar;
      if (openCar) void loadCar(openCar); // someone else may have ticked an item on the open car
    } catch (error) { state.error = error?.message || 'Could not load the stock take.'; }
    finally { state.loading = false; render(); }
  }
  async function poll() {
    if (!state.open || document.visibilityState === 'hidden' || state.loading || state.view.pending.size || inflight) return;
    try {
      const rev = await rpc('get_pdc_stock_take_rev_808', {});
      if ((rev && rev !== state.rev) || Date.now() - state.lastFull > FULL_MS) await load();
    } catch (_) { /* keep the last list; the next poll tries again */ }
  }
  // A tick, a cross, Seen or Close shows at once and saves in the background (no "Saving" wait, no reload per tap). One
  // refresh runs a few seconds after the last save, so other people's changes still come in.
  let inflight = 0; let settleTimer = null; let saveGen = 0;
  function settle() {
    clearTimeout(settleTimer);
    settleTimer = setTimeout(() => { if (!inflight) void load(); }, 2500);
  }
  function findLine(id) {
    const [carId, lineId] = id.split('|');
    const detail = state.view.details.get(carId);
    return { carId, lineId, line: detail?.l?.find(entry => entry.id === lineId) };
  }
  const findCar = id => (state.payload?.cars || []).find(entry => entry.id === id);
  async function save(name, body, onFail, carId) {
    inflight += 1; saveGen += 1; state.view.errors.delete(carId);
    try {
      const result = await rpc(name, body);
      if (result?.ok !== true) { onFail(); state.view.errors.set(carId, ERRORS[result?.error] || 'Not saved. Try again.'); render(); }
      return result;
    } catch (_) { onFail(); state.view.errors.set(carId, ERRORS.completion_unavailable); render(); return null; }
    finally { inflight -= 1; settle(); }
  }
  // Green ✓: it is there. Ticks the line on the board (and clears a red ✗). Tap again to take the tick off.
  function markThere(id) {
    const { carId, lineId, line } = findLine(id);
    if (!line) return;
    const before = { done: line.done, by: line.by, at: line.at, x: line.x, x_by: line.x_by, x_at: line.x_at };
    const on = line.done !== true;
    line.done = on; line.by = on ? me() : null; line.at = new Date().toISOString();
    if (on && line.x) { line.x = false; void save('set_pdc_stock_take_x_723', { p_vehicle_id: carId, p_line_identity: lineId, p_x: false }, () => {}, carId); }
    render();
    void save('set_panel_line_completion_565', { p_vehicle_id: carId, p_line_identity: lineId, p_completed: on }, () => Object.assign(line, before), carId);
  }
  // Red ✗: it is missing (r723 stock take cross). On a ticked item it also takes the board tick off. Tap again to clear.
  function markMissingItem(id) {
    const { carId, lineId, line } = findLine(id);
    if (!line) return;
    const before = { done: line.done, by: line.by, at: line.at, x: line.x, x_by: line.x_by, x_at: line.x_at };
    const on = !(line.x === true && !line.done);
    if (on && line.done) {
      line.done = false; line.by = null; line.at = new Date().toISOString();
      void save('set_panel_line_completion_565', { p_vehicle_id: carId, p_line_identity: lineId, p_completed: false }, () => Object.assign(line, before), carId);
    }
    line.x = on; line.x_by = on ? me() : null; line.x_at = new Date().toISOString();
    render();
    void save('set_pdc_stock_take_x_723', { p_vehicle_id: carId, p_line_identity: lineId, p_x: on }, () => Object.assign(line, before), carId);
  }
  // Opening a car drops it down, loads its items and marks it Seen for everyone (controllers; first opener is kept).
  function toggleCar(id) {
    const car = findCar(id);
    if (state.view.openCar === id) { state.view.openCar = ''; render(); return; }
    state.view.openCar = id;
    if (car && !car.seen_at && state.payload?.can_tick === true) {
      const before = { seen_at: car.seen_at, seen_by: car.seen_by };
      car.seen_at = new Date().toISOString(); car.seen_by = me();
      void save('set_pdc_stock_take_car_808', { p_vehicle_id: id, p_action: 'seen' }, () => Object.assign(car, before), id);
    }
    render();
    void loadCar(id);
    const node = document.querySelector(`[data-st-car="${CSS.escape(id)}"]`);
    if (node && node.getBoundingClientRect().top < 0) node.scrollIntoView({ block: 'start' });
  }
  // Close: the car is Processed (orange) and folds up.
  async function closeCar(id) {
    const car = findCar(id); const key = `close|${id}`;
    if (!car || state.view.pending.has(key)) return;
    state.view.pending.add(key);
    const before = { processed_at: car.processed_at, processed_by: car.processed_by, seen_at: car.seen_at, seen_by: car.seen_by };
    car.processed_at = new Date().toISOString(); car.processed_by = me(); car.seen_at = car.seen_at || car.processed_at; car.seen_by = car.seen_by || me();
    state.view.openCar = '';
    render();
    const node = document.querySelector(`[data-st-car="${CSS.escape(id)}"]`);
    if (node && node.getBoundingClientRect().top < 0) node.scrollIntoView({ block: 'start' });
    try { await save('set_pdc_stock_take_car_808', { p_vehicle_id: id, p_action: 'processed' }, () => Object.assign(car, before), id); }
    finally { state.view.pending.delete(key); }
  }
  function reopenCar(id) {
    const car = findCar(id);
    if (!car) return;
    const before = { processed_at: car.processed_at, processed_by: car.processed_by };
    car.processed_at = null; car.processed_by = null;
    render();
    void save('set_pdc_stock_take_car_808', { p_vehicle_id: id, p_action: 'reopen' }, () => Object.assign(car, before), id);
  }
  let armTimer = null;
  async function newRound() {
    if (!state.view.armReset) {
      state.view.armReset = true; render();
      clearTimeout(armTimer); armTimer = setTimeout(() => { state.view.armReset = false; render(); }, 5000);
      return;
    }
    clearTimeout(armTimer); state.view.armReset = false; state.view.openCar = ''; render();
    try {
      const result = await rpc('start_pdc_stock_take_round_808', {});
      if (result?.ok !== true) state.error = ERRORS[result?.error] || 'Not started. Try again.';
    } catch (_) { state.error = ERRORS.completion_unavailable; }
    await load();
  }
  async function addFound(form) {
    const key = form.querySelector('[data-st-found-key]'); const stock = form.querySelector('[data-st-found-stock]'); const note = form.querySelector('[data-st-found-note]');
    const msg = form.querySelector('[data-st-found-msg]'); const button = form.querySelector('button');
    if (!key.value.trim() && !stock.value.trim()) { msg.textContent = 'Put in the key or the stock number.'; return; }
    button.disabled = true; msg.textContent = 'Adding…';
    try {
      const result = await rpc('set_pdc_stock_take_found_724', { p_key: key.value, p_stock: stock.value, p_note: note.value || null });
      if (result?.ok === true) { key.value = ''; stock.value = ''; note.value = ''; msg.textContent = 'Added. Everyone can see it.'; key.focus(); }
      else msg.textContent = ERRORS[result?.error] || 'Not added. Try again.';
    } catch (_) { msg.textContent = ERRORS.completion_unavailable; }
    finally { button.disabled = false; await load(); }
  }
  async function sortFound(id, button) {
    button.disabled = true;
    try { await rpc('set_pdc_stock_take_found_724', { p_key: null, p_stock: null, p_note: null, p_sorted_id: id }); } catch (_) { /* reload shows the truth */ }
    await load();
  }
  async function flagMissing(carId, missing) {
    const car = findCar(carId);
    const key = `miss|${carId}`;
    if (!car || state.view.pending.has(key)) return;
    state.view.pending.add(key); state.view.errors.delete(carId);
    car.missing = missing; car.missing_by = missing ? me() : null; car.missing_at = new Date().toISOString();
    render();
    try {
      const result = await rpc('set_pdc_stock_take_missing_720', { p_vehicle_id: carId, p_missing: missing });
      if (result?.ok !== true) state.view.errors.set(carId, ERRORS[result?.error] || 'Not saved. Try again.');
    } catch (_) { state.view.errors.set(carId, ERRORS.completion_unavailable); }
    finally { state.view.pending.delete(key); await load(); }
  }
  function bind() {
    const el = host();
    if (!el || el.dataset.stBound) return;
    el.dataset.stBound = '1';
    el.addEventListener('change', event => {
      if (event.target.matches?.('[data-st-hide]')) { state.view.hideProcessed = event.target.checked; render(); }
      if (event.target.matches?.('[data-st-missing-only]')) { state.view.missingOnly = event.target.checked; render(); }
    });
    el.addEventListener('input', event => { if (event.target.matches?.('[data-st-search]')) { state.view.search = event.target.value; render(); } });
    el.addEventListener('click', event => {
      const t = event.target;
      const yes = t.closest?.('[data-st-yes]');
      if (yes) { markThere(yes.dataset.stYes); return; }
      const no = t.closest?.('[data-st-no]');
      if (no) { markMissingItem(no.dataset.stNo); return; }
      const close = t.closest?.('[data-st-close]');
      if (close) { void closeCar(close.dataset.stClose); return; }
      const reopen = t.closest?.('[data-st-reopen]');
      if (reopen) { reopenCar(reopen.dataset.stReopen); return; }
      const toggle = t.closest?.('[data-st-toggle]');
      if (toggle) { toggleCar(toggle.dataset.stToggle); return; }
      const sorted = t.closest?.('[data-st-sorted]');
      if (sorted) { void sortFound(sorted.dataset.stSorted, sorted); return; }
      const miss = t.closest?.('[data-st-missing]');
      if (miss) { void flagMissing(miss.dataset.stMissing, miss.getAttribute('aria-pressed') !== 'true'); return; }
      if (t.closest?.('[data-st-reset]')) void newRound();
    });
    el.addEventListener('submit', event => {
      const form = event.target.closest?.('[data-st-found-form]');
      if (!form) return;
      event.preventDefault();
      void addFound(form);
    });
  }
  // While the Stock take is open, a new board release does not reload the tablet (pdc-auto-reload.js waits while
  // PDC_UNSAVED_WORK is true); it reloads once they leave this page.
  api.open = function open() {
    state.open = true; root.PDC_UNSAVED_WORK = true; bind(); render(); void load();
    clearInterval(state.timer); state.timer = setInterval(() => { void poll(); }, POLL_MS);
  };
  api.close = function close() { state.open = false; root.PDC_UNSAVED_WORK = false; clearInterval(state.timer); state.timer = null; };
  document.addEventListener('visibilitychange', () => { if (state.open && document.visibilityState === 'visible') void load(); });

  // On a phone or iPad the board is a QC-only client (pdc-qc-mobile.js turns every view into QC except Fitters bay).
  // As r711 does for Sublet · PSC, this wrapper loads first and turns 'qc' back into 'stock-take' when the stock take
  // was asked for (menu tap or pmgpdc.au/stocktake).
  if (typeof root.showView === 'function') {
    const phone = root.matchMedia?.('(max-width: 900px), (pointer: coarse) and (max-width: 1024px)');
    let want = root.location?.hash === '#/stock-take';
    document.addEventListener('click', event => {
      const nav = event.target.closest?.('[data-view]');
      if (nav) want = nav.dataset.view === 'stock-take';
    }, true);
    root.addEventListener('hashchange', () => { if (root.location.hash === '#/stock-take') want = true; });
    const inner = root.showView;
    root.showView = function stockTakePhoneShowView(view, options) {
      const next = view === 'qc' && phone?.matches && want ? 'stock-take' : view;
      if (next === 'stock-take') document.documentElement.classList.remove('pdc-qc-phone');
      return inner.call(this, next, options);
    };
  }
})(typeof window !== 'undefined' ? window : globalThis);
