/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r516 (F130): JITA ETA from a daily Revolution paste under Navision Uploads.
 * r517 (F131): after Confirm and Apply, the same success panel as Daily Navision
 * (green tick, counts, saved stocks, skipped list). The JITA date sits at the
 * bottom of the Parts ETA box, under the email Parts ETA. It does not write that ETA.
 * r519 (F133): SHOW_JITA_ETA is false. The paste stays in the page but hidden, and
 * this file does not bind it, does not read the JITA board, and does not draw a
 * JITA ETA under the email Parts ETA or on the Parts tab. The r518 Parts Jita tick
 * is not in this file. The parser below is unchanged for a later unhide.
 * One date per stock: the latest JITA Planned Delivery Date on a row with Qty Outstanding > 0,
 * otherwise the latest planned date on any row. Previous ETA, Latest ETA, Manual ETA and
 * Vehicle ETA at Kewdale are not read. */
(() => {
  'use strict';
  const VERSION = '2026.10.23.r519';
  const SHOW_JITA_ETA = false;
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const IMPORT_RPC = 'import_jita_eta_516';
  const BOARD_RPC = 'get_pdc_jita_eta_board';
  const PARTS_CHIP = /<span class="pdc-parts-eta pdc-parts-eta-(?:ok|due|overdue)"[^>]*>(?:<span class="pdc-parts-eta-k">[^<]*<\/span>)?[^<]*<\/span>/;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const stockKey = value => String(value ?? '').trim().toUpperCase();
  const iso = value => /^\d{4}-\d{2}-\d{2}/.test(String(value || '')) ? String(value).slice(0, 10) : '';
  const ddmmyyyy = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}` : ''; };

  function parseDate(raw) {
    const text = String(raw ?? '').trim();
    const match = /^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/.exec(text);
    if (!match) return null;
    const day = +match[1];
    const month = +match[2];
    let year = +match[3];
    if (year < 100) year = year <= 69 ? 2000 + year : 1900 + year;
    if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    const date = new Date(Date.UTC(year, month - 1, day));
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
    return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  function outstandingQty(raw) {
    const text = String(raw ?? '').trim().replace(/,/g, '');
    return text.length <= 12 && /^[0-9]+(\.[0-9]+)?$/.test(text) && Number(text) > 0;
  }

  /** Same reduction as jita_eta_parse_516. Latest means the greatest calendar date. */
  function parseJitaEta(text) {
    let raw = String(text ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    if (raw.length > 1500000) return { ok: false, error: 'too_big', message: 'Paste is too big.' };
    if (!raw.trim()) return { ok: false, error: 'empty', message: 'Paste the Revolution JITA export, including the header row.' };
    const lines = raw.split('\n');
    let start = -1;
    for (let i = 0; i < lines.length; i += 1) {
      if (lines[i].trim()) { start = i; break; }
    }
    if (start < 0) return { ok: false, error: 'empty', message: 'Paste the Revolution JITA export, including the header row.' };
    const header = lines[start].split('\t');
    let veh = -1; let eta = -1; let qty = -1;
    header.forEach((name, i) => {
      const key = name.trim().toLowerCase();
      if (key === 'jita vehicle' && veh < 0) veh = i;
      else if (key === 'jita planned delivery date' && eta < 0) eta = i;
      else if ((key === 'qty oustanding' || key === 'qty outstanding') && qty < 0) qty = i;
    });
    if (veh < 0 || eta < 0 || qty < 0) {
      return { ok: false, error: 'header', message: 'Header must include JITA Vehicle, JITA Planned Delivery Date, and Qty Outstanding.' };
    }
    const acc = new Map();
    let rows = 0; let blank = 0; let bad = 0;
    for (let i = start + 1; i < lines.length; i += 1) {
      if (!lines[i].trim()) continue;
      if (rows >= 8000) return { ok: false, error: 'too_big', message: 'Paste has too many rows.' };
      const cols = lines[i].split('\t');
      const stock = String(cols[veh] ?? '').trim();
      if (!stock || stock.length > 40 || /[\u0000-\u001F\u007F]/.test(stock)) { blank += 1; continue; }
      rows += 1;
      const rawDate = String(cols[eta] ?? '').trim();
      const parsed = rawDate ? parseDate(rawDate) : null;
      if (rawDate && !parsed) bad += 1;
      const key = stock.toUpperCase();
      const item = acc.get(key) || { stock, rows: 0, outstanding_rows: 0, latest_outstanding: null, latest_any: null, dates: new Set() };
      item.rows += 1;
      if (parsed && (!item.latest_any || parsed > item.latest_any)) item.latest_any = parsed;
      if (outstandingQty(cols[qty])) {
        item.outstanding_rows += 1;
        if (parsed) {
          if (!item.latest_outstanding || parsed > item.latest_outstanding) item.latest_outstanding = parsed;
          item.dates.add(parsed);
        }
      }
      acc.set(key, item);
    }
    const stocks = [...acc.values()].map(item => ({
      stock: item.stock,
      eta_date: item.latest_outstanding || item.latest_any,
      rule: item.latest_outstanding ? 'latest_outstanding' : item.latest_any ? 'latest_any' : null,
      source_rows: item.rows,
      outstanding_rows: item.outstanding_rows,
      distinct_outstanding_dates: item.dates.size
    })).sort((a, b) => String(a.stock).localeCompare(String(b.stock)));
    return { ok: true, rows, blank_vehicle_rows: blank, bad_date_rows: bad, stocks };
  }

  /** One line at the bottom of the Parts ETA box. Not a second chip beside the vehicle name. */
  function inPartsHtml(entry) {
    const date = iso(entry && entry.eta_date);
    if (!date) return '';
    return `<div class="pdc-jita-eta-in-parts" data-jita-eta="${esc(date)}"><b>JITA ETA</b><span>${esc(ddmmyyyy(date))}</span></div>`;
  }

  /** Nest JITA at the bottom of the email Parts ETA detail. If that box is absent, one Parts ETA box that holds only the JITA date. */
  function insertDetail(html, entry) {
    const line = inPartsHtml(entry);
    if (!line || typeof html !== 'string' || html.includes('pdc-jita-eta-in-parts')) return html;
    const partsDetail = /<div class="tune-service-location-job pdc-parts-eta-detail"[^>]*>[\s\S]*?<\/div>/;
    if (partsDetail.test(html)) return html.replace(partsDetail, match => match.replace(/<\/div>$/, `${line}</div>`));
    const box = `<div class="tune-service-location-job pdc-parts-eta-detail pdc-jita-eta-only">${line}</div>`;
    if (html.includes('<div class="incoming-vehicle-detail-grid">')) {
      return html.replace('<div class="incoming-vehicle-detail-grid">', `<div class="incoming-vehicle-detail-grid">${box}`);
    }
    return html;
  }

  function resultRows(payload) {
    return Array.isArray(payload?.results) ? payload.results : [];
  }

  function resultLine(row) {
    const date = ddmmyyyy(row?.eta_date);
    const previous = ddmmyyyy(row?.previous_eta);
    const when = date ? `JITA ETA ${date}${previous ? ` (was ${previous})` : ''}` : 'No planned date';
    return `<div class="summary-row"><strong>${esc(row?.stock || 'Stock')}</strong><span>${esc(when)}</span></div>`;
  }

  function resultSection(title, rows, empty) {
    const body = rows.length
      ? rows.slice(0, 40).map(resultLine).join('') + (rows.length > 40 ? `<div class="subtle">Showing first 40 of ${rows.length}.</div>` : '')
      : `<div class="summary-row"><strong>None</strong><span>${esc(empty)}</span></div>`;
    return `<div class="summary-section"><h3>${esc(title)}</h3>${body}</div>`;
  }

  /** Same shape as Daily Navision after Confirm and Apply: green tick, counts, then the lists. Preview stays the lighter checked-and-ready row. */
  function renderUploadResult(payload) {
    const dry = payload?.dry_run !== false;
    const rows = resultRows(payload);
    const saved = rows.filter(row => ['applied', 'replaced', 'would_apply', 'would_replace'].includes(row.status));
    const same = rows.filter(row => row.status === 'unchanged');
    const unknown = rows.filter(row => row.status === 'skipped_unknown');
    const ambiguous = rows.filter(row => row.status === 'ambiguous');
    const nodate = rows.filter(row => row.status === 'no_planned_date');
    const stats = `<div class="scot-summary-grid navision-human-summary">
      <div class="summary-stat"><span>Rows in the paste</span><strong>${esc(payload?.rows ?? 0)}</strong></div>
      <div class="summary-stat"><span>${dry ? 'Would be saved' : 'Dates saved'}</span><strong>${saved.length}</strong></div>
      <div class="summary-stat"><span>Already that date</span><strong>${same.length}</strong></div>
      <div class="summary-stat"><span>Not on the board</span><strong>${unknown.length}</strong></div>
      <div class="summary-stat"><span>More than one vehicle</span><strong>${ambiguous.length}</strong></div>
      <div class="summary-stat"><span>No planned date</span><strong>${nodate.length}</strong></div>
    </div>`;
    const lists = resultSection(dry ? 'JITA ETA that would be set' : 'JITA ETA set', saved, dry ? 'No vehicle date would change.' : 'No vehicle date was changed.')
      + (same.length ? resultSection('Already that date', same, '') : '')
      + resultSection('Not on the board', unknown, 'Every stock in the paste is on the board.')
      + (ambiguous.length ? resultSection('More than one vehicle', ambiguous, '') : '')
      + (nodate.length ? resultSection('No planned date', nodate, '') : '');
    if (!dry) {
      const noun = `${saved.length} vehicle date${saved.length === 1 ? '' : 's'} saved`;
      return `<div class="navision-import-success" role="status" aria-live="polite"><span class="navision-import-success-tick" aria-hidden="true">✓</span><div><strong>JITA upload complete</strong><span>${noun}. The email Parts ETA was not changed.</span></div></div>${stats}<div class="summary-section-heading"><h3>Import complete</h3></div>${lists}`;
    }
    return `<div class="summary-row success" role="status"><strong>JITA file checked and ready</strong><span>Preview only. Nothing has been saved. The email Parts ETA is not changed.</span></div>${stats}${lists}`;
  }

  const EMPTY_UPLOAD = '<div class="empty-state compact-empty"><strong>No JITA preview yet</strong><span>Paste the Revolution JITA export, then click Preview.</span></div>';

  if (typeof module !== 'undefined') {
    module.exports = { parseJitaEta, parseDate, inPartsHtml, insertDetail, renderUploadResult, ddmmyyyy, PARTS_CHIP, VERSION, SHOW_JITA_ETA, IMPORT_RPC, BOARD_RPC };
  }
  if (typeof window === 'undefined') return;
  if (!SHOW_JITA_ETA) {
    const panel = document.getElementById('jita-upload-panel');
    if (panel) panel.hidden = true;
    window.PDC_JITA_ETA_VERSION = VERSION;
    window.PDC_JITA_ETA = Object.freeze({ VERSION, hidden: true, reload() {} });
    return;
  }
  if (window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_JITA_ETA_VERSION) return;
  window.PDC_JITA_ETA_VERSION = VERSION;

  const byStock = new Map();
  let lastBody = '';
  let loading = false;
  let hooked = false;

  function entryFor(vehicle) {
    if (!vehicle) return null;
    const hit = byStock.get(stockKey(vehicle.stock || vehicle.stock_number));
    return hit || null;
  }

  function indexBoard(payload) {
    byStock.clear();
    for (const row of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      if (row && iso(row.eta_date) && stockKey(row.stock_number)) byStock.set(stockKey(row.stock_number), row);
    }
  }

  function decoratePartsTable() {
    const host = document.getElementById('parts-home-content');
    const table = host && host.querySelector('table.parts-queue-table');
    if (!table) return;
    const heads = [...table.querySelectorAll('thead th')];
    const jitaHead = heads.find(th => th.textContent.trim() === 'JITA');
    if (!jitaHead) return;
    if (!jitaHead.nextElementSibling || !jitaHead.nextElementSibling.classList.contains('pdc-jita-eta-col')) {
      const th = document.createElement('th');
      th.className = 'pdc-jita-eta-col';
      th.textContent = 'JITA ETA';
      jitaHead.insertAdjacentElement('afterend', th);
    }
    table.querySelectorAll('tbody tr').forEach(tr => {
      const jitaCell = tr.querySelector('td.parts-queue-jita-cell');
      if (!jitaCell) return;
      let cell = jitaCell.nextElementSibling;
      if (!cell || !cell.classList.contains('pdc-jita-eta-cell')) {
        cell = document.createElement('td');
        cell.className = 'pdc-jita-eta-cell';
        jitaCell.insertAdjacentElement('afterend', cell);
      }
      const stock = stockKey(tr.querySelector('.parts-compact-identity strong')?.textContent);
      const hit = byStock.get(stock);
      const text = hit ? ddmmyyyy(hit.eta_date) : '—';
      if (cell.textContent !== text) cell.textContent = text;
      cell.setAttribute('data-jita-eta', hit ? iso(hit.eta_date) : '');
    });
  }

  /** Vehicle Locations table: JITA date at the bottom of the Parts ETA cell, under the email chip. */
  function decorateLocationsTable() {
    const host = document.getElementById('vlt-table-host');
    if (!host) return;
    host.querySelectorAll('tbody tr').forEach(tr => {
      const etaCell = tr.querySelector('td.c-eta');
      if (!etaCell) return;
      tr.querySelectorAll('td.c-unit .pdc-jita-eta, td.c-unit .pdc-jita-eta-in-parts').forEach(node => node.remove());
      const stock = stockKey(tr.querySelector('td.c-stock')?.textContent);
      const date = iso(byStock.get(stock)?.eta_date);
      const dash = etaCell.querySelector('.vlt-subtle-dash');
      const slot = etaCell.querySelector('.pdc-jita-eta-in-parts');
      if (slot && slot.getAttribute('data-jita-eta') === date && (!dash || dash.hidden === Boolean(date))) return;
      if (dash) dash.hidden = Boolean(date);
      if (!date) {
        if (slot) slot.remove();
        return;
      }
      const line = document.createElement('div');
      line.className = 'pdc-jita-eta-in-parts';
      line.setAttribute('data-jita-eta', date);
      line.innerHTML = `<b>JITA ETA</b><span>${esc(ddmmyyyy(date))}</span>`;
      if (slot) slot.replaceWith(line);
      else etaCell.appendChild(line);
    });
  }

  function hookParts() {
    if (hooked || typeof renderPartsHome !== 'function') return;
    const prior = renderPartsHome;
    const wrapped = function jitaPartsHome(...args) {
      const out = prior.apply(this, args);
      try { decoratePartsTable(); } catch (_) { /* the parts table still renders */ }
      return out;
    };
    wrapped.__jita = true;
    renderPartsHome = wrapped;
    hooked = true;
    decoratePartsTable();
  }

  if (typeof incomingVehicleDetailRow === 'function') {
    const prior = incomingVehicleDetailRow;
    incomingVehicleDetailRow = (vehicle, ...args) => {
      const html = prior(vehicle, ...args);
      const entry = entryFor(vehicle);
      if (!entry) return html;
      return insertDetail(html, entry);
    };
  }

  async function rpc(name, body) {
    const config = window.PDC_SUPABASE_CONFIG;
    const token = window.__pdcCachedAccessToken;
    if (!token || config?.url?.replace(/\/$/, '') !== `https://${PROJECT}.supabase.co`) return { ok: false, missing: true };
    const response = await fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: config.publishableKey, Authorization: `Bearer ${token}` },
      body: JSON.stringify(body || {})
    });
    const text = await response.text();
    let payload = null;
    try { payload = text ? JSON.parse(text) : null; } catch (_) { payload = null; }
    return { ok: response.ok, status: response.status, payload, text };
  }

  async function loadBoard() {
    if (loading || document.visibilityState === 'hidden') return;
    loading = true;
    try {
      const result = await rpc(BOARD_RPC, {});
      if (!result.ok || result.text === lastBody) return;
      lastBody = result.text;
      indexBoard(result.payload);
      decoratePartsTable();
      decorateLocationsTable();
    } catch (_) { /* keep the last dates */ }
    finally { loading = false; }
  }

  function importAllowed() {
    if (typeof navisionSharedImportRoleAllowed === 'function') return navisionSharedImportRoleAllowed() === true;
    const role = String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
    return role === 'importer' || role === 'administrator';
  }

  function bindUpload() {
    const paste = document.getElementById('jita-paste');
    const preview = document.getElementById('jita-preview');
    const apply = document.getElementById('jita-apply');
    const clear = document.getElementById('jita-clear');
    const summary = document.getElementById('jita-upload-summary');
    const access = document.getElementById('jita-upload-access');
    if (!paste || !preview || paste.dataset.jitaBound) return;
    paste.dataset.jitaBound = '1';
    let previewed = '';
    const say = text => { if (summary) summary.textContent = text; };
    const show = html => { if (summary) summary.innerHTML = html; };
    const syncAccess = () => {
      const allowed = importAllowed();
      preview.disabled = !allowed;
      if (!allowed) apply.disabled = true;
      if (access) access.textContent = allowed ? 'Importer or administrator. Preview, then confirm.' : 'Importer or administrator access is required.';
    };
    paste.addEventListener('input', () => { previewed = ''; apply.disabled = true; show(EMPTY_UPLOAD); });
    preview.addEventListener('click', () => run(true));
    apply.addEventListener('click', () => run(false));
    clear.addEventListener('click', () => {
      paste.value = '';
      previewed = '';
      apply.disabled = true;
      show(EMPTY_UPLOAD);
    });
    async function run(dry) {
      syncAccess();
      if (!importAllowed()) { say('Importer or administrator access is required.'); return; }
      const text = paste.value;
      if (!dry && text !== previewed) { say('Preview the paste first.'); apply.disabled = true; return; }
      preview.disabled = true;
      apply.disabled = true;
      say(dry ? 'Checking…' : 'Saving…');
      try {
        const result = await rpc(IMPORT_RPC, { p_text: text, p_dry_run: dry });
        if (result.missing) { say('Sign in on the staging board first. Nothing was saved.'); return; }
        if (result.status === 404) { say('JITA upload is not on this database yet. Nothing was saved.'); return; }
        const payload = result.payload || {};
        const forbidden = result.status === 401 || result.status === 403 || payload.code === '42501' || /PDC_JITA_ETA_FORBIDDEN/.test(payload.message || '');
        if (forbidden) { say('Importer or administrator access is required.'); return; }
        if (!result.ok || payload.ok === false) {
          const message = payload.message || (dry ? 'Could not preview. Nothing was saved.' : 'Could not save the JITA ETA. Nothing was saved.');
          show(`<div class="summary-row error" role="alert"><strong>JITA upload needs attention</strong><span>${esc(message)}</span></div>`);
          return;
        }
        show(renderUploadResult(payload));
        if (dry) { previewed = text; apply.disabled = false; }
        else { previewed = ''; await loadBoard(); }
      } catch (_) {
        say(dry ? 'Could not preview. Nothing was saved.' : 'Could not save the JITA ETA. Nothing was saved.');
      } finally {
        syncAccess();
        if (!dry) apply.disabled = true;
      }
    }
    syncAccess();
    show(EMPTY_UPLOAD);
    let tries = 0;
    const accessTimer = setInterval(() => { syncAccess(); if (++tries > 15) clearInterval(accessTimer); }, 2000);
  }

  const style = document.createElement('style');
  style.textContent = '.pdc-jita-eta-cell{white-space:nowrap;font-weight:650;color:#166534}'
    + '.pdc-jita-eta-in-parts{margin-top:6px;padding-top:6px;border-top:1px solid #bbf7d0}'
    + '.pdc-jita-eta-in-parts b{display:block;font-size:11px;font-weight:750;color:#166534;letter-spacing:.01em}'
    + '.pdc-jita-eta-in-parts span{display:block;font-weight:650;color:#166534}'
    + '.pdc-parts-eta-detail .pdc-jita-eta-in-parts{grid-column:1/-1}'
    + '.pdc-jita-eta-only{grid-column:1/-1}'
    + 'td.c-eta:has(.pdc-jita-eta-in-parts){height:auto;max-height:none;overflow:visible;white-space:normal}'
    + 'td.c-eta .pdc-jita-eta-in-parts{margin-top:2px !important;padding-top:2px}'
    + 'td.c-eta .vlt-subtle-dash[hidden]{display:none}'
    + '#jita-upload-summary{margin-top:12px;display:grid;gap:10px}'
    + '#jita-upload-summary .scot-summary-grid{grid-template-columns:repeat(3,minmax(0,1fr))}'
    + '#jita-upload-summary .navision-import-success{margin:0}';
  document.head.appendChild(style);
  function watchLocations() {
    const host = document.getElementById('vlt-table-host');
    if (!host || host.dataset.jitaWatch) return;
    host.dataset.jitaWatch = '1';
    new MutationObserver(() => decorateLocationsTable()).observe(host, { childList: true, subtree: true });
    decorateLocationsTable();
  }
  hookParts();
  bindUpload();
  watchLocations();
  const ready = setInterval(() => {
    hookParts();
    bindUpload();
    watchLocations();
    if (hooked && document.getElementById('jita-paste')?.dataset.jitaBound) clearInterval(ready);
  }, 500);
  const locationsReady = setInterval(() => {
    watchLocations();
    if (document.getElementById('vlt-table-host')?.dataset.jitaWatch) clearInterval(locationsReady);
  }, 1000);
  loadBoard();
  setInterval(loadBoard, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') loadBoard(); });
  window.PDC_JITA_ETA = Object.freeze({ VERSION, parseJitaEta, reload: loadBoard });
})();
