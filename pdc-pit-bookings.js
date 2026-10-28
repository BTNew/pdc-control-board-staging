/*
 * r604 (F218): pit bookings. Craig, 28 Oct 2026.
 * - The PIT tile on Vehicle Locations shows every board vehicle with a PIT line ("PIT AND WEIGH",
 *   "PIT INSPECTION", a sublet PO that says PIT). "NO PIT..." lines do not count.
 * - Under the list, a month calendar. Drag a vehicle onto a day to book its pit there, at PMB,
 *   Wangara or Wades. Drag a booked chip to another day to move it.
 * - Vehicle Locations gets a Pit column left of Parts ETA: the date, the place and a day counter.
 *   Ticked Back turns it green with a tick.
 * Reads get_pdc_pit_board_604 (board readers). Writes set_pdc_pit_booking_604 (controllers and
 * administrators). Nothing here touches imports, bookings in the planner or vehicle locations.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.28.r604';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const PLACES = Object.freeze(['PMB', 'Wangara', 'Wades']);
  const DAY_MS = 86400000;
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const LONG_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const isoDate = value => /^\d{4}-\d{2}-\d{2}$/.test(String(value || '')) ? String(value) : '';
  const utc = iso => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10)));
  const toIso = ms => new Date(ms).toISOString().slice(0, 10);
  const stockKey = value => String(value ?? '').trim().toUpperCase();

  /** Whole days from today to the pit date (negative once the date has passed). */
  function daysUntil(pitDate, today) {
    const a = isoDate(pitDate), b = isoDate(today);
    return a && b ? Math.round((utc(a) - utc(b)) / DAY_MS) : null;
  }
  function shortDate(iso) {
    const d = isoDate(iso);
    if (!d) return '';
    const day = new Date(utc(d));
    return `${WEEKDAYS[(day.getUTCDay() + 6) % 7]} ${day.getUTCDate()} ${MONTHS[day.getUTCMonth()]}`;
  }
  /** Counter text: "in 3d", "today", or "+2d" once the date has passed and it is not back yet. */
  function counterText(days) {
    if (days === null) return '';
    if (days > 0) return `in ${days}d`;
    if (days === 0) return 'today';
    return `+${-days}d`;
  }

  /** Index the RPC payload by vehicle id and by stock number (the table's row key is the stock number). */
  function indexBoard(json) {
    const byKey = new Map();
    const vehicles = Array.isArray(json?.vehicles) ? json.vehicles : [];
    vehicles.forEach(entry => {
      if (entry?.vehicle_id) byKey.set(String(entry.vehicle_id), entry);
      const stock = stockKey(entry?.stock_number);
      if (stock) byKey.set(stock, entry);
    });
    return { today: isoDate(json?.today) || toIso(Date.now()), canEdit: json?.can_edit === true, vehicles, byKey };
  }

  /** The Pit cell for a Vehicle Locations row. A dash unless a pit date is booked. */
  function cellHtml(entry, today) {
    const date = isoDate(entry?.pit_date);
    if (!date) {
      const title = entry?.needs_pit ? 'Needs pitting. Not booked yet.' : 'No pit booked';
      return `<span class="vlt-subtle-dash" title="${esc(title)}">—</span>`;
    }
    const place = PLACES.includes(entry.pit_location) ? entry.pit_location : '';
    if (entry.back) {
      const when = entry.back_at ? ` Ticked back ${String(entry.back_at).slice(0, 10)}.` : '';
      return `<span class="pdc-pit-chip is-back" data-pdc-pit-cell title="${esc(`Pitted ${shortDate(date)} at ${place}.${when}`)}"><span aria-hidden="true">✓</span> ${esc(shortDate(date))}${place ? ` · ${esc(place)}` : ''}</span>`;
    }
    const days = daysUntil(date, today);
    const tone = days === null ? '' : days < 0 ? ' is-over' : days === 0 ? ' is-today' : days <= 2 ? ' is-soon' : '';
    const counter = counterText(days);
    const title = days === null ? '' : days > 0 ? `Pit booked in ${days} day${days === 1 ? '' : 's'}` : days === 0 ? 'Pit booked today' : `Pit date was ${-days} day${days === -1 ? '' : 's'} ago. Not ticked back yet.`;
    return `<span class="pdc-pit-chip${tone}" data-pdc-pit-cell title="${esc(`${title}. ${place}.`)}">${esc(shortDate(date))}${place ? ` · ${esc(place)}` : ''}${counter ? ` <b class="pdc-pit-count">${esc(counter)}</b>` : ''}</span>`;
  }

  /** Monday-first weeks covering the month of `monthIso` (YYYY-MM-01). */
  function monthGrid(monthIso) {
    const first = utc(isoDate(monthIso) || `${monthIso}-01`);
    const month = new Date(first).getUTCMonth();
    const last = Date.UTC(new Date(first).getUTCFullYear(), month + 1, 0);
    const start = first - ((new Date(first).getUTCDay() + 6) % 7) * DAY_MS;
    const end = last + (6 - ((new Date(last).getUTCDay() + 6) % 7)) * DAY_MS;
    const days = [];
    for (let ms = start; ms <= end; ms += DAY_MS) days.push({ iso: toIso(ms), inMonth: new Date(ms).getUTCMonth() === month });
    return days;
  }
  const monthStart = iso => `${(isoDate(iso) || toIso(Date.now())).slice(0, 7)}-01`;
  function shiftMonth(monthIso, delta) {
    const y = Number(monthIso.slice(0, 4)), m = Number(monthIso.slice(5, 7)) - 1 + delta;
    return toIso(Date.UTC(y + Math.floor(m / 12), ((m % 12) + 12) % 12, 1));
  }

  const FILTERS = Object.freeze({ open: 'Not booked', booked: 'Booked', back: 'Back', all: 'All' });
  function filterVehicles(vehicles, filter) {
    return vehicles.filter(v => {
      const booked = Boolean(isoDate(v.pit_date));
      if (filter === 'open') return v.needs_pit && !booked;
      if (filter === 'booked') return booked && !v.back;
      if (filter === 'back') return booked && v.back;
      return true;
    });
  }

  /** The panel above the table on the PIT tile: the list, then the calendar. */
  function panelHtml(board, { filter = 'open', month = '', place = 'PMB', message = '' } = {}) {
    const today = board.today;
    const canEdit = board.canEdit;
    const shownMonth = monthStart(month || today);
    const counts = Object.fromEntries(Object.keys(FILTERS).map(key => [key, filterVehicles(board.vehicles, key).length]));
    const rows = filterVehicles(board.vehicles, filter);
    const listRows = rows.map(v => {
      const booked = Boolean(isoDate(v.pit_date));
      const id = esc(v.vehicle_id);
      const drag = canEdit ? ` draggable="true" data-pit-drag="${id}"` : '';
      const placeSelect = canEdit && booked
        ? `<select data-pit-place-for="${id}" aria-label="Pit place">${PLACES.map(p => `<option${p === v.pit_location ? ' selected' : ''}>${p}</option>`).join('')}</select>`
        : esc(v.pit_location || '');
      const backBox = booked
        ? `<label class="pdc-pit-back"><input type="checkbox" data-pit-back="${id}"${v.back ? ' checked' : ''}${canEdit ? '' : ' disabled'}> Back</label>`
        : '';
      const clear = canEdit && booked ? `<button type="button" class="small-button" data-pit-clear="${id}" title="Remove this pit booking">Clear</button>` : '';
      return `<tr class="pdc-pit-row${v.back ? ' is-back' : ''}"${drag}>
        <td class="pdc-pit-grip">${canEdit ? '<span aria-hidden="true">⠿</span>' : ''}</td>
        <td>${esc(v.key_number || '')}</td><td><strong>${esc(v.stock_number || '')}</strong></td><td>${esc(v.job_card_number || '')}</td>
        <td>${esc(v.vehicle || '')}</td><td>${esc(v.location || '')}</td>
        <td class="pdc-pit-lines" title="${esc((v.pit_lines || []).join('\n'))}">${esc((v.pit_lines || [])[0] || '')}${(v.pit_lines || []).length > 1 ? ` <small>+${v.pit_lines.length - 1}</small>` : ''}</td>
        <td>${booked ? cellHtml(v, today) : '<span class="pdc-pit-chip is-needed">Not booked</span>'}</td>
        <td>${booked ? placeSelect : ''}</td><td>${backBox}</td><td>${clear}</td></tr>`;
    }).join('') || `<tr><td colspan="11" class="pdc-pit-empty">No vehicles under ${esc(FILTERS[filter] || 'this filter')}.</td></tr>`;

    const byDay = new Map();
    board.vehicles.forEach(v => { const d = isoDate(v.pit_date); if (d) byDay.set(d, [...(byDay.get(d) || []), v]); });
    const cells = monthGrid(shownMonth).map(day => {
      const chips = (byDay.get(day.iso) || []).map(v => `<span class="pdc-pit-cal-chip pdc-pit-at-${esc(String(v.pit_location || '').toLowerCase())}${v.back ? ' is-back' : ''}"${canEdit ? ` draggable="true" data-pit-drag="${esc(v.vehicle_id)}"` : ''} title="${esc(`${v.stock_number} · ${v.vehicle || ''} · ${v.pit_location}${v.back ? ' · back' : ''}`)}">${v.back ? '✓ ' : ''}${esc(v.key_number ? `K${v.key_number}` : v.stock_number)} · ${esc(v.pit_location || '')}</span>`).join('');
      const cls = ['pdc-pit-day', day.inMonth ? '' : 'is-out', day.iso === today ? 'is-today' : '', day.iso < today ? 'is-past' : ''].filter(Boolean).join(' ');
      return `<div class="${cls}"${canEdit ? ` data-pit-day="${day.iso}"` : ''}><span class="pdc-pit-daynum">${Number(day.iso.slice(8, 10))}</span>${chips}</div>`;
    }).join('');

    const placePick = canEdit
      ? `<div class="pdc-pit-place" role="radiogroup" aria-label="Place for new pit bookings"><span>Drop books at</span>${PLACES.map(p => `<button type="button" role="radio" aria-checked="${p === place}" class="${p === place ? 'active' : ''}" data-pit-place="${p}">${p}</button>`).join('')}</div>`
      : '<p class="pdc-pit-readonly">View only. Controllers and administrators book pits.</p>';

    return `<section class="pdc-pit-panel" data-pdc-pit-panel aria-label="Pit bookings">
      <div class="pdc-pit-head"><h2>Vehicles that need pitting</h2>
        <div class="pdc-pit-filters" role="toolbar">${Object.entries(FILTERS).map(([key, label]) => `<button type="button" class="${key === filter ? 'active' : ''}" data-pit-filter="${key}">${label} <b>${counts[key]}</b></button>`).join('')}</div>
        ${message ? `<p class="pdc-pit-msg" role="status">${esc(message)}</p>` : ''}</div>
      <div class="pdc-pit-list-wrap"><table class="pdc-pit-list"><thead><tr><th></th><th>Key</th><th>Stock</th><th>Job Card</th><th>Vehicle</th><th>Location</th><th>Pit line</th><th>Pit</th><th>Place</th><th></th><th></th></tr></thead><tbody>${listRows}</tbody></table></div>
      <div class="pdc-pit-cal-head"><button type="button" class="small-button" data-pit-month="-1" aria-label="Previous month">‹</button><h3>${LONG_MONTHS[Number(shownMonth.slice(5, 7)) - 1]} ${shownMonth.slice(0, 4)}</h3><button type="button" class="small-button" data-pit-month="1" aria-label="Next month">›</button><button type="button" class="small-button" data-pit-month="0">Today</button>${placePick}</div>
      <div class="pdc-pit-cal">${WEEKDAYS.map(d => `<div class="pdc-pit-wd">${d}</div>`).join('')}${cells}</div>
      ${canEdit ? '<p class="pdc-pit-hint">Drag a vehicle from the list onto a day. Drag a booked chip to move it.</p>' : ''}
    </section>`;
  }

  const CSS = `
.vlt-table col.c-pit { width: var(--vlt-w-pit, 104px); }
.vlt-table td.c-pit { white-space: normal; }
.pdc-pit-chip { display: inline-block; font-size: 10.5px; line-height: 1.15; padding: 1px 5px; border-radius: 4px; background: #eef2f7; color: #1e293b; white-space: nowrap; }
.pdc-pit-chip .pdc-pit-count { font-weight: 700; margin-left: 2px; }
.pdc-pit-chip.is-soon { background: #fef3c7; color: #78350f; }
.pdc-pit-chip.is-today { background: #dbeafe; color: #1e3a8a; }
.pdc-pit-chip.is-over { background: #fee2e2; color: #991b1b; }
.pdc-pit-chip.is-back { background: #dcfce7; color: #14532d; font-weight: 600; }
.pdc-pit-chip.is-needed { background: transparent; color: #92400e; border: 1px dashed #f59e0b; }
.pdc-pit-panel { margin: 10px 0 14px; padding: 12px; border: 1px solid #e2e8f0; border-radius: 8px; background: #fff; }
.pdc-pit-head { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-bottom: 8px; }
.pdc-pit-head h2 { margin: 0; font-size: 15px; }
.pdc-pit-filters, .pdc-pit-place { display: inline-flex; gap: 4px; align-items: center; flex-wrap: wrap; }
.pdc-pit-filters button, .pdc-pit-place button { border: 1px solid #cbd5e1; background: #fff; border-radius: 999px; padding: 2px 10px; font-size: 12px; cursor: pointer; }
.pdc-pit-filters button.active, .pdc-pit-place button.active { background: #1e293b; border-color: #1e293b; color: #fff; }
.pdc-pit-place span { font-size: 12px; color: #475569; margin-right: 2px; }
.pdc-pit-msg { margin: 0; font-size: 12px; color: #9a3412; }
.pdc-pit-list-wrap { max-height: 300px; overflow: auto; border: 1px solid #e2e8f0; border-radius: 6px; }
.pdc-pit-list { width: 100%; border-collapse: collapse; font-size: 12px; }
.pdc-pit-list th { position: sticky; top: 0; background: #f8fafc; text-align: left; font-weight: 600; padding: 4px 6px; border-bottom: 1px solid #e2e8f0; }
.pdc-pit-list td { padding: 3px 6px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
.pdc-pit-row[draggable="true"] { cursor: grab; }
.pdc-pit-row.is-back td { color: #64748b; }
.pdc-pit-grip { color: #94a3b8; width: 14px; }
.pdc-pit-lines { max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pdc-pit-empty { text-align: center; color: #64748b; padding: 10px; }
.pdc-pit-back { display: inline-flex; gap: 3px; align-items: center; }
.pdc-pit-cal-head { display: flex; align-items: center; gap: 6px; margin: 12px 0 6px; flex-wrap: wrap; }
.pdc-pit-cal-head h3 { margin: 0 4px; font-size: 14px; min-width: 120px; text-align: center; }
.pdc-pit-cal-head .pdc-pit-place { margin-left: auto; }
.pdc-pit-cal { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 3px; }
.pdc-pit-wd { font-size: 11px; font-weight: 600; color: #475569; text-align: center; }
.pdc-pit-day { min-height: 64px; border: 1px solid #e2e8f0; border-radius: 5px; padding: 2px 3px; background: #fff; display: flex; flex-direction: column; gap: 2px; overflow: hidden; }
.pdc-pit-day.is-out { background: #f8fafc; opacity: .6; }
.pdc-pit-day.is-past { background: #f8fafc; }
.pdc-pit-day.is-today { border-color: #2563eb; box-shadow: inset 0 0 0 1px #2563eb; }
.pdc-pit-day.is-drop { background: #eff6ff; border-color: #2563eb; }
.pdc-pit-daynum { font-size: 11px; color: #64748b; }
.pdc-pit-cal-chip { font-size: 10.5px; padding: 1px 4px; border-radius: 3px; background: #e2e8f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pdc-pit-cal-chip[draggable="true"] { cursor: grab; }
.pdc-pit-cal-chip.pdc-pit-at-pmb { background: #e0e7ff; }
.pdc-pit-cal-chip.pdc-pit-at-wangara { background: #fde68a; }
.pdc-pit-cal-chip.pdc-pit-at-wades { background: #bae6fd; }
.pdc-pit-cal-chip.is-back { background: #dcfce7; color: #14532d; }
.pdc-pit-hint, .pdc-pit-readonly { font-size: 11px; color: #64748b; margin: 6px 0 0; }
@media (max-width: 720px) { .pdc-pit-day { min-height: 46px; } .pdc-pit-cal-chip { font-size: 9.5px; } }
`;

  const api = { VERSION, PLACES, daysUntil, counterText, shortDate, indexBoard, cellHtml, monthGrid, shiftMonth, filterVehicles, panelHtml, CSS };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_PIT_BOOKINGS) return;

  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  const token = () => window.__pdcCachedAccessToken;
  async function rpc(name, body) {
    if (!token() || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    const text = await response.text();
    if (!response.ok) { let m = text; try { m = JSON.parse(text).message || text; } catch (_) { /* raw */ } throw new Error(String(m || response.status)); }
    return JSON.parse(text || 'null');
  }

  let board = indexBoard(null);
  let loaded = false;
  let loading = null;
  const ui = { filter: 'open', month: '', place: 'PMB', message: '', host: null };

  function rerender() { try { if (typeof refreshAllViews === 'function') refreshAllViews(); } catch (_) { /* next render */ } }
  function load() {
    if (loading || !token()) return loading;
    loading = rpc('get_pdc_pit_board_604', {})
      .then(json => { if (json) { board = indexBoard(json); loaded = true; rerender(); } })
      .catch(() => { /* the column shows dashes; the next load retries */ })
      .finally(() => { loading = null; });
    return loading;
  }
  function paintPanel() {
    const panel = ui.host?.querySelector('[data-pdc-pit-panel]');
    if (!panel) return;
    panel.outerHTML = panelHtml(board, ui);
    bindPanel(ui.host.querySelector('[data-pdc-pit-panel]'));
  }
  async function save(vehicleId, changes) {
    const entry = board.byKey.get(vehicleId);
    if (!entry) return;
    const next = { date: entry.pit_date || null, place: entry.pit_location || null, back: Boolean(entry.back), ...changes };
    try {
      const result = await rpc('set_pdc_pit_booking_604', { p_vehicle_id: vehicleId, p_pit_date: next.date, p_pit_location: next.date ? next.place : null, p_back: next.date ? next.back : false, p_expected_version: Number(entry.booking_version || 0) });
      ui.message = result?.ok ? '' : (result?.message || 'The pit booking was not saved.');
    } catch (error) {
      ui.message = `The pit booking was not saved. ${error.message || ''}`.trim();
    }
    await load();
    paintPanel();
  }

  function bindPanel(panel) {
    if (!panel) return;
    panel.querySelectorAll('[data-pit-filter]').forEach(b => b.addEventListener('click', () => { ui.filter = b.dataset.pitFilter; paintPanel(); }));
    panel.querySelectorAll('[data-pit-month]').forEach(b => b.addEventListener('click', () => {
      const delta = Number(b.dataset.pitMonth);
      ui.month = delta ? shiftMonth(monthStart(ui.month || board.today), delta) : '';
      paintPanel();
    }));
    panel.querySelectorAll('[data-pit-place]').forEach(b => b.addEventListener('click', () => { ui.place = b.dataset.pitPlace; paintPanel(); }));
    panel.querySelectorAll('[data-pit-place-for]').forEach(s => s.addEventListener('change', () => save(s.dataset.pitPlaceFor, { place: s.value })));
    panel.querySelectorAll('[data-pit-back]').forEach(c => c.addEventListener('change', () => save(c.dataset.pitBack, { back: c.checked })));
    panel.querySelectorAll('[data-pit-clear]').forEach(b => b.addEventListener('click', () => save(b.dataset.pitClear, { date: null, place: null, back: false })));
    panel.querySelectorAll('[data-pit-drag]').forEach(el => el.addEventListener('dragstart', event => {
      event.dataTransfer.setData('application/x-pdc-pit-vehicle', el.dataset.pitDrag);
      event.dataTransfer.setData('text/plain', el.dataset.pitDrag);
      event.dataTransfer.effectAllowed = 'move';
    }));
    panel.querySelectorAll('[data-pit-day]').forEach(day => {
      day.addEventListener('dragover', event => { if (event.dataTransfer.types.includes('application/x-pdc-pit-vehicle')) { event.preventDefault(); day.classList.add('is-drop'); } });
      day.addEventListener('dragleave', () => day.classList.remove('is-drop'));
      day.addEventListener('drop', event => {
        event.preventDefault();
        day.classList.remove('is-drop');
        const vid = event.dataTransfer.getData('application/x-pdc-pit-vehicle');
        const entry = board.byKey.get(vid);
        if (!entry) return;
        // A booked vehicle keeps its place when moved; a new booking takes the place picked above.
        save(vid, { date: day.dataset.pitDay, place: entry.pit_location || ui.place, back: false });
      });
    });
  }

  /** Called by the Vehicle Locations table after each render. */
  function afterRender(host, { bucket } = {}) {
    if (!host) return;
    host.querySelector('[data-pdc-pit-panel]')?.remove();
    if (bucket !== 'pit') return;
    ui.host = host;
    const anchor = host.querySelector('.vlt-panel');
    if (!anchor) return;
    anchor.insertAdjacentHTML('beforebegin', loaded ? panelHtml(board, ui) : '<section class="pdc-pit-panel" data-pdc-pit-panel><p class="pdc-pit-hint">Loading pit bookings…</p></section>');
    if (loaded) bindPanel(host.querySelector('[data-pdc-pit-panel]'));
    else load();
  }

  const style = document.createElement('style');
  style.dataset.pdcPitBookings = VERSION;
  style.textContent = CSS;
  document.head.appendChild(style);

  window.PDC_PIT_BOOKINGS = Object.freeze({
    ...api,
    cell: rowKey => cellHtml(board.byKey.get(String(rowKey)) || board.byKey.get(stockKey(rowKey)), board.today),
    afterRender,
    load,
    get board() { return board; },
  });
  window.addEventListener('pdc-auth-ready', () => load());
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setInterval(load, 5 * 60 * 1000);
  load();
}(typeof window !== 'undefined' ? window : globalThis));
