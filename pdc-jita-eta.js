/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r512 (F128): JITA ETA from a daily Revolution paste under Navision Uploads.
 * One date per stock: the latest JITA Planned Delivery Date on a row with Qty Outstanding > 0,
 * otherwise the latest planned date on any row. Previous ETA, Latest ETA, Manual ETA and
 * Vehicle ETA at Kewdale are not read. This is not the email Parts ETA. */
(() => {
  'use strict';
  const VERSION = '2026.10.23.r512';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const IMPORT_RPC = 'import_jita_eta_512';
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

  /** Same reduction as jita_eta_parse_512. Latest means the greatest calendar date. */
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

  function chipHtml(entry) {
    const date = iso(entry && entry.eta_date);
    if (!date) return '';
    const label = `JITA ETA ${ddmmyyyy(date)}`;
    return `<span class="pdc-jita-eta" title="${esc(label)}" aria-label="${esc(label)}" data-jita-eta="${esc(date)}"><span class="pdc-jita-eta-k">JITA ETA </span>${esc(ddmmyyyy(date))}</span>`;
  }

  /** Place the JITA chip after the email Parts ETA chip, never inside it. */
  function insertChip(html, entry) {
    const chip = chipHtml(entry);
    if (!chip || typeof html !== 'string' || html.includes('class="pdc-jita-eta"')) return html;
    if (PARTS_CHIP.test(html)) return html.replace(PARTS_CHIP, match => match + chip);
    const location = /(<span class="tune-parts-location"[^>]*>[\s\S]*?<\/span>)/;
    if (location.test(html)) return html.replace(location, (_, loc) => loc + chip);
    return html.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)/, (_, start) => `${start}${chip}`);
  }

  function detailHtml(entry) {
    const date = iso(entry && entry.eta_date);
    if (!date) return '';
    return `<div class="tune-service-location-job pdc-jita-eta-detail"><b>JITA ETA</b><span>${esc(ddmmyyyy(date))}</span><small>From the JITA paste</small></div>`;
  }

  function insertDetail(html, entry) {
    const block = detailHtml(entry);
    if (!block || typeof html !== 'string' || html.includes('pdc-jita-eta-detail')) return html;
    const partsDetail = /<div class="tune-service-location-job pdc-parts-eta-detail"[\s\S]*?<\/div>/;
    if (partsDetail.test(html)) return html.replace(partsDetail, match => match + block);
    if (html.includes('<div class="incoming-vehicle-detail-grid">')) {
      return html.replace('<div class="incoming-vehicle-detail-grid">', `<div class="incoming-vehicle-detail-grid">${block}`);
    }
    return html;
  }

  if (typeof module !== 'undefined') {
    module.exports = { parseJitaEta, parseDate, chipHtml, insertChip, detailHtml, insertDetail, ddmmyyyy, PARTS_CHIP, VERSION, IMPORT_RPC, BOARD_RPC };
  }
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_JITA_ETA_VERSION) return;
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
      return insertDetail(insertChip(html, entry), entry);
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
    } catch (_) { /* keep the last dates */ }
    finally { loading = false; }
  }

  function importAllowed() {
    if (typeof navisionSharedImportRoleAllowed === 'function') return navisionSharedImportRoleAllowed() === true;
    const role = String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
    return role === 'importer' || role === 'administrator';
  }

  function summaryFrom(result) {
    const base = result?.message || (result?.dry_run ? 'Preview only. Nothing saved.' : 'Saved.');
    const rows = Array.isArray(result?.results) ? result.results : [];
    const unknown = rows.filter(row => row.status === 'skipped_unknown').map(row => row.stock);
    const ambiguous = rows.filter(row => row.status === 'ambiguous').map(row => row.stock);
    const bits = [base];
    if (unknown.length) bits.push(`Not on the board: ${unknown.slice(0, 8).join(', ')}${unknown.length > 8 ? '…' : ''}.`);
    if (ambiguous.length) bits.push(`More than one vehicle: ${ambiguous.slice(0, 8).join(', ')}.`);
    return bits.join(' ');
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
    const syncAccess = () => {
      const allowed = importAllowed();
      preview.disabled = !allowed;
      if (!allowed) apply.disabled = true;
      if (access) access.textContent = allowed ? 'Importer or administrator. Preview, then confirm.' : 'Importer or administrator access is required.';
    };
    paste.addEventListener('input', () => { previewed = ''; apply.disabled = true; });
    preview.addEventListener('click', () => run(true));
    apply.addEventListener('click', () => run(false));
    clear.addEventListener('click', () => {
      paste.value = '';
      previewed = '';
      apply.disabled = true;
      say('');
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
          say(payload.message || (dry ? 'Could not preview. Nothing was saved.' : 'Could not save the JITA ETA. Nothing was saved.'));
          return;
        }
        say(summaryFrom(payload));
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
    let tries = 0;
    const accessTimer = setInterval(() => { syncAccess(); if (++tries > 15) clearInterval(accessTimer); }, 2000);
  }

  const style = document.createElement('style');
  style.textContent = '.pdc-jita-eta{font-size:10.5px;font-weight:650;line-height:1.2;white-space:nowrap;padding:1px 5px;border-radius:4px;background:#dcfce7;color:#166534}'
    + '.pdc-jita-eta-detail{grid-column:1/-1}.pdc-jita-eta-detail span{display:block;font-weight:650}'
    + '.pdc-jita-eta-detail small{display:block;color:#475569}'
    + '.pdc-jita-eta-cell{white-space:nowrap;font-weight:650;color:#166534}'
    + '#jita-upload-summary{margin-top:8px;white-space:pre-wrap}';
  document.head.appendChild(style);
  hookParts();
  bindUpload();
  const ready = setInterval(() => {
    hookParts();
    bindUpload();
    if (hooked && document.getElementById('jita-paste')?.dataset.jitaBound) clearInterval(ready);
  }, 500);
  loadBoard();
  setInterval(loadBoard, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') loadBoard(); });
  window.PDC_JITA_ETA = Object.freeze({ VERSION, parseJitaEta, reload: loadBoard });
})();
