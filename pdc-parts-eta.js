/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r436 (F47): parts ETA from parts-staff emails, shown next to the parts location on board vehicle rows. Read only.
 * r475 (F88, Craig 22 Oct 10:51): the chip reads "Parts ETA dd/mm · N days" (due today amber "today", past red "N days overdue",
 * Perth dates) and its hover names the source email: who sent it, when (Perth time), the subject and the quoted line. The
 * vehicle details (drop-down card and the Table view slide-out panel) show the same countdown and source. Data comes from
 * get_pdc_parts_eta_board_v2 (r475 migration); until that exists the board falls back to the r436 get_pdc_parts_eta_board
 * by itself (countdown, no source). The Table view lifts this chip into its own "Parts ETA" column (pdc-vehicle-locations-table.js).
 * r482 (F95, Craig 22 Oct): booking warning. Before a bay booking is saved, any booking that starts (Perth date) before the
 * vehicle's parts ETA asks "Book anyway" or "Cancel" (warning only; Cancel makes no booking, Book anyway books exactly as
 * before). No ETA, or an ETA on or before the booking date, means no question. Used by the planner (workshopDispatchSharedAction),
 * Book all stations and Prioritise vehicle. bookingWarning / bookAllWarning / warningText are the pure parts (tested). */
(() => {
  'use strict';
  const VERSION = '2026.10.22.r482';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const RPC_V2 = 'get_pdc_parts_eta_board_v2', RPC_V1 = 'get_pdc_parts_eta_board';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const iso = value => /^\d{4}-\d{2}-\d{2}/.test(String(value || '')) ? String(value).slice(0, 10) : '';
  const ddmm = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}` : ''; };
  const ddmmyy = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(2, 4)}` : ''; };
  const stockKey = value => String(value ?? '').trim().toUpperCase();
  const clean = value => String(value ?? '').replace(/\s+/g, ' ').trim();
  /** Today's date in Perth (YYYY-MM-DD) whatever the device time zone; '' if the browser cannot tell. */
  function perthToday(now = new Date()) {
    try {
      const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Perth', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
      const get = type => parts.find(p => p.type === type)?.value || '';
      const out = `${get('year')}-${get('month')}-${get('day')}`;
      return /^\d{4}-\d{2}-\d{2}$/.test(out) ? out : '';
    } catch (_) { return ''; }
  }
  /** Whole days from today to the ETA (calendar dates, no clock): 0 today, negative overdue. */
  function daysUntil(eta, today) {
    const a = iso(eta), b = iso(today);
    if (!a || !b) return null;
    return Math.round((Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10)) - Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10))) / 86400000);
  }
  function countdown(eta, today) {
    const days = daysUntil(eta, today);
    if (days === null) return { days, text: '', state: 'ok' };
    if (days < 0) return { days, text: `${-days} day${days === -1 ? '' : 's'} overdue`, state: 'overdue' };
    if (days === 0) return { days, text: 'today', state: 'due' };
    return { days, text: `${days} day${days === 1 ? '' : 's'}`, state: 'ok' };
  }
  /** "Thu 22/10/26 9:15 am AWST" (Perth time) for the email's sent time. */
  function sentLabel(value) {
    const d = new Date(value || '');
    if (!value || Number.isNaN(d.getTime())) return '';
    try {
      const parts = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', year: '2-digit', hour: 'numeric', minute: '2-digit', hour12: true }).formatToParts(d);
      const get = type => parts.find(p => p.type === type)?.value || '';
      return `${get('weekday')} ${get('day')}/${get('month')}/${get('year')} ${get('hour')}:${get('minute')} ${get('dayPeriod').toLowerCase()} AWST`;
    } catch (_) { return ''; }
  }
  /** Hover lines for one ETA's source email (r475 board v2; nothing for r436 rows). */
  function sourceLines(part) {
    if (!part) return [];
    const lines = [];
    const sender = clean(part.sender), name = clean(part.sender_name);
    if (sender || name) lines.push(`From: ${name && sender ? (name.toLowerCase() === sender.toLowerCase() ? sender : `${name} <${sender}>`) : name || sender}`);
    const sent = sentLabel(part.message_at);
    if (sent) lines.push(`Sent: ${sent}`);
    if (clean(part.subject)) lines.push(`Subject: ${clean(part.subject)}`);
    if (clean(part.quote)) lines.push(`“${clean(part.quote)}”`);
    if (clean(part.previous_stock)) lines.push(`Email also names stock ${clean(part.previous_stock)} (renumbered)`);
    return lines;
  }
  /** Index the server's board payload by vehicle id and by stock number. */
  function indexBoard(payload) {
    const byId = new Map(), byStock = new Map();
    for (const entry of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      if (!entry || !iso(entry.latest_eta)) continue;
      if (entry.vehicle_id) byId.set(String(entry.vehicle_id).toLowerCase(), entry);
      if (stockKey(entry.stock_number)) byStock.set(stockKey(entry.stock_number), entry);
    }
    return { byId, byStock, today: iso(payload?.today) };
  }
  function entryFor(index, vehicle) {
    if (!index || !vehicle) return null;
    for (const id of [vehicle.__emailVehicleId, vehicle.id, vehicle.permanentVehicleId]) {
      const hit = id && index.byId.get(String(id).toLowerCase());
      if (hit) return hit;
    }
    return index.byStock.get(stockKey(vehicle.stock)) || null;
  }
  /** Label, tooltip and colour for one vehicle: latest ETA with a days countdown plus a count; any part overdue (before today,
   * Perth) is red, due today amber. */
  function summarise(entry, today) {
    if (!entry || !iso(entry.latest_eta)) return null;
    const parts = Array.isArray(entry.parts) ? entry.parts : [];
    const count = Number(entry.count) || parts.length || 1;
    const overdue = parts.filter(p => today && iso(p.eta_date) && iso(p.eta_date) < today).length;
    const dueToday = parts.some(p => today && iso(p.eta_date) === today);
    const left = countdown(entry.latest_eta, today);
    const state = overdue || left.state === 'overdue' ? 'overdue' : dueToday || left.state === 'due' ? 'due' : 'ok';
    const value = `${ddmm(entry.latest_eta)}${left.text ? ` · ${left.text}` : ''}${count > 1 ? ` · ${count} parts` : ''}`;
    const label = `Parts ETA ${value}`;
    const lines = [];
    parts.forEach(p => {
      const bits = [`${p.part || 'Part'}: ${ddmmyy(p.eta_date)}`];
      if (today && iso(p.eta_date) < today) bits.push('OVERDUE');
      if (p.line_no) bits.push(`line ${p.line_no}`);
      if (p.ro) bits.push(`R/O ${p.ro}`);
      if (p.bay) bits.push(`bay ${p.bay}`);
      if (p.notes) bits.push(String(p.notes));
      lines.push(bits.join(' · '), ...sourceLines(p).map(line => `  ${line}`));
    });
    const title = [`Parts ETA (Perth), latest ${ddmmyy(entry.latest_eta)}${left.text ? ` · ${left.text}` : ''}${overdue ? `, ${overdue} overdue` : ''}`, ...lines].join('\n');
    return { label, value, title, state, count, overdue, days: left.days, countdown: left.text, eta: iso(entry.latest_eta) };
  }
  function chipHtml(summary) {
    if (!summary) return '';
    return `<span class="pdc-parts-eta pdc-parts-eta-${summary.state}" title="${esc(summary.title)}" aria-label="${esc(summary.title)}" data-parts-eta="${esc(summary.eta || '')}" data-parts-eta-days="${summary.days ?? ''}"><span class="pdc-parts-eta-k">Parts ETA </span>${esc(summary.value || summary.label)}</span>`;
  }
  /** Put the chip beside the parts location (Tune Tag) on a board row; without a parts location, at the right of the vehicle name. */
  function decorateRow(html, summary) {
    const chip = chipHtml(summary);
    if (!chip || typeof html !== 'string' || html.includes('class="pdc-parts-eta ')) return html;
    const location = /(<span class="tune-parts-location"[^>]*>[\s\S]*?<\/span>)/;
    if (location.test(html)) return html.replace(location, (_, loc) => `<span class="pdc-parts-eta-wrap">${loc}${chip}</span>`);
    return html.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)/, (_, start) => `${start}<span class="pdc-parts-eta-wrap">${chip}</span>`);
  }
  /** Vehicle details block (drop-down card and slide-out panel): date + countdown, each part, and its source email in full. */
  function detailHtml(entry, today) {
    const s = summarise(entry, today);
    if (!s) return '';
    const rows = (entry.parts || []).map(p => {
      const source = sourceLines(p).map(line => `<small class="pdc-parts-eta-source">${esc(line)}</small>`).join('');
      return `<span class="${today && iso(p.eta_date) < today ? 'pdc-parts-eta-overdue' : ''}">${esc(p.part)}: ${esc(ddmmyy(p.eta_date))}${p.line_no ? ` · line ${esc(p.line_no)}` : ''}${p.bay ? ` · bay ${esc(p.bay)}` : ''}${p.ro ? ` · R/O ${esc(p.ro)}` : ''}</span>${source}`;
    }).join('');
    return `<div class="tune-service-location-job pdc-parts-eta-detail" title="${esc(s.title)}"><b>Parts ETA</b><span class="pdc-parts-eta-countdown pdc-parts-eta-${s.state}">${esc(ddmmyy(s.eta))}${s.countdown ? ` · ${esc(s.countdown)}` : ''}</span>${rows}<small>From parts staff emails (Perth dates)</small></div>`;
  }
  // ---- r482 (F95): parts ETA booking warning (pure parts) ----
  /** Perth calendar date (YYYY-MM-DD) of a booking start time; '' if it cannot be read. */
  function perthDate(value) {
    const d = value instanceof Date ? value : new Date(value || '');
    if (!value || Number.isNaN(d.getTime())) return '';
    return perthToday(d);
  }
  /** "Thu 22 Oct, 1:15 pm" (Perth) for a booking start. */
  function startLabel(value) {
    const d = new Date(value || '');
    if (!value || Number.isNaN(d.getTime())) return '';
    try {
      const parts = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true }).formatToParts(d);
      const get = type => parts.find(p => p.type === type)?.value || '';
      return `${get('weekday')} ${get('day')} ${get('month')}, ${get('hour')}:${get('minute')} ${get('dayPeriod').toLowerCase()}`;
    } catch (_) { return ''; }
  }
  const weekday = value => { const d = iso(value); return d ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][new Date(Date.UTC(+d.slice(0, 4), +d.slice(5, 7) - 1, +d.slice(8, 10))).getUTCDay()] : ''; };
  /** "Thu 29/10/26" for an ETA date. */
  const etaLabel = value => (iso(value) ? `${weekday(value)} ${ddmmyy(value)}` : '');
  /** Bookings (each { station, bay, start }) that start on a Perth date before the vehicle's latest active parts ETA.
   * null when there is no ETA or nothing starts before it. The latest ETA is used: the job needs every part. */
  function bookingWarning(entry, bookings, vehicleLabel = '') {
    const eta = iso(entry?.latest_eta);
    if (!eta) return null;
    const before = (Array.isArray(bookings) ? bookings : []).map(b => ({ ...b, date: perthDate(b?.start) }))
      .filter(b => b.date && b.date < eta);
    if (!before.length) return null;
    const parts = (Array.isArray(entry.parts) ? entry.parts : []).filter(p => iso(p?.eta_date) && iso(p.eta_date) > before[0].date)
      .map(p => ({ part: clean(p.part) || 'Part', eta: iso(p.eta_date) }));
    return { eta, etaLabel: etaLabel(eta), vehicle: clean(vehicleLabel) || clean(entry.stock_number), count: Number(entry.count) || parts.length || 1, parts, before };
  }
  /** Book all stations picks its bays and times on the server (no dry run), so it warns when the parts ETA is after today:
   * the earliest booking can then start before the parts are due. */
  function bookAllWarning(entry, today, vehicleLabel = '') {
    const eta = iso(entry?.latest_eta), day = iso(today);
    if (!eta || !day || eta <= day) return null;
    return { eta, etaLabel: etaLabel(eta), vehicle: clean(vehicleLabel) || clean(entry.stock_number), count: Number(entry.count) || 1, parts: [], before: [], bookAll: true, today: day };
  }
  const bookingLine = b => [clean(b.station) || 'Workshop', b.bay ? `Bay ${clean(b.bay)}` : '', startLabel(b.start)].filter(Boolean).join(' · ');
  /** Plain text of the question (also the aria description). */
  function warningText(warnings) {
    const list = (Array.isArray(warnings) ? warnings : [warnings]).filter(Boolean);
    const lines = [];
    for (const w of list) {
      lines.push(`${w.vehicle ? `${w.vehicle}: ` : ''}Parts ETA ${w.etaLabel}${w.count > 1 ? ` (latest of ${w.count} parts)` : ''}.`);
      if (w.bookAll) lines.push(`Book all stations books each outstanding station in its next available bay. The earliest start is today (${etaLabel(w.today)}), before the parts are due.`);
      else { lines.push('Booked before the parts ETA:'); for (const b of w.before) lines.push(`• ${bookingLine(b)}`); }
    }
    lines.push('You can still book it. Book anyway confirms you understand it is booked before the parts ETA.');
    return lines.join('\n');
  }
  /** Metadata note for the booking RPC's p_metadata (stored in its audit / receipt; no schema change). */
  function acknowledgement(warnings) {
    const list = (Array.isArray(warnings) ? warnings : [warnings]).filter(Boolean);
    if (!list.length) return null;
    return { acknowledged: true, eta_date: list.map(w => w.eta).sort().pop(), bookings_before_eta: list.reduce((n, w) => n + w.before.length, 0), release: 'r482' };
  }
  if (typeof module !== 'undefined') module.exports = { indexBoard, entryFor, summarise, chipHtml, decorateRow, detailHtml, ddmm, ddmmyy, perthToday, daysUntil, countdown, sentLabel, sourceLines, RPC_V2, RPC_V1, VERSION,
    perthDate, startLabel, etaLabel, bookingWarning, bookAllWarning, warningText, acknowledgement };
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_PARTS_ETA_VERSION) return;
  window.PDC_PARTS_ETA_VERSION = VERSION;
  let index = null, lastBody = '', loading = false, rpc = RPC_V2, v2RetryAt = 0;
  // Perth date from the device clock (so the countdown turns over at Perth midnight), else the server's date.
  const today = () => perthToday() || index?.today || '';
  async function load() {
    const config = window.PDC_SUPABASE_CONFIG, token = window.__pdcCachedAccessToken;
    if (loading || !token || config?.url?.replace(/\/$/, '') !== `https://${PROJECT}.supabase.co` || document.visibilityState === 'hidden') return;
    loading = true;
    try {
      if (rpc === RPC_V1 && Date.now() >= v2RetryAt) rpc = RPC_V2;
      const call = name => fetch(config.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
        method: 'POST', headers: { 'Content-Type': 'application/json', apikey: config.publishableKey, Authorization: 'Bearer ' + token }, body: '{}'
      });
      let response = await call(rpc);
      if (!response.ok && rpc === RPC_V2 && response.status === 404) {
        // r475 SQL not applied yet: use the r436 read (no source) and look for v2 again in 30 minutes.
        rpc = RPC_V1; v2RetryAt = Date.now() + 30 * 60 * 1000;
        response = await call(rpc);
      }
      if (!response.ok) return;
      const text = await response.text();
      if (text === lastBody) return;
      lastBody = text; index = indexBoard(JSON.parse(text || 'null'));
      if (typeof refreshAllViews === 'function') refreshAllViews();
    } catch (_) { /* Keep the last good ETAs; the next poll retries. */ }
    finally { loading = false; }
  }
  if (typeof incomingVehicleDetailRow === 'function') {
    const prior = incomingVehicleDetailRow;
    incomingVehicleDetailRow = (vehicle, ...args) => {
      const html = prior(vehicle, ...args);
      const entry = entryFor(index, vehicle);
      if (!entry) return html;
      const day = today();
      return decorateRow(html, summarise(entry, day))
        .replace('<div class="incoming-vehicle-detail-grid">', '<div class="incoming-vehicle-detail-grid">' + detailHtml(entry, day));
    };
  }
  // r482 (F95): the "Book anyway / Cancel" question. Resolves true to book, false to make no booking. One question at a time.
  let asking = null;
  function ask(warnings) {
    const list = (Array.isArray(warnings) ? warnings : [warnings]).filter(Boolean);
    if (!list.length) return Promise.resolve(true);
    if (asking) return Promise.resolve(false);
    asking = new Promise(resolve => {
      const dialog = document.createElement('dialog');
      dialog.className = 'pdc-parts-eta-confirm';
      dialog.setAttribute('role', 'alertdialog');
      dialog.setAttribute('aria-labelledby', 'pdc-parts-eta-confirm-title');
      dialog.setAttribute('aria-describedby', 'pdc-parts-eta-confirm-body');
      const groups = list.map(w => `<section><p class="pdc-parts-eta-confirm-eta">${w.vehicle ? `<b>${esc(w.vehicle)}</b> · ` : ''}Parts ETA <strong>${esc(w.etaLabel)}</strong>${w.count > 1 ? ` <small>(latest of ${w.count} parts)</small>` : ''}</p>`
        + (w.bookAll
          ? `<p>Book all stations books each outstanding station in its next available bay. The earliest start is today (${esc(etaLabel(w.today))}), before the parts are due. The bays and times are shown after booking, with any that start before the ETA marked.</p>`
          : `<p>Booked before the parts ETA:</p><ul>${w.before.map(b => `<li>${esc(bookingLine(b))}</li>`).join('')}</ul>`) + '</section>').join('');
      dialog.innerHTML = `<h2 id="pdc-parts-eta-confirm-title">Parts not due yet</h2><div id="pdc-parts-eta-confirm-body">${groups}<p class="pdc-parts-eta-confirm-note">You can still book it. Book anyway confirms you understand it is booked before the parts ETA.</p></div>`
        + '<footer><button type="button" class="small-button" data-parts-eta-cancel>Cancel</button><button type="button" class="primary" data-parts-eta-book>Book anyway</button></footer>';
      let done = false;
      const finish = value => {
        if (done) return; done = true; asking = null;
        try { dialog.close(); } catch (_) { /* already closed */ }
        dialog.remove();
        resolve(value);
      };
      dialog.querySelector('[data-parts-eta-cancel]').addEventListener('click', () => finish(false));
      dialog.querySelector('[data-parts-eta-book]').addEventListener('click', () => finish(true));
      dialog.addEventListener('cancel', event => { event.preventDefault(); finish(false); });
      dialog.addEventListener('close', () => finish(false));
      document.body.appendChild(dialog);
      try { dialog.showModal(); } catch (_) { dialog.setAttribute('open', ''); }
      dialog.querySelector('[data-parts-eta-cancel]').focus();
    });
    return asking;
  }
  const vehicleText = vehicle => clean(vehicle?.stock || vehicle?.stock_number) ? `Stock ${clean(vehicle.stock || vehicle.stock_number)}` : '';
  /** groups: [{ vehicle: { id, stock }, bookings: [{ station, bay, start }] }] -> warnings for the vehicles that have them. */
  function check(groups) {
    const out = [];
    for (const g of Array.isArray(groups) ? groups : [groups]) {
      const entry = g && entryFor(index, g.vehicle);
      const w = entry && bookingWarning(entry, g.bookings, vehicleText(g.vehicle) || clean(entry.stock_number) && `Stock ${clean(entry.stock_number)}`);
      if (w) out.push(w);
    }
    return out;
  }
  /** Ask only if something starts before its parts ETA. Resolves { ok, warnings }. */
  async function confirmBookings(groups) {
    const warnings = check(groups);
    if (!warnings.length) return { ok: true, warnings };
    return { ok: await ask(warnings), warnings };
  }
  /** Book all stations: the warning for this vehicle, or null (checked synchronously so no-ETA booking is unchanged). */
  function bookAllWarningFor(vehicle) {
    const entry = entryFor(index, vehicle);
    return (entry && bookAllWarning(entry, today(), vehicleText(vehicle) || `Stock ${clean(entry.stock_number)}`)) || null;
  }
  async function confirmBookAll(vehicle) {
    const w = bookAllWarningFor(vehicle);
    if (!w) return { ok: true, warnings: [] };
    return { ok: await ask([w]), warnings: [w] };
  }
  /** The ETA date when this start (Perth date) is before the vehicle's parts ETA, else ''. */
  function beforeEta(vehicle, start) {
    const eta = iso(entryFor(index, vehicle)?.latest_eta), date = perthDate(start);
    return eta && date && date < eta ? eta : '';
  }
  window.PDC_PARTS_ETA = Object.freeze({ VERSION, summarise, entryFor: vehicle => entryFor(index, vehicle), today, rpc: () => rpc, reload: load,
    check, ask, confirmBookings, bookAllWarningFor, confirmBookAll, beforeEta, acknowledgement, etaLabel });
  const style = document.createElement('style');
  style.textContent = '.incoming-card-main:has(.pdc-parts-eta-wrap){display:grid!important;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:6px!important}'
    + '.pdc-parts-eta-wrap{display:flex;flex-direction:column;align-items:flex-end;gap:2px;min-width:0}'
    + '.pdc-parts-eta{font-size:10.5px;font-weight:650;line-height:1.2;white-space:nowrap;padding:1px 5px;border-radius:4px;background:#e0f2fe;color:#075985;cursor:help}'
    + '.pdc-parts-eta-due{background:#fef3c7;color:#92400e}.pdc-parts-eta-overdue{background:#fee2e2;color:#b91c1c}'
    + '.pdc-parts-eta-detail{grid-column:1/-1}.pdc-parts-eta-detail span{display:block}.pdc-parts-eta-detail span.pdc-parts-eta-overdue{background:none;font-weight:650}'
    + '.pdc-parts-eta-detail .pdc-parts-eta-countdown{display:inline-block;font-weight:700;padding:1px 6px;border-radius:4px;margin:2px 0;background:#e0f2fe;color:#075985}'
    + '.pdc-parts-eta-detail .pdc-parts-eta-countdown.pdc-parts-eta-due{background:#fef3c7;color:#92400e}.pdc-parts-eta-detail .pdc-parts-eta-countdown.pdc-parts-eta-overdue{background:#fee2e2;color:#b91c1c}'
    + '.pdc-parts-eta-detail small.pdc-parts-eta-source{display:block;color:#475569;padding-left:8px;white-space:normal;overflow-wrap:anywhere}'
    + '.pdc-parts-eta-confirm{width:min(520px,calc(100vw - 32px));border:1px solid #cbd5e1;border-left:5px solid #d97706;border-radius:12px;padding:20px 22px;color:#17283d;font-size:14px}'
    + '.pdc-parts-eta-confirm::backdrop{background:#0f172a77}.pdc-parts-eta-confirm h2{margin:0 0 10px;font-size:18px;color:#92400e}'
    + '.pdc-parts-eta-confirm section{margin:0 0 10px}.pdc-parts-eta-confirm p{margin:0 0 6px}.pdc-parts-eta-confirm ul{margin:0 0 6px;padding-left:20px}'
    + '.pdc-parts-eta-confirm-eta strong{color:#92400e}.pdc-parts-eta-confirm-note{color:#475569;font-size:13px}'
    + '.pdc-parts-eta-confirm footer{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}'
    + '.book-all-before-eta{display:block;color:#b45309;font-weight:650;font-size:11px}';
  document.head.appendChild(style);
  load();
  setInterval(load, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setTimeout(load, 4000);
  const warmup = setInterval(() => { if (index) clearInterval(warmup); else load(); }, 20000);
})();
