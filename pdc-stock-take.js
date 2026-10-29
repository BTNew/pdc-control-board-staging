/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/*
 * r720 (F330): Stock take. Craig, 29 Oct 2026 12:58.
 * Craig, Oleg and Garrath walk PMB with iPads. Every vehicle at PMB with work on the chosen stations, sorted by key
 * number. Ticking an item ticks that line on the board (set_panel_line_completion_565, the same tick as the vehicle
 * side panel; controllers only), and everyone else's screen shows it, with who ticked it, within about 5 seconds.
 * Reads get_pdc_stock_take_720 (the list) and polls get_pdc_stock_take_rev_720 (a tiny change marker) while open,
 * so the list is fetched again only when something changed. pmgpdc.au/stocktake opens it, also on an iPad.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.29.r725';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const POLL_MS = 5000;
  const FULL_MS = 120000;
  const STATIONS = Object.freeze([
    ['FITTING', 'Fitting'], ['FABRICATION', 'Fabrication'], ['ELECTRICAL', 'Electrical'],
    ['HOIST', 'Hoist'], ['TYRE', 'Tyres'], ['TINT', 'Tint'],
  ]);
  const STATION_LABEL = Object.fromEntries(STATIONS);
  const PICK_KEY = 'pdc.stock-take.stations.v1';
  const ERRORS = Object.freeze({
    controller_required: 'Only a controller login can tick items.',
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
  const keyMatch = (car, q) => {
    const key = String(car.k ?? '').replace(/^0+/, '').toLowerCase();
    const qKey = q.replace(/^k(ey)?\s*/, '').replace(/^0+/, '');
    return (qKey && key === qKey) || String(car.s ?? '').toLowerCase().includes(q);
  };

  // r723 (F333, Craig 13:39): X = "we looked at the car and this item is not there". A car is checked when every item
  // is ticked (done) or X'd (seen, not done).
  const carChecked = car => (car.l || []).length > 0 && (car.l || []).every(line => line.done || line.x);
  /** Cars to show for the search and the "open only" switch. */
  function visibleCars(payload, view) {
    const q = String(view?.search || '').trim().toLowerCase();
    return (payload?.cars || []).filter(car => {
      if (q && !keyMatch(car, q)) return false;
      if (view?.openOnly && carChecked(car)) return false;
      if (view?.missingOnly && !car.missing) return false;
      return true;
    });
  }
  function totals(payload) {
    let lines = 0; let done = 0; let carsDone = 0; let missing = 0; let xs = 0; let checked = 0;
    for (const car of payload?.cars || []) {
      if (car.missing) missing += 1;
      if (carChecked(car)) checked += 1;
      xs += (car.l || []).filter(line => line.x && !line.done).length;
      const n = (car.l || []).length; const d = (car.l || []).filter(line => line.done).length;
      lines += n; done += d; if (n && d === n) carsDone += 1;
    }
    return { cars: (payload?.cars || []).length, carsDone, lines, done, missing, xs, checked };
  }
  function lineHtml(car, line, canTick, view, now) {
    const id = `${car.id}|${line.id}`;
    const fresh = line.done && line.at && now - Date.parse(line.at) < 120000;
    const who = line.done ? (line.by ? `${esc(line.by)}${line.at ? ` ${esc(hhmm(line.at))}` : ''}` : 'Done') : '';
    const xed = line.x === true && !line.done;
    const xWho = xed ? `${line.x_by ? esc(line.x_by) : ''}${line.x_at ? ` ${esc(hhmm(line.x_at))}` : ''}`.trim() : '';
    const hours = line.h != null && line.h !== '' ? `${esc(line.h)} h` : '';
    const xBtn = canTick ? `<button type="button" class="st-x" data-st-x="${esc(id)}" aria-pressed="${xed}"${line.done ? ' disabled' : ''} aria-label="${esc(line.d)}: looked, not done" title="Looked at the car: this item is not done">✗</button>` : '';
    return `<li class="st-line${line.done ? ' is-done' : ''}${xed ? ' is-x' : ''}${fresh ? ' is-fresh' : ''}"><div class="st-row"><label>`
      + `<input type="checkbox" data-st-tick="${esc(id)}"${line.done ? ' checked' : ''}${!canTick ? ' disabled' : ''} aria-label="${esc(line.d)} done">`
      + `<span class="st-d">${esc(line.d)}${(view?.stations || []).length > 1 ? ` <em>${esc(STATION_LABEL[line.st] || line.st)}</em>` : ''}</span>`
      + `<span class="st-meta">${who ? `<b>✓ ${who}</b>` : ''}${xed ? `<b class="st-xwho">✗ Not done${xWho ? ` · ${xWho}` : ''}</b>` : ''}${hours ? `<small>${hours}</small>` : ''}</span></label>${xBtn}</div></li>`;
  }
  function carHtml(car, canTick, view, now) {
    const lines = car.l || [];
    const done = lines.filter(line => line.done).length;
    const all = lines.length > 0 && done === lines.length;
    const error = view?.errors?.get(car.id);
    // Craig 13:15: "if we go to a bay and that vehicle isn't here, put down missing so we have to find it later".
    const missBtn = canTick ? `<button type="button" class="st-missing" data-st-missing="${esc(car.id)}" aria-pressed="${car.missing === true}"${view?.pending?.has(`miss|${car.id}`) ? ' disabled' : ''}>${car.missing ? 'Found it' : 'Missing'}</button>` : '';
    const missNote = car.missing ? `<p class="st-miss-note">MISSING${car.missing_by ? ` · flagged by ${esc(car.missing_by)}${car.missing_at ? ` ${esc(hhmm(car.missing_at))}` : ''}` : ''}. Find it, then tap Found it.</p>` : '';
    // r725 (F335, Craig 14:05): each car is one collapsed row with its status; tap it to open its accessories, tick or
    // X them, and when every item is done it closes and the next car opens.
    const open = view?.openCar === car.id;
    const xs = lines.filter(line => line.x && !line.done).length;
    const status = car.missing ? ['missing', 'Missing'] : all ? ['done', 'All done'] : carChecked(car) ? ['looked', 'Looked at']
      : (done || xs) ? ['part', 'In progress'] : ['todo', 'Not checked'];
    return `<section class="st-car is-${status[0]}${open ? ' is-open' : ''}${all ? ' is-done' : ''}${car.missing ? ' is-missing' : ''}" data-st-car="${esc(car.id)}">`
      + `<h3><button type="button" class="st-toggle" data-st-toggle="${esc(car.id)}" aria-expanded="${open}"><span class="st-key">${car.k ? `Key ${esc(car.k)}` : 'No key'}</span>`
      + `<span class="st-stock">${esc(car.s || '')}</span><span class="st-veh">${esc(car.v || '')}</span>`
      + `<span class="st-status">${esc(status[1])}</span><span class="st-count">✓ ${done}/${lines.length}${xs ? ` · ✗ ${xs}` : ''}</span><span class="st-chev" aria-hidden="true">${open ? '▲' : '▼'}</span></button>${missBtn}</h3>`
      + `${missNote}${error ? `<p class="st-error" role="alert">${esc(error)}</p>` : ''}${open ? `<ul>${lines.map(line => lineHtml(car, line, canTick, view, now)).join('')}</ul>` : ''}</section>`;
  }
  function panelHtml(payload, view, now = Date.now()) {
    const canTick = payload?.can_tick === true;
    const t = totals(payload);
    const cars = visibleCars(payload, view);
    const chips = STATIONS.map(([code, label]) => `<button type="button" class="st-chip" data-st-station="${code}" aria-pressed="${(view.stations || []).includes(code)}">${label}</button>`).join('');
    return `<div class="st-bar"><div class="st-chips" role="group" aria-label="Stations">${chips}</div>`
      + `<div class="st-tools"><input type="search" data-st-search placeholder="Key or stock number" aria-label="Find key or stock" value="${esc(view.search || '')}">`
      + `<label class="st-open"><input type="checkbox" data-st-open${view.openOnly ? ' checked' : ''}> Hide checked cars</label>`
      + `<label class="st-open st-open-miss"><input type="checkbox" data-st-missing-only${view.missingOnly ? ' checked' : ''}> Missing only</label></div>`
      + `<p class="st-sum">${t.cars} cars at PMB · ${t.checked} checked · ${t.carsDone} finished · ${t.done} of ${t.lines} items ticked${t.xs ? ` · <b class="st-sum-miss">${t.xs} not done</b>` : ''}${t.missing ? ` · <b class="st-sum-miss">${t.missing} missing</b>` : ''}${canTick ? '' : ' · <b>view only: a controller login ticks items</b>'}`
      + `<span class="st-live" title="Other people's ticks show here within about 5 seconds">Live${view.updated ? ` · ${esc(hhmm(view.updated))}` : ''}</span></p></div>`
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
    if (!Array.isArray(view?.found)) return ''; // r725: the box shows once the server has the found list (r724 DB)
    const rows = view.found;
    const form = canTick ? `<form class="st-found-form" data-st-found-form autocomplete="off">`
      + `<input data-st-found-key inputmode="numeric" maxlength="32" placeholder="Key number" aria-label="Key number">`
      + `<input data-st-found-stock maxlength="40" placeholder="Stock number" aria-label="Stock number">`
      + `<input data-st-found-note maxlength="300" placeholder="Where / note (optional)" aria-label="Note">`
      + `<button type="submit">Add car</button><span class="st-found-msg" data-st-found-msg role="status"></span></form>` : '';
    return `<details class="st-found" data-st-found${rows.length ? ' open' : ''}><summary>Found a car not on the list?${rows.length ? ` <b>${rows.length} logged</b>` : ''}</summary>`
      + `${form}<div class="st-found-list">${foundListHtml(rows, canTick)}</div></details>`;
  }

  const api = { VERSION, STATIONS, visibleCars, totals, panelHtml, carHtml, keyMatch, foundListHtml };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.PdcStockTake = api;
  if (typeof document === 'undefined') return;
  // The sidebar override (pdc-sidebar-compact.css) must stay the last <link> in index.html, so the page adds its own.
  if (!document.querySelector('link[data-pdc-stock-take]')) {
    const link = document.createElement('link');
    link.rel = 'stylesheet'; link.href = `pdc-stock-take.css?r720=${VERSION}`; link.dataset.pdcStockTake = '1';
    document.head.appendChild(link);
  }

  function readPick() {
    try { const v = JSON.parse(root.localStorage.getItem(PICK_KEY) || 'null'); if (Array.isArray(v) && v.length) return v.filter(code => STATION_LABEL[code]); } catch (_) { /* default */ }
    return ['FITTING', 'FABRICATION'];
  }
  const state = { payload: null, error: '', loading: false, rev: '', timer: null, lastFull: 0, open: false,
    view: { stations: readPick(), search: '', openOnly: false, missingOnly: false, openCar: '', pending: new Set(), errors: new Map(), updated: '' } };
  const host = () => document.getElementById('stock-take-content');

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
    // draw the bar (station chips, search, switches) and the found-a-car box are never redrawn, so typing and focus are
    // kept; only the summary, the found list and the cars that changed are swapped in place.
    if (!el.querySelector('.st-bar') || state.barDirty) {
      state.barDirty = false;
      el.innerHTML = panelHtml(state.payload, state.view);
    } else {
      const next = document.createElement('div');
      next.innerHTML = panelHtml(state.payload, state.view);
      const swap = sel => { const a = el.querySelector(sel); const b = next.querySelector(sel); if (a && b && a.innerHTML !== b.innerHTML) a.innerHTML = b.innerHTML; };
      swap('.st-sum'); swap('.st-found-list');
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
  async function load() {
    if (state.loading) return;
    state.loading = true; const gen = saveGen;
    try {
      const [payload, found] = await Promise.all([
        rpc('get_pdc_stock_take_720', { p_stations: state.view.stations }),
        rpc('get_pdc_stock_take_found_724', {}).catch(() => null),
      ]);
      if (found?.ok === true) { if (!Array.isArray(state.view.found)) state.barDirty = true; state.view.found = found.found || []; }
      if (gen !== saveGen) return; // r725: a tick landed while this was loading; keep it, settle() loads again
      state.payload = payload; state.error = ''; state.rev = payload?.rev || ''; state.lastFull = Date.now(); state.view.updated = payload?.now || '';
    } catch (error) { state.error = error?.message || 'Could not load the stock take.'; }
    finally { state.loading = false; render(); }
  }
  async function poll() {
    if (!state.open || document.visibilityState === 'hidden' || state.loading || state.view.pending.size || inflight) return;
    try {
      const rev = await rpc('get_pdc_stock_take_rev_720', {});
      if ((rev && rev !== state.rev) || Date.now() - state.lastFull > FULL_MS) await load();
    } catch (_) { /* keep the last list; the next poll tries again */ }
  }
  // r725 (F335): a tick or X shows at once and saves in the background (no "Saving" wait, no reload per tick). One
  // refresh runs a few seconds after the last save, so other people's changes still come in.
  let inflight = 0; let settleTimer = null; let saveGen = 0;
  function settle() {
    clearTimeout(settleTimer);
    settleTimer = setTimeout(() => { if (!inflight) void load(); }, 2500);
  }
  function findLine(id) {
    const [carId, lineId] = id.split('|');
    const car = (state.payload?.cars || []).find(entry => entry.id === carId);
    return { carId, lineId, car, line: car?.l?.find(entry => entry.id === lineId) };
  }
  // When the open car is fully checked, close it and open the next car in the list that still needs checking.
  function advance(car) {
    if (!car || state.view.openCar !== car.id || !carChecked(car)) return;
    const cars = visibleCars(state.payload, state.view);
    const at = cars.findIndex(entry => entry.id === car.id);
    const next = cars.slice(at + 1).find(entry => !carChecked(entry) && !entry.missing) || null;
    state.view.openCar = next ? next.id : '';
    render();
    const node = next && document.querySelector(`[data-st-car="${CSS.escape(next.id)}"]`);
    node?.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
  }
  async function save(name, body, onFail, carId) {
    inflight += 1; saveGen += 1; state.view.errors.delete(carId);
    try {
      const result = await rpc(name, body);
      if (result?.ok !== true) { onFail(); state.view.errors.set(carId, ERRORS[result?.error] || 'Not saved. Try again.'); render(); }
    } catch (_) { onFail(); state.view.errors.set(carId, ERRORS.completion_unavailable); render(); }
    finally { inflight -= 1; settle(); }
  }
  function tick(id, completed) {
    const { carId, lineId, car, line } = findLine(id);
    if (!line) return;
    const before = { done: line.done, by: line.by, at: line.at, x: line.x };
    line.done = completed; line.by = completed ? (root.PDC_AUTH_CONTEXT?.displayName || 'You') : null; line.at = new Date().toISOString();
    if (completed && line.x) { line.x = false; void save('set_pdc_stock_take_x_723', { p_vehicle_id: carId, p_line_identity: lineId, p_x: false }, () => {}, carId); } // r723: done clears the X
    render();
    void save('set_panel_line_completion_565', { p_vehicle_id: carId, p_line_identity: lineId, p_completed: completed },
      () => Object.assign(line, before), carId);
    advance(car);
  }
  function markX(id, on) {
    const { carId, lineId, car, line } = findLine(id);
    if (!line || line.done) return;
    const before = { x: line.x, x_by: line.x_by, x_at: line.x_at };
    line.x = on; line.x_by = on ? (root.PDC_AUTH_CONTEXT?.displayName || 'You') : null; line.x_at = new Date().toISOString();
    render();
    void save('set_pdc_stock_take_x_723', { p_vehicle_id: carId, p_line_identity: lineId, p_x: on }, () => Object.assign(line, before), carId);
    advance(car);
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
    const car = (state.payload?.cars || []).find(entry => entry.id === carId);
    const key = `miss|${carId}`;
    if (!car || state.view.pending.has(key)) return;
    state.view.pending.add(key); state.view.errors.delete(carId);
    car.missing = missing; car.missing_by = missing ? (root.PDC_AUTH_CONTEXT?.displayName || 'You') : null; car.missing_at = new Date().toISOString();
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
      const box = event.target.closest?.('[data-st-tick]');
      if (box) { void tick(box.dataset.stTick, box.checked); return; }
      if (event.target.matches?.('[data-st-open]')) { state.view.openOnly = event.target.checked; render(); }
      if (event.target.matches?.('[data-st-missing-only]')) { state.view.missingOnly = event.target.checked; render(); }
    });
    el.addEventListener('input', event => { if (event.target.matches?.('[data-st-search]')) { state.view.search = event.target.value; render(); } });
    el.addEventListener('click', event => {
      const toggle = event.target.closest?.('[data-st-toggle]');
      if (toggle) { const id = toggle.dataset.stToggle; state.view.openCar = state.view.openCar === id ? '' : id; render(); return; }
      const sorted = event.target.closest?.('[data-st-sorted]');
      if (sorted) { void sortFound(sorted.dataset.stSorted, sorted); return; }
      const xb = event.target.closest?.('[data-st-x]');
      if (xb) { event.preventDefault(); void markX(xb.dataset.stX, xb.getAttribute('aria-pressed') !== 'true'); return; }
      const miss = event.target.closest?.('[data-st-missing]');
      if (miss) { void flagMissing(miss.dataset.stMissing, miss.getAttribute('aria-pressed') !== 'true'); return; }
      const chip = event.target.closest?.('[data-st-station]');
      if (!chip) return;
      const code = chip.dataset.stStation;
      const on = new Set(state.view.stations);
      if (on.has(code)) { if (on.size > 1) on.delete(code); } else on.add(code);
      state.view.stations = STATIONS.map(([c]) => c).filter(c => on.has(c));
      try { root.localStorage.setItem(PICK_KEY, JSON.stringify(state.view.stations)); } catch (_) { /* this device only */ }
      state.payload = null; state.barDirty = true; render(); void load();
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
