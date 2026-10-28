/*
 * r612 (F226): Completed Vehicles shows every vehicle that has been at PMB. Craig, 28 Oct 2026.
 * Includes vehicles taken off the board because they dropped off an upload (they are archived, never
 * deleted), deleted vehicles, RFT and completed ones. Each row: import date, PMB, QC, RFT and leaving
 * dates, lines done, bay time, stations and pit. "Details" opens everything kept for that vehicle:
 * every job line and who ticked it, every bay booking with actual times and fitter line timings, pit
 * booking and pit ticks, and the board history (removed, put back, deleted).
 * Reads get_pdc_vehicle_history_612 and get_pdc_vehicle_history_detail_612. View only.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.28.r612';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const LIST_TTL_MS = 2 * 60 * 1000;

  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const DATE = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', year: '2-digit' });
  const DATETIME = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', year: '2-digit', hour: 'numeric', minute: '2-digit' });
  function fmtDate(value) {
    if (!value) return '';
    if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) { const [y, m, d] = String(value).split('-'); return `${d}/${m}/${y.slice(2)}`; }
    const t = Date.parse(value); return Number.isFinite(t) ? DATE.format(t) : '';
  }
  function fmtDateTime(value) { const t = Date.parse(value || ''); return Number.isFinite(t) ? DATETIME.format(t) : ''; }
  const dash = '<span class="vh-dash">—</span>';
  const cell = value => (value ? esc(value) : dash);
  function hoursText(h) { const n = Number(h) || 0; return n ? `${n.toFixed(1)} h` : ''; }
  function minutesText(m) { const n = Math.round(Number(m) || 0); if (!n) return ''; return n >= 60 ? `${Math.floor(n / 60)}h ${n % 60}m` : `${n}m`; }

  const STATUS = Object.freeze({
    on_board: ['On board', 'is-board'], rft: ['RFT', 'is-rft'], completed: ['Completed', 'is-done'],
    removed: ['Off upload', 'is-removed'], deleted: ['Deleted', 'is-deleted'], hidden: ['Hidden', 'is-hidden'],
  });
  const TABS = Object.freeze({
    left: ['Left the board', s => ['completed', 'rft', 'removed', 'deleted'].includes(s)],
    completed: ['Completed', s => s === 'completed' || s === 'rft'],
    removed: ['Off upload', s => s === 'removed'],
    deleted: ['Deleted', s => s === 'deleted'],
    on_board: ['On board', s => s === 'on_board' || s === 'hidden'],
    all: ['All', () => true],
  });

  function searchText(v) {
    return [v.stock, v.key, v.job_card, v.vehicle, v.customer, v.location, v.removed_reason, (v.stations || []).join(' '),
      STATUS[v.status]?.[0], v.pit_location].filter(Boolean).join(' ').toLowerCase();
  }
  function filterRows(vehicles, { tab = 'left', search = '' } = {}) {
    const test = (TABS[tab] || TABS.left)[1];
    const needle = String(search || '').trim().toLowerCase();
    return (vehicles || []).filter(v => test(v.status) && (!needle || searchText(v).includes(needle)));
  }
  function tabCounts(vehicles) {
    return Object.fromEntries(Object.entries(TABS).map(([key, [, test]]) => [key, (vehicles || []).filter(v => test(v.status)).length]));
  }

  function leftAt(v) { return v.removed_at || v.collected_at || v.delivered || v.rft_at || ''; }
  function pitText(v) {
    if (!v.pit_date) return '';
    return `${fmtDate(v.pit_date)} ${v.pit_location || ''}${v.pit_back ? ' ✓' : ''}`.trim();
  }

  function rowHtml(v, open) {
    const [label, tone] = STATUS[v.status] || [v.status, ''];
    const reason = v.removed_reason ? ` title="${esc(v.removed_reason)}"` : '';
    const bay = v.actual_hours || v.booked_hours ? `${hoursText(v.actual_hours) || '0 h'}${v.booked_hours ? ` <small>of ${hoursText(v.booked_hours)}</small>` : ''}` : dash;
    return `<tr class="vh-row${open ? ' is-open' : ''}" data-vh-id="${esc(v.id)}">
      <td><strong>${cell(v.stock)}</strong><small>${v.key ? `Key ${esc(v.key)} · ` : ''}${esc(v.job_card || '')}</small></td>
      <td><strong>${cell(v.customer)}</strong><small>${esc(v.vehicle || '')}</small></td>
      <td><span class="vh-status ${tone}"${reason}>${esc(label)}</span></td>
      <td>${cell(fmtDate(v.imported_at))}</td>
      <td>${cell(fmtDate(v.to_pmb))}</td>
      <td>${cell(fmtDate(v.qc_done_at))}</td>
      <td>${cell(fmtDate(v.rft_at))}</td>
      <td>${cell(fmtDate(leftAt(v)))}</td>
      <td class="vh-num">${v.lines ? `${v.lines_done}/${v.lines}` : dash}</td>
      <td class="vh-num">${bay}</td>
      <td>${(v.stations || []).length ? esc(v.stations.join(', ')) : dash}</td>
      <td>${v.pit_date ? `<span class="vh-pit${v.pit_back ? ' is-back' : ''}">${esc(pitText(v))}</span>` : dash}</td>
      <td><button type="button" class="small-button" data-vh-open="${esc(v.id)}" aria-expanded="${open}">${open ? 'Hide' : 'Details'}</button></td>
    </tr>`;
  }

  function tableHtml(list, { tab = 'left', search = '', openId = '', details = {}, limit = 300 } = {}) {
    const vehicles = list?.vehicles || [];
    const counts = tabCounts(vehicles);
    const rows = filterRows(vehicles, { tab, search });
    const shown = rows.slice(0, limit);
    const tabs = Object.entries(TABS).map(([key, [label]]) => `<button type="button" class="vh-tab${key === tab ? ' active' : ''}" data-vh-tab="${key}">${esc(label)} <b>${counts[key]}</b></button>`).join('');
    const body = shown.map(v => {
      const open = v.id === openId;
      return rowHtml(v, open) + (open ? `<tr class="vh-detail-row"><td colspan="13">${details[v.id] ? detailHtml(details[v.id]) : '<p class="vh-loading">Loading everything kept for this vehicle…</p>'}</td></tr>` : '');
    }).join('') || `<tr><td colspan="13" class="vh-empty">${search ? 'No vehicles match this search.' : 'No vehicles in this list.'}</td></tr>`;
    const more = rows.length > shown.length ? `<p class="vh-more">Showing ${shown.length} of ${rows.length}. Search to narrow it down. <button type="button" class="small-button" data-vh-more>Show all</button></p>` : '';
    return `<div class="vh" data-vh-version="${VERSION}">
      <div class="vh-tabs" role="toolbar" aria-label="Which vehicles">${tabs}</div>
      <div class="parts-table-wrap vh-wrap"><table class="data-table compact-table vh-table">
        <thead><tr><th>Stock / job card</th><th>Customer / vehicle</th><th>Status</th><th>Imported</th><th>To PMB</th><th>QC done</th><th>RFT</th><th>Left board</th><th>Lines done</th><th>Bay time</th><th>Stations</th><th>Pit</th><th></th></tr></thead>
        <tbody>${body}</tbody></table></div>${more}</div>`;
  }

  function detailHtml(d) {
    const milestones = [
      ['Imported', fmtDateTime(d.imported_at)], ['To PMB', fmtDate(d.to_pmb)], ['QC done', fmtDateTime(d.qc_done_at)],
      ['RFT', fmtDateTime(d.rft_at)], ['RFT confirmed', fmtDateTime(d.rft_confirmed_at)], ['Collected', fmtDateTime(d.collected_at)],
      ['Delivered', fmtDate(d.delivered)], ['Left board', fmtDateTime(d.removed_at)],
    ].filter(([, v]) => v);
    const lines = d.lines || [];
    const done = lines.filter(l => l.done).length;
    const lineRows = lines.map(l => `<tr class="${l.done ? 'is-done' : ''}${l.pit ? ' is-pit' : ''}"><td>${esc(l.ro || '')} / ${esc(l.line ?? '')}</td><td>${esc(l.description || '')}</td><td>${esc(l.station || '')}</td><td class="vh-num">${l.hours ? Number(l.hours).toFixed(1) : ''}</td><td>${l.done ? `✓ ${esc(fmtDateTime(l.done_at))}` : ''}</td><td>${esc(l.done_by || '')}</td></tr>`).join('');
    const bookings = (d.bookings || []).map(b => {
      const timings = (b.line_timings || []).filter(t => t.minutes || t.completed_at);
      const timingText = timings.length ? `<small>${timings.map(t => `${esc(t.technician || 'Tech')} ${esc(minutesText(t.minutes) || '')}`).join(' · ')}</small>` : '';
      return `<tr><td>${esc(b.station || '')}</td><td>${esc(b.bay || 'No bay')}</td><td>${esc(b.technician || '')}</td><td>${esc(b.status || '')}</td>
        <td>${esc(fmtDateTime(b.start))} – ${esc(fmtDateTime(b.end))}</td><td>${esc(fmtDateTime(b.actual_start))}${b.actual_end ? ` – ${esc(fmtDateTime(b.actual_end))}` : ''}</td>
        <td class="vh-num">${esc(minutesText(b.actual_minutes))}${timingText}</td><td>${b.stoppage ? esc(b.stoppage) : ''}${b.stoppage_minutes ? ` <small>${esc(minutesText(b.stoppage_minutes))}</small>` : ''}</td></tr>`;
    }).join('');
    const pit = d.pit ? `<p><strong>Pit booked</strong> ${esc(fmtDate(d.pit.date))} at ${esc(d.pit.location || '')}${d.pit.back ? ` · <span class="vh-pit is-back">✓ Back ${esc(fmtDateTime(d.pit.back_at))}${d.pit.back_by ? ` by ${esc(d.pit.back_by)}` : ''}</span>` : ' · not back yet'}</p>` : '';
    const pitLines = lines.filter(l => l.pit).map(l => `<li>${esc(l.description)}${l.done ? ` ✓ ${esc(fmtDateTime(l.done_at))}` : ''}</li>`).join('');
    const pitTicks = (d.pit_ticks || []).map(t => `<li>${esc(t.description || 'Pit line')}: ${t.ticked ? '✓' : 'unticked'} ${esc(fmtDateTime(t.at))}${t.by ? ` by ${esc(t.by)}` : ''}</li>`).join('');
    const events = (d.events || []).map(e => `<li><span>${esc(fmtDateTime(e.at))}</span> ${esc(String(e.what || '').replace(/_/g, ' '))}${e.by && e.by.includes('@') ? ` <small>${esc(e.by)}</small>` : ''}</li>`).join('');
    return `<div class="vh-detail">
      <div class="vh-detail-head"><strong>${esc(d.stock || '')}</strong> ${esc(d.vehicle || '')} ${d.vin ? `<small>VIN ${esc(d.vin)}</small>` : ''} ${d.rego ? `<small>Rego ${esc(d.rego)}</small>` : ''}${d.removed_reason ? `<p class="vh-reason">Left the board: ${esc(d.removed_reason)}</p>` : ''}</div>
      <dl class="vh-milestones">${milestones.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('') || '<div><dt>Dates</dt><dd>None recorded</dd></div>'}</dl>
      <section><h4>Work done <small>${done} of ${lines.length} lines ticked</small></h4>${lines.length ? `<div class="vh-scroll"><table class="vh-sub"><thead><tr><th>R/O / line</th><th>Work</th><th>Station</th><th>Hours</th><th>Done</th><th>By</th></tr></thead><tbody>${lineRows}</tbody></table></div>` : '<p class="vh-dash">No job lines kept.</p>'}</section>
      <section><h4>Bay time</h4>${bookings ? `<div class="vh-scroll"><table class="vh-sub"><thead><tr><th>Station</th><th>Bay</th><th>Tech</th><th>Status</th><th>Booked</th><th>Actual</th><th>Worked</th><th>Stoppage</th></tr></thead><tbody>${bookings}</tbody></table></div>` : '<p class="vh-dash">Never booked into a bay.</p>'}</section>
      <section><h4>Pit inspection</h4>${pit}${pitLines ? `<ul>${pitLines}</ul>` : ''}${pitTicks ? `<ul>${pitTicks}</ul>` : ''}${!pit && !pitLines && !pitTicks ? '<p class="vh-dash">No pit work recorded.</p>' : ''}</section>
      <section><h4>Board history</h4>${events ? `<ul class="vh-events">${events}</ul>` : '<p class="vh-dash">No board changes recorded.</p>'}</section>
    </div>`;
  }

  const CSS = `
.vh-tabs { display: flex; flex-wrap: wrap; gap: 6px; margin: 4px 0 10px; }
.vh-tab { border: 1px solid #cbd5e1; background: #fff; border-radius: 999px; padding: 3px 12px; font-size: 13px; cursor: pointer; }
.vh-tab b { color: #475569; margin-left: 2px; }
.vh-tab.active { background: #0f172a; border-color: #0f172a; color: #fff; }
.vh-tab.active b { color: #cbd5e1; }
.vh-table td { vertical-align: top; }
.vh-table td small, .vh-table td strong { display: block; }
.vh-table td small { color: #64748b; font-size: 11px; }
.vh-num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
.vh-dash { color: #94a3b8; }
.vh-status { display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; white-space: nowrap; background: #e2e8f0; color: #1e293b; }
.vh-status.is-done { background: #dcfce7; color: #14532d; }
.vh-status.is-rft { background: #dbeafe; color: #1e3a8a; }
.vh-status.is-removed { background: #fef3c7; color: #78350f; cursor: help; }
.vh-status.is-deleted { background: #fee2e2; color: #991b1b; cursor: help; }
.vh-pit { font-size: 11px; white-space: nowrap; }
.vh-pit.is-back { color: #15803d; font-weight: 700; }
.vh-row.is-open td { background: #f8fafc; }
.vh-detail-row > td { background: #f8fafc; padding: 0 10px 12px; }
.vh-detail { display: grid; gap: 10px; }
.vh-detail-head small { color: #64748b; margin-left: 6px; }
.vh-reason { margin: 4px 0 0; color: #92400e; font-size: 12px; }
.vh-milestones { display: flex; flex-wrap: wrap; gap: 6px 16px; margin: 0; }
.vh-milestones dt { font-size: 11px; color: #64748b; }
.vh-milestones dd { margin: 0; font-weight: 600; font-variant-numeric: tabular-nums; }
.vh-detail h4 { margin: 4px 0; font-size: 13px; }
.vh-detail h4 small { color: #64748b; font-weight: 400; margin-left: 6px; }
.vh-scroll { overflow-x: auto; max-height: 320px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 6px; background: #fff; }
.vh-sub { width: 100%; border-collapse: collapse; font-size: 12px; }
.vh-sub th { position: sticky; top: 0; background: #f1f5f9; text-align: left; padding: 3px 6px; }
.vh-sub td { padding: 3px 6px; border-top: 1px solid #f1f5f9; }
.vh-sub td small { display: block; color: #64748b; }
.vh-sub tr.is-done td:first-child { box-shadow: inset 3px 0 0 #16a34a; }
.vh-sub tr.is-pit td { background: #fffbeb; }
.vh-events { list-style: none; padding: 0; margin: 0; font-size: 12px; }
.vh-events span { display: inline-block; min-width: 120px; color: #475569; font-variant-numeric: tabular-nums; }
.vh-detail ul { margin: 4px 0; padding-left: 18px; font-size: 12px; }
.vh-more, .vh-loading, .vh-empty { font-size: 12px; color: #64748b; }
.vh-empty { text-align: center; padding: 14px; }
`;

  const api = { VERSION, fmtDate, fmtDateTime, minutesText, filterRows, tabCounts, rowHtml, tableHtml, detailHtml, TABS, STATUS, CSS };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_VEHICLE_HISTORY) return;

  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  const token = () => window.__pdcCachedAccessToken;
  async function rpc(name, body) {
    if (!token() || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    const text = await response.text();
    if (!response.ok) { let m = text; try { m = JSON.parse(text).message || text; } catch (_) { /* raw */ } throw new Error(String(m || response.status)); }
    return JSON.parse(text || 'null');
  }

  const ui = { tab: 'left', openId: '', limit: 300, list: null, loadedAt: 0, loading: null, error: '', details: {} };
  const host = () => document.getElementById('completed-vehicles-content');
  const search = () => document.getElementById('completed-search')?.value || '';

  function paint() {
    const el = host();
    if (!el) return;
    if (!ui.list) { el.innerHTML = `<p class="vh-loading">${ui.error ? `Could not load the vehicle history. ${esc(ui.error)}` : 'Loading every vehicle that has been at PMB…'}</p>`; return; }
    el.innerHTML = tableHtml(ui.list, { tab: ui.tab, search: search(), openId: ui.openId, details: ui.details, limit: ui.limit });
  }
  function load(force) {
    if (ui.loading || (!force && ui.list && Date.now() - ui.loadedAt < LIST_TTL_MS)) return ui.loading;
    ui.loading = rpc('get_pdc_vehicle_history_612', {})
      .then(json => { if (json) { ui.list = json; ui.loadedAt = Date.now(); ui.error = ''; } })
      .catch(error => { ui.error = error.message || ''; })
      .finally(() => { ui.loading = null; paint(); });
    return ui.loading;
  }
  async function openDetail(id) {
    ui.openId = ui.openId === id ? '' : id;
    paint();
    if (!ui.openId || ui.details[id]) return;
    try { ui.details[id] = await rpc('get_pdc_vehicle_history_detail_612', { p_vehicle_id: id }) || { lines: [], bookings: [], events: [] }; }
    catch (error) { ui.details[id] = { stock: '', vehicle: `Could not load: ${error.message || ''}`, lines: [], bookings: [], events: [] }; }
    paint();
  }

  document.addEventListener('click', event => {
    const el = host();
    if (!el || !el.contains(event.target)) return;
    const tab = event.target.closest('[data-vh-tab]');
    if (tab) { ui.tab = tab.dataset.vhTab; ui.limit = 300; paint(); return; }
    const open = event.target.closest('[data-vh-open]');
    if (open) { void openDetail(open.dataset.vhOpen); return; }
    if (event.target.closest('[data-vh-more]')) { ui.limit = Infinity; paint(); }
  });

  // The Completed view calls renderCompletedVehicles (search box, view switch). Keep its statistics,
  // then replace the table with the full history.
  if (typeof renderCompletedVehicles === 'function') {
    const prior = renderCompletedVehicles;
    renderCompletedVehicles = (...args) => {
      try { prior(...args); } catch (_) { /* the history table below still renders */ }
      paint();
      void load(false);
    };
  }

  const style = document.createElement('style');
  style.dataset.pdcVehicleHistory = VERSION;
  style.textContent = CSS;
  document.head.appendChild(style);
  window.PDC_VEHICLE_HISTORY = Object.freeze({ ...api, load: () => load(true) });
  // Someone may already be on Completed Vehicles when this loads: draw the history now.
  try { if (host() && typeof app !== 'undefined' && app.currentView === 'completed') renderCompletedVehicles(); } catch (_) { /* next render */ }
}(typeof window !== 'undefined' ? window : globalThis));
