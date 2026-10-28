/*
 * r604 (F218): pit bookings. Craig, 28 Oct 2026.
 * - The PIT tile on Vehicle Locations shows every board vehicle with a PIT line ("PIT AND WEIGH",
 *   "PIT INSPECTION", a sublet PO that says PIT). "NO PIT..." lines do not count.
 * - Under the list, a month calendar. Drag a vehicle onto a day to book its pit there, at PMB,
 *   Wangara or Wades. Drag a booked chip to another day to move it.
 * - Vehicle Locations gets a Pit column left of Parts ETA: the date, the place and a day counter.
 *   Ticked Back turns it green with a tick.
 * r630 (F245): dropping on the calendar opens one box for the time (07:00 to 17:00; r632: quarter hours; mouse wheel or arrow
 *   keys) and the place, then saves. One calendar for PMB, Wangara and Wades. Writes go to set_pdc_pit_booking_630.
 * Reads get_pdc_pit_board_604 (board readers). Writes set_pdc_pit_booking_604 (controllers and
 * administrators). Nothing here touches imports, bookings in the planner or vehicle locations.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.28.r632';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const PLACES = Object.freeze(['PMB', 'Wangara', 'Wades', 'Welshpool']); // r632 (F247): Welshpool added
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

  // r622 (F237): dd/mm, the same date style as the Parts ETA cell.
  const ddmm = iso => { const d = isoDate(iso); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}` : ''; };

  // r630 (F245) pit times; r632 (F247): every quarter hour, 07:00 to 17:00.
  const TIME_SLOTS = Object.freeze(Array.from({ length: 41 }, (_, i) => `${String(7 + Math.floor(i / 4)).padStart(2, '0')}:${String((i % 4) * 15).padStart(2, '0')}`));
  const hhmm = value => { const m = /^(\d{2}):(\d{2})/.exec(String(value || '')); return m ? `${m[1]}:${m[2]}` : ''; };
  /** 07:30 -> 7:30am, 13:00 -> 1:00pm. */
  function timeLabel(value) {
    const t = hhmm(value);
    if (!t) return '';
    const h = Number(t.slice(0, 2));
    return `${h % 12 || 12}:${t.slice(3)}${h < 12 ? 'am' : 'pm'}`;
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
      return `<span class="pdc-pit-chip is-back" data-pdc-pit-cell title="${esc(`Pitted ${shortDate(date)}${hhmm(entry.pit_time) ? ` ${timeLabel(entry.pit_time)}` : ''}${place ? ` at ${place}` : ''}.${when}`)}"><span aria-hidden="true">✓</span> ${esc(ddmm(date))}</span>`;
    }
    const days = daysUntil(date, today);
    const tone = days === null ? '' : days < 0 ? ' is-over' : days === 0 ? ' is-today' : days <= 2 ? ' is-soon' : '';
    // r622 (F237): the same words as the Parts ETA cell ("14/12 · 9 days"); the place moves to the hover.
    const counter = days === null ? '' : days > 0 ? `${days} day${days === 1 ? '' : 's'}` : days === 0 ? 'today' : `${-days} day${days === -1 ? '' : 's'} overdue`;
    const title = days === null ? '' : days > 0 ? `Pit booked in ${days} day${days === 1 ? '' : 's'}` : days === 0 ? 'Pit booked today' : `Pit date was ${-days} day${days === -1 ? '' : 's'} ago. Not ticked back yet.`;
    return `<span class="pdc-pit-chip${tone}" data-pdc-pit-cell title="${esc(`${title}.${hhmm(entry.pit_time) ? ` ${timeLabel(entry.pit_time)}.` : ''}${place ? ` ${place}.` : ''}`)}">${esc(ddmm(date))}${counter ? ` · ${esc(counter)}` : ''}</span>`;
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

  const FILTERS = Object.freeze({ open: 'Not booked', booked: 'Booked', back: 'Done', all: 'All' });
  // r611 (F225): only vehicles with a key number are listed (no key means not physically here yet).
  const hasKey = v => String(v?.key_number ?? '').trim() !== '' && String(v.key_number).trim() !== '0';
  // r618 (F233): the Vehicle Locations search boxes also search the pit list. Key number is exact (leading zeros and
  // spaces ignored, as on the table); the other box matches stock, job card, customer, vehicle, location or pit line.
  const keyToken = value => { const c = String(value ?? '').replace(/\s+/g, '').toLowerCase(); return c.replace(/^0+/, '') || (c ? '0' : ''); };
  function searchActive(search) {
    return Boolean(search) && (keyToken(search.key).length >= 1 || String(search.text || '').trim().length >= 2);
  }
  function searchMatches(v, search) {
    if (!searchActive(search)) return true;
    const key = keyToken(search.key);
    if (key && keyToken(v?.key_number) !== key) return false;
    const text = String(search.text || '').trim().toLowerCase();
    if (text.length >= 2) {
      const hay = [v.key_number, v.stock_number, v.job_card_number, v.customer, v.customer_name, v.vehicle, v.location, ...(v.pit_lines || [])]
        .filter(x => x !== null && x !== undefined).join(' ').toLowerCase();
      if (!hay.includes(text)) return false;
    }
    return true;
  }
  function filterVehicles(vehicles, filter, search = null) {
    return vehicles.filter(v => {
      if (!hasKey(v) || !searchMatches(v, search)) return false;
      const booked = Boolean(isoDate(v.pit_date));
      if (filter === 'open') return v.needs_pit && !booked;
      if (filter === 'booked') return booked && !v.back;
      if (filter === 'back') return booked && v.back;
      return true;
    });
  }

  /** The panel above the table on the PIT tile: the list, then the calendar. */
  function panelHtml(board, { filter = 'open', month = '', message = '', search = null } = {}) {
    const today = board.today;
    const canEdit = board.canEdit;
    const shownMonth = monthStart(month || today);
    const searching = searchActive(search);
    const counts = Object.fromEntries(Object.keys(FILTERS).map(key => [key, filterVehicles(board.vehicles, key, search).length]));
    const rows = filterVehicles(board.vehicles, filter, search);
    const listRows = rows.map(v => {
      const booked = Boolean(isoDate(v.pit_date));
      const id = esc(v.vehicle_id);
      const drag = canEdit ? ` draggable="true" data-pit-drag="${id}"` : '';
      const placeSelect = canEdit && booked
        ? `<select data-pit-place-for="${id}" aria-label="Pit place">${PLACES.map(p => `<option${p === v.pit_location ? ' selected' : ''}>${p}</option>`).join('')}</select>`
        : esc(v.pit_location || '');
      // r611 (F225): every row has a Done tick. r630: on an unbooked vehicle it asks the time and place, books today and marks it done.
      const backBox = `<label class="pdc-pit-back" title="${booked ? 'Pitted and back' : 'Pitted already: books today and marks it done'}"><input type="checkbox" data-pit-back="${id}"${v.back ? ' checked' : ''}${canEdit ? '' : ' disabled'}> Done</label>`;
      const clear = canEdit && booked ? `<button type="button" class="small-button" data-pit-clear="${id}" title="Remove this pit booking">Clear</button>` : '';
      return `<tr class="pdc-pit-row${v.back ? ' is-back' : ''}"${drag}>
        <td class="pdc-pit-grip">${canEdit ? '<span aria-hidden="true">⠿</span>' : ''}</td>
        <td>${esc(v.key_number || '')}</td><td><strong>${esc(v.stock_number || '')}</strong></td><td>${esc(v.job_card_number || '')}</td>
        <td>${esc(v.vehicle || '')}</td><td>${esc(v.location || '')}</td>
        <td class="pdc-pit-lines" title="${esc((v.pit_lines || []).join('\n'))}">${esc((v.pit_lines || [])[0] || '')}${(v.pit_lines || []).length > 1 ? ` <small>+${v.pit_lines.length - 1}</small>` : ''}</td>
        <td>${booked ? cellHtml(v, today) : '<span class="pdc-pit-chip is-needed">Not booked</span>'}</td>
        <td>${booked ? placeSelect : ''}</td><td>${backBox}</td><td>${clear}</td></tr>`;
    }).join('') || `<tr><td colspan="11" class="pdc-pit-empty">${searching ? `No pit vehicle matches your search under ${esc(FILTERS[filter] || 'this filter')}${counts.all ? `. Try ${esc(FILTERS.all)}` : ''}.` : `No vehicles under ${esc(FILTERS[filter] || 'this filter')}.`}</td></tr>`;

    const byDay = new Map();
    board.vehicles.filter(v => hasKey(v) && searchMatches(v, search)).forEach(v => { const d = isoDate(v.pit_date); if (d) byDay.set(d, [...(byDay.get(d) || []), v]); });
    const cells = monthGrid(shownMonth).map(day => {
      // r630 (F245): one calendar for all three places, in time order. Click a chip to change its time or place.
      const dayList = (byDay.get(day.iso) || []).slice().sort((a, b) => (hhmm(a.pit_time) || '99').localeCompare(hhmm(b.pit_time) || '99'));
      const chips = dayList.map(v => `<span class="pdc-pit-cal-chip pdc-pit-at-${esc(String(v.pit_location || '').toLowerCase())}${v.back ? ' is-back' : ''}"${canEdit ? ` draggable="true" data-pit-drag="${esc(v.vehicle_id)}" data-pit-edit="${esc(v.vehicle_id)}" role="button" tabindex="0"` : ''} title="${esc(`${v.stock_number} · ${v.vehicle || ''} · ${hhmm(v.pit_time) ? `${timeLabel(v.pit_time)} · ` : ''}${v.pit_location}${v.back ? ' · back' : ''}${canEdit ? ' · click to change' : ''}`)}">${v.back ? '✓ ' : ''}${hhmm(v.pit_time) ? `<b>${esc(hhmm(v.pit_time))}</b> ` : ''}${esc(v.key_number ? `K${v.key_number}` : v.stock_number)} · ${esc(v.pit_location || '')}</span>`).join('');
      const cls = ['pdc-pit-day', day.inMonth ? '' : 'is-out', day.iso === today ? 'is-today' : '', day.iso < today ? 'is-past' : ''].filter(Boolean).join(' ');
      return `<div class="${cls}"${canEdit ? ` data-pit-day="${day.iso}"` : ''}><span class="pdc-pit-daynum">${Number(day.iso.slice(8, 10))}</span>${chips}</div>`;
    }).join('');

    // r630 (F245): no "Drop books at" picker; the box that opens on drop asks the time and place.
    const placePick = canEdit
      ? `<div class="pdc-pit-legend" aria-label="Places">${PLACES.map(p => `<span class="pdc-pit-cal-chip pdc-pit-at-${p.toLowerCase()}">${p}</span>`).join('')}</div>`
      : '<p class="pdc-pit-readonly">View only. Controllers and administrators book pits.</p>';

    return `<section class="pdc-pit-panel" data-pdc-pit-panel aria-label="Pit bookings">
      <div class="pdc-pit-head"><h2>Vehicles that need pitting</h2>
        <div class="pdc-pit-filters" role="toolbar">${Object.entries(FILTERS).map(([key, label]) => `<button type="button" class="${key === filter ? 'active' : ''}" data-pit-filter="${key}">${label} <b>${counts[key]}</b></button>`).join('')}</div>
        ${searching ? `<p class="pdc-pit-search" role="status">Search: ${esc([search.key && `key ${String(search.key).trim()}`, String(search.text || '').trim()].filter(Boolean).join(' · '))} · ${counts.all} match${counts.all === 1 ? '' : 'es'}</p>` : ''}
        ${message ? `<p class="pdc-pit-msg" role="status">${esc(message)}</p>` : ''}</div>
      <div class="pdc-pit-list-wrap"><table class="pdc-pit-list"><thead><tr><th></th><th>Key</th><th>Stock</th><th>Job Card</th><th>Vehicle</th><th>Location</th><th>Pit line</th><th>Pit</th><th>Place</th><th>Done</th><th></th></tr></thead><tbody>${listRows}</tbody></table></div>
      <div class="pdc-pit-cal-head"><button type="button" class="small-button" data-pit-month="-1" aria-label="Previous month">‹</button><h3>${LONG_MONTHS[Number(shownMonth.slice(5, 7)) - 1]} ${shownMonth.slice(0, 4)}</h3><button type="button" class="small-button" data-pit-month="1" aria-label="Next month">›</button><button type="button" class="small-button" data-pit-month="0">Today</button>${placePick}</div>
      <div class="pdc-pit-cal">${WEEKDAYS.map(d => `<div class="pdc-pit-wd">${d}</div>`).join('')}${cells}</div>
      ${canEdit ? '<p class="pdc-pit-hint">Drag a vehicle from the list onto a day, then pick the time and place. Drag a booked chip to move it; click it to change the time or place.</p>' : ''}
    </section>`;
  }

  /** r630 (F245): the box that opens on drop. Pick a time and a place, then Save. */
  function dialogHtml({ entry = {}, date = '', time = '', place = '', back = false, booked = false } = {}) {
    const pickTime = TIME_SLOTS.includes(hhmm(time)) ? hhmm(time) : TIME_SLOTS[0];
    const pickPlace = PLACES.includes(place) ? place : PLACES[0];
    const who = [entry.key_number ? `Key ${entry.key_number}` : '', entry.stock_number, entry.vehicle].filter(Boolean).join(' · ');
    return `<div class="pdc-pit-dlg-back" data-pit-dlg-back><div class="pdc-pit-dlg" role="dialog" aria-modal="true" aria-label="Book pit">
      <h3>${back ? 'Pitted' : booked ? 'Pit booking' : 'Book pit'} · ${esc(shortDate(date))}</h3>
      <p class="pdc-pit-dlg-sub">${esc(who)}</p>
      <label class="pdc-pit-dlg-label" id="pdc-pit-time-label">Time</label>
      <div class="pdc-pit-times" role="listbox" tabindex="0" aria-labelledby="pdc-pit-time-label" data-pit-times>${TIME_SLOTS.map(t => `<button type="button" role="option" data-pit-time="${t}" aria-selected="${t === pickTime}">${timeLabel(t)}</button>`).join('')}</div>
      <label class="pdc-pit-dlg-label">Place</label>
      <div class="pdc-pit-places" role="radiogroup" aria-label="Place">${PLACES.map((p, i) => `<button type="button" role="radio" data-pit-dlg-place="${p}" aria-checked="${p === pickPlace}" title="Key ${i + 1}">${p}</button>`).join('')}</div>
      <div class="pdc-pit-dlg-actions">${booked ? '<button type="button" class="pdc-pit-dlg-remove" data-pit-dlg-remove>Remove</button>' : ''}<button type="button" data-pit-dlg-cancel>Cancel</button><button type="button" class="pdc-pit-dlg-save" data-pit-dlg-save>Save</button></div>
      <p class="pdc-pit-dlg-keys">Mouse wheel or ↑ ↓ for the time · 1 2 3 4 for the place · Enter saves · Esc cancels</p>
    </div></div>`;
  }

  const CSS = `
.vlt-table col.c-pit { width: var(--vlt-w-pit, 104px); }
.vlt-table td.c-pit { white-space: normal; }
.pdc-pit-chip { display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; vertical-align: middle; font-size: 10.5px; line-height: 1.12; padding: 1px 5px; border-radius: 4px; background: #e0f2fe; color: #075985; white-space: nowrap; }
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
.pdc-pit-search { margin: 0; font-size: 12px; font-weight: 600; color: #1d4ed8; }
.pdc-pit-legend { margin-left: auto; display: inline-flex; gap: 4px; }
.pdc-pit-cal-chip[data-pit-edit] { cursor: pointer; }
.pdc-pit-dlg-back { position: fixed; inset: 0; background: rgba(15, 23, 42, .35); z-index: 10000; display: flex; align-items: center; justify-content: center; padding: 16px; }
.pdc-pit-dlg { background: #fff; border-radius: 10px; box-shadow: 0 12px 40px rgba(15, 23, 42, .3); width: min(360px, 100%); padding: 14px 16px; font-size: 13px; color: #0f172a; }
.pdc-pit-dlg h3 { margin: 0 0 2px; font-size: 16px; }
.pdc-pit-dlg .pdc-pit-dlg-sub { margin: 0 0 10px; color: #475569; font-size: 12px; }
.pdc-pit-dlg label.pdc-pit-dlg-label { display: block; font-weight: 600; font-size: 12px; margin: 8px 0 4px; color: #334155; }
.pdc-pit-times { height: 176px; overflow-y: auto; border: 1px solid #cbd5e1; border-radius: 6px; padding: 3px; outline: none; scroll-snap-type: y proximity; }
.pdc-pit-times:focus { border-color: #2563eb; box-shadow: 0 0 0 2px #bfdbfe; }
.pdc-pit-times button { display: block; width: 100%; text-align: left; border: 0; background: none; padding: 5px 10px; border-radius: 4px; font-size: 14px; cursor: pointer; scroll-snap-align: center; }
.pdc-pit-times button:hover { background: #f1f5f9; }
.pdc-pit-times button[aria-selected="true"] { background: #1e293b; color: #fff; font-weight: 700; }
.pdc-pit-places { display: flex; gap: 6px; }
.pdc-pit-places button { flex: 1; min-width: 0; border: 1px solid #cbd5e1; background: #fff; border-radius: 6px; padding: 7px 4px; font-size: 13px; cursor: pointer; }
.pdc-pit-places button[aria-checked="true"] { background: #1e293b; border-color: #1e293b; color: #fff; font-weight: 700; }
.pdc-pit-dlg-actions { display: flex; gap: 6px; margin-top: 12px; align-items: center; }
.pdc-pit-dlg-actions .pdc-pit-dlg-save { margin-left: auto; background: #2563eb; color: #fff; border: 0; border-radius: 6px; padding: 7px 16px; font-weight: 700; cursor: pointer; }
.pdc-pit-dlg-actions button { border: 1px solid #cbd5e1; background: #fff; border-radius: 6px; padding: 6px 10px; cursor: pointer; }
.pdc-pit-dlg-actions .pdc-pit-dlg-remove { color: #b91c1c; border-color: #fecaca; }
.pdc-pit-dlg-keys { margin: 8px 0 0; font-size: 11px; color: #64748b; }
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
.pdc-pit-cal-chip.pdc-pit-at-welshpool { background: #fbcfe8; }
.pdc-pit-cal-chip.is-back { background: #dcfce7; color: #14532d; }
.pdc-pit-hint, .pdc-pit-readonly { font-size: 11px; color: #64748b; margin: 6px 0 0; }
@media (max-width: 720px) { .pdc-pit-day { min-height: 46px; } .pdc-pit-cal-chip { font-size: 9.5px; } }
`;

  const api = { VERSION, PLACES, TIME_SLOTS, timeLabel, dialogHtml, searchActive, searchMatches, daysUntil, counterText, shortDate, indexBoard, cellHtml, monthGrid, shiftMonth, filterVehicles, panelHtml, CSS };
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
  const ui = { filter: 'open', month: '', lastPlace: 'PMB', lastTime: '07:00', message: '', search: null, host: null };

  function rerender() { try { if (typeof refreshAllViews === 'function') refreshAllViews(); } catch (_) { /* next render */ } }
  function load() {
    if (String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'fitter') return; // r616 (F231): Fitters bay only
    // r612: fitter logins may only call the Fitters bay; they never see Vehicle Locations, so do not ask.
    if (loading || !token() || window.PDC_AUTH_CONTEXT?.role === 'fitter') return loading;
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
    const next = { date: entry.pit_date || null, time: hhmm(entry.pit_time) || null, place: entry.pit_location || null, back: Boolean(entry.back), ...changes };
    try {
      // r630 (F245): the writer that also keeps the time.
      const result = await rpc('set_pdc_pit_booking_630', { p_vehicle_id: vehicleId, p_pit_date: next.date, p_pit_time: next.date ? (next.time || null) : null, p_pit_location: next.date ? next.place : null, p_back: next.date ? next.back : false, p_expected_version: Number(entry.booking_version || 0) });
      ui.message = result?.ok ? '' : (result?.message || 'The pit booking was not saved.');
    } catch (error) {
      ui.message = `The pit booking was not saved. ${error.message || ''}`.trim();
    }
    await load();
    paintPanel();
  }

  /** r630 (F245): open the time and place box. Resolves when it closes; onCancel runs if it was not saved. */
  function openDialog(vehicleId, { date, back = false, onCancel = null } = {}) {
    const entry = board.byKey.get(vehicleId);
    if (!entry || !isoDate(date)) return;
    document.querySelector('[data-pit-dlg-back]')?.remove();
    const booked = Boolean(isoDate(entry.pit_date));
    let time = hhmm(entry.pit_time) || ui.lastTime;
    let place = entry.pit_location || ui.lastPlace;
    document.body.insertAdjacentHTML('beforeend', dialogHtml({ entry, date, time, place, back, booked }));
    const wrap = document.querySelector('[data-pit-dlg-back]');
    const list = wrap.querySelector('[data-pit-times]');
    const opener = document.activeElement;
    const show = () => {
      list.querySelectorAll('[data-pit-time]').forEach(b => b.setAttribute('aria-selected', String(b.dataset.pitTime === time)));
      wrap.querySelectorAll('[data-pit-dlg-place]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.pitDlgPlace === place)));
      list.querySelector(`[data-pit-time="${time}"]`)?.scrollIntoView({ block: 'center' });
    };
    if (!TIME_SLOTS.includes(time)) time = TIME_SLOTS[0];
    if (!PLACES.includes(place)) place = PLACES[0];
    const step = delta => { const i = TIME_SLOTS.indexOf(time); time = TIME_SLOTS[Math.max(0, Math.min(TIME_SLOTS.length - 1, (i < 0 ? 0 : i) + delta))]; show(); };
    let saved = false;
    const close = () => { wrap.remove(); document.removeEventListener('keydown', onKey, true); if (!saved && typeof onCancel === 'function') onCancel(); try { opener?.focus?.(); } catch (_) { /* gone */ } };
    const commit = () => {
      saved = true; ui.lastTime = time; ui.lastPlace = place; close();
      save(vehicleId, { date, time, place, back: back || (booked && date === entry.pit_date ? Boolean(entry.back) : false) });
    };
    function onKey(event) {
      if (event.key === 'Escape') { event.preventDefault(); close(); }
      else if (event.key === 'Enter') { event.preventDefault(); commit(); }
      else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); step(event.key === 'ArrowDown' ? 1 : -1); }
      else if (/^[1-9]$/.test(event.key) && PLACES[Number(event.key) - 1]) { event.preventDefault(); place = PLACES[Number(event.key) - 1]; show(); }
    }
    document.addEventListener('keydown', onKey, true);
    // Mouse wheel over the times moves one step (15 minutes) per notch.
    let wheelAt = 0;
    list.addEventListener('wheel', event => {
      event.preventDefault();
      const now = Date.now();
      if (now - wheelAt < 60 && Math.abs(event.deltaY) < 40) return; // trackpads send many small events
      wheelAt = now;
      step(event.deltaY > 0 ? 1 : -1);
    }, { passive: false });
    list.querySelectorAll('[data-pit-time]').forEach(b => {
      b.addEventListener('click', () => { time = b.dataset.pitTime; show(); });
      b.addEventListener('dblclick', () => { time = b.dataset.pitTime; commit(); });
    });
    wrap.querySelectorAll('[data-pit-dlg-place]').forEach(b => b.addEventListener('click', () => { place = b.dataset.pitDlgPlace; show(); }));
    wrap.querySelector('[data-pit-dlg-save]').addEventListener('click', commit);
    wrap.querySelector('[data-pit-dlg-cancel]').addEventListener('click', close);
    wrap.querySelector('[data-pit-dlg-remove]')?.addEventListener('click', () => { saved = true; close(); save(vehicleId, { date: null, time: null, place: null, back: false }); });
    wrap.addEventListener('mousedown', event => { if (event.target === wrap) close(); });
    show();
    list.focus();
  }

  function bindPanel(panel) {
    if (!panel) return;
    panel.querySelectorAll('[data-pit-filter]').forEach(b => b.addEventListener('click', () => { ui.filter = b.dataset.pitFilter; paintPanel(); }));
    panel.querySelectorAll('[data-pit-month]').forEach(b => b.addEventListener('click', () => {
      const delta = Number(b.dataset.pitMonth);
      ui.month = delta ? shiftMonth(monthStart(ui.month || board.today), delta) : '';
      paintPanel();
    }));
    panel.querySelectorAll('[data-pit-place-for]').forEach(s => s.addEventListener('change', () => save(s.dataset.pitPlaceFor, { place: s.value })));
    panel.querySelectorAll('[data-pit-back]').forEach(c => c.addEventListener('change', () => {
      const entry = board.byKey.get(c.dataset.pitBack);
      if (c.checked && entry && !isoDate(entry.pit_date)) openDialog(c.dataset.pitBack, { date: board.today, back: true, onCancel: () => { c.checked = false; } });
      else save(c.dataset.pitBack, { back: c.checked });
    }));
    panel.querySelectorAll('[data-pit-clear]').forEach(b => b.addEventListener('click', () => save(b.dataset.pitClear, { date: null, place: null, back: false })));
    panel.querySelectorAll('[data-pit-drag]').forEach(el => el.addEventListener('dragstart', event => {
      event.dataTransfer.setData('application/x-pdc-pit-vehicle', el.dataset.pitDrag);
      event.dataTransfer.setData('text/plain', el.dataset.pitDrag);
      event.dataTransfer.effectAllowed = 'move';
    }));
    panel.querySelectorAll('[data-pit-edit]').forEach(chip => {
      const open = () => { const entry = board.byKey.get(chip.dataset.pitEdit); if (entry) openDialog(chip.dataset.pitEdit, { date: entry.pit_date }); };
      chip.addEventListener('click', open);
      chip.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); open(); } });
    });
    panel.querySelectorAll('[data-pit-day]').forEach(day => {
      day.addEventListener('dragover', event => { if (event.dataTransfer.types.includes('application/x-pdc-pit-vehicle')) { event.preventDefault(); day.classList.add('is-drop'); } });
      day.addEventListener('dragleave', () => day.classList.remove('is-drop'));
      day.addEventListener('drop', event => {
        event.preventDefault();
        day.classList.remove('is-drop');
        const vid = event.dataTransfer.getData('application/x-pdc-pit-vehicle');
        const entry = board.byKey.get(vid);
        if (!entry) return;
        // r630 (F245): ask the time and place, then save. A moved booking starts on its own time and place.
        openDialog(vid, { date: day.dataset.pitDay });
      });
    });
  }

  /** Called by the Vehicle Locations table after each render. */
  function afterRender(host, { bucket, search = null } = {}) {
    if (!host) return;
    host.querySelector('[data-pdc-pit-panel]')?.remove();
    if (bucket !== 'pit') return; // r618 (F233): the list and calendar belong to the PIT tile only
    ui.host = host;
    ui.search = searchActive(search) ? { key: String(search.key || ''), text: String(search.text || '') } : null;
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
