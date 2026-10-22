/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r461 (F74): Vehicle Locations "Table view" — a switchable, compact table in the Sales dashboard style.
 *
 * - Default is today's "Drop-down view". Nobody sees the table unless they switch; the choice is remembered per
 *   signed-in user on this device (localStorage, key pdc.vehicle-locations-view.v1:<user id>).
 * - Drawn once: in Table view the drop-down board is not rendered at all (renderIncomingDashboardBoard is wrapped).
 * - Every station cell, badge, button and identity value is the exact HTML that the board's own
 *   incomingVehicleDetailRow() produced for the drop-down view (including every module that wraps it: parts/JITA,
 *   sublet PO, service locations, parts ETA, key number). This file only splits that HTML into table cells; it never
 *   re-implements a state, symbol, colour or tooltip. test_vehicle_locations_table_461.js checks that cell by cell.
 * - Tiles in Craig's journey order (All, Other, IT, Yard Hold, Non-Navision, PMB, QC, PIT, RFT, STOPPAGES) filter the
 *   table; clicking a row opens the vehicle in a side panel (the existing drop-down card, opened, with its Open button).
 * - Selected tile, search, scroll and the open vehicle survive live refreshes.
 * Undo: revert the PR. With the PR in place, "Drop-down view" restores today's board for that user.
 *
 * r462 (F75), Table view only:
 * - "Loc." column replaced by "Parts loc": the exact parts-location span the card shows ("Parts location: 05E2A",
 *   pdc-service-locations.js), moved out of the Vehicle cell into its own cell; "—" when there is none. The column
 *   sorts (table-only sort, missing values last) and the search box also matches it.
 * - Columns resize by dragging a header edge (or arrow keys on the edge). Widths are saved per signed-in user on this
 *   device (key pdc.vehicle-locations-columns.v1:<user id>), like the view switch. "Reset columns" clears them. The
 *   station column never goes below its default width, so station cells keep their size, symbols and colours.
 * - setDrawerOpener() lets pdc-vehicle-slideout.js take over "open this vehicle" (the slide-out panel).
 *
 * r476 (F89), Table view only, display only (Craig 22 Oct 10:56): columns are bunched up.
 * - Columns whose content never grows have tight fixed default widths: Key 42, Stock 82, Job Card 78, Parts loc 60,
 *   Stations 276 (9 x 27 px cells + 8 x 3 px gaps + padding) and Age / ETA 72. Before, every column (fixed ones too)
 *   was stretched in proportion to fill a wide screen (table-layout: fixed spreads spare width over all columns).
 * - Customer, Vehicle, Status and Booking flex: they start at a base width and share the spare width by weight
 *   (layoutWidths(), recomputed when the table area changes size). A width someone drags on a flex column fixes it.
 * - The first column is the drop-down card's own multi-select checkbox cell (.incoming-card-select). It is only a
 *   checkbox for an editable vehicle; read-only email / Navision vehicles get an empty placeholder, which is the blank
 *   gap Craig marked. The column now takes 0 px when no row on screen has a checkbox, and 22 px when one does.
 * - Station headings use a 7.5 px label and "Parts Jita" sits on one line, so it fits its 27 px column.
 * - Saved widths move to key pdc.vehicle-locations-columns.v2:<user id>, so r462-era saved widths (often the stretched
 *   widths of a wide screen) do not hide the new defaults. v1 values are left on the device untouched, so undoing r476
 *   brings them back. "Reset columns" clears the v2 widths and restores these defaults.
 *
 * r475 (F88, Craig 22 Oct 10:51), Table view only: a compact "Parts ETA" column after "Parts loc". It is the card's own
 * parts ETA chip (pdc-parts-eta.js: "dd/mm · N days", amber "today", red "N days overdue", hover = the source email),
 * moved out of the Vehicle cell verbatim like the parts location; "—" when there is none. Resizable like the others.
 */
(function vehicleLocationsTableModule(root) {
  'use strict';
  const VERSION = '2026.10.22.r475'; // r476 (F89) widths, then r475 (F88) Parts ETA column (cache-busts this module)
  const STORAGE_PREFIX = 'pdc.vehicle-locations-view.v1:';
  const VIEWS = Object.freeze({ dropdown: 'dropdown', table: 'table' });
  // Vehicle journey, left to right (Craig, 22 Oct 2026).
  const JOURNEY = Object.freeze(['overseas', 'transit', 'yardhold', 'nonnavision', 'pmb', 'qc', 'pit', 'rft']);
  const TILE = Object.freeze({
    overseas: ['Other', 'All other active', 'unknown', 'OTHER'],
    transit: ['In transit (IT)', 'To WA / Kewdale', 'transit-it', 'IT'],
    yardhold: ['Yard Hold', 'Release to PMB', 'yardhold', 'YH'],
    nonnavision: ['Non-Navision', 'No Navision updates', 'unconfirmed', 'NON-NAV'],
    pmb: ['PMB', 'Work still active', 'transit', 'PMB'],
    qc: ['QC', 'Awaiting QC sign-off', 'hold', 'QC'],
    pit: ['PIT', 'Dept of Transport', 'production', 'PIT'],
    rft: ['RFT', 'Ready for transport', 'released', 'RFT'],
  });
  const STOPPAGES = '__stoppages';
  // r462: resizable columns. Defaults equal the r461 widths in pdc-vehicle-locations-table.css (CSS variables there
  // fall back to these numbers). The station column's minimum is its default, so the strip is never squeezed.
  // r476 (F89): v2 key and tight defaults; flex columns carry a weight for the spare width (their width is the base).
  const COLUMN_STORAGE_PREFIX = 'pdc.vehicle-locations-columns.v2:';
  const COLUMNS = Object.freeze({
    key: { label: 'Key', width: 42, min: 30 },
    stock: { label: 'Stock', width: 82, min: 56 },
    job: { label: 'Job Card', width: 78, min: 64 }, // r463 (F76): the job card in its own column
    cust: { label: 'Customer', width: 104, min: 48, flex: 1 },
    unit: { label: 'Vehicle', width: 112, min: 60, flex: 1 },
    ploc: { label: 'Parts loc', width: 60, min: 44 },
    eta: { label: 'Parts ETA', width: 96, min: 56 }, // r475 (F88)
    work: { label: 'Stations', width: 276, min: 276 },
    age: { label: 'Age / ETA', width: 72, min: 48 },
    status: { label: 'Status', width: 112, min: 56, flex: 1.2 },
    action: { label: 'Booking', width: 160, min: 72, flex: 0.4 },
  });
  const COLUMN_MAX = 520;
  const SEL_WIDTH = 22; // r476: only when a row on screen has a select checkbox; otherwise 0

  // ---------- Pure helpers (also used by the Node tests) ----------
  const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
  function tagEnd(html, start) {
    let quote = '';
    for (let i = start + 1; i < html.length; i += 1) {
      const c = html[i];
      if (quote) { if (c === quote) quote = ''; } else if (c === '"' || c === "'") quote = c; else if (c === '>') return i + 1;
    }
    return html.length;
  }
  // Top-level elements of an HTML fragment, in order, each with its exact outer HTML (text between them is dropped).
  function topLevelElements(html = '') {
    const out = [];
    let depth = 0; let start = -1; let tag = ''; let open = ''; let i = 0;
    while (i < html.length) {
      const lt = html.indexOf('<', i);
      if (lt < 0) break;
      if (html.startsWith('<!--', lt)) { const e = html.indexOf('-->', lt + 4); i = e < 0 ? html.length : e + 3; continue; }
      const end = tagEnd(html, lt);
      const raw = html.slice(lt, end);
      const m = /^<\/?\s*([a-zA-Z][\w:-]*)/.exec(raw);
      if (!m) { i = end; continue; }
      const name = m[1].toLowerCase();
      if (raw[1] === '/') {
        depth -= 1;
        if (depth === 0 && start >= 0) { out.push({ tag, open, html: html.slice(start, end), inner: html.slice(start + open.length, lt) }); start = -1; }
        if (depth < 0) depth = 0;
      } else if (VOID.has(name) || /\/\s*>$/.test(raw)) {
        if (depth === 0) out.push({ tag: name, open: raw, html: raw, inner: '' });
      } else {
        if (depth === 0) { start = lt; tag = name; open = raw; }
        depth += 1;
      }
      i = end;
    }
    return out;
  }
  const attrOf = (open, name) => { const m = new RegExp(`\\s${name}\\s*=\\s*"([^"]*)"`).exec(open || ''); return m ? m[1] : ''; };
  const classesOf = element => attrOf(element?.open, 'class').split(/\s+/).filter(Boolean);
  const hasClass = (element, name) => classesOf(element).includes(name);

  // Split one drop-down card (incomingVehicleDetailRow output) into the pieces the table shows. Nothing is rewritten.
  function splitCard(cardHtml = '') {
    const card = topLevelElements(cardHtml).find(el => el.tag === 'details') || null;
    const summary = card ? topLevelElements(card.inner).find(el => el.tag === 'summary') : null;
    const parts = topLevelElements(summary?.inner || '');
    const pick = name => parts.find(el => hasClass(el, name)) || null;
    const stock = pick('incoming-card-stock');
    const stack = stock ? topLevelElements(stock.inner).find(el => hasClass(el, 'vehicle-identity-stack')) : null;
    const identity = stack ? topLevelElements(stack.inner) : [];
    const cell = name => identity.find(el => hasClass(el, name)) || null;
    return {
      ok: Boolean(card && summary),
      cardClass: classesOf(card),
      rowKey: attrOf(card?.open, 'data-incoming-row'),
      select: pick('incoming-card-select'),
      stock,
      identityTitle: attrOf(stack?.open, 'title'),
      key: cell('identity-key'), stockNo: cell('identity-stock'), job: cell('identity-jc'), name: cell('identity-name'),
      unit: pick('incoming-card-main'),
      work: pick('incoming-card-work-wrap'),
      rft: pick('rft-row-controls-slot'),
      age: pick('incoming-card-age'),
      status: pick('incoming-card-status'),
      action: pick('incoming-card-action'),
    };
  }

  const escapeText = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const html = element => element?.html || '';
  const isBlank = element => !element || !element.inner.replace(/<[^>]*>/g, '').trim() && !/<(button|select|input|img)\b/i.test(element.inner);

  // One table row from one drop-down card. Station strip / RFT controls / badges / buttons are copied verbatim.
  function tableRowHtml(cardHtml, bucket, { key = '', openKey = '', bucketLabel = '' } = {}) {
    const p = splitCard(cardHtml);
    const rowKey = key || p.rowKey;
    const tile = TILE[bucket] || [bucket, '', 'unknown', String(bucket || '').toUpperCase()];
    const classes = ['vlt-row', `vlt-${bucket}`];
    if (p.cardClass.includes('is-selected')) classes.push('selected');
    if (p.cardClass.includes('has-parts-risk')) classes.push('has-parts-risk');
    if (rowKey && rowKey === openKey) classes.push('is-open');
    const td = (cls, inner, extra = '') => `<td class="${cls}"${extra}>${inner}</td>`;
    const identityFallback = !p.key && !p.stockNo; // unexpected identity markup: keep the whole stock span
    const parts = extractPartsLocation(html(p.unit));
    const ploc = parts.span || '<span class="vlt-subtle-dash" title="No parts location">—</span>';
    const eta = extractPartsEta(parts.unit); // r475: the parts ETA chip gets its own column
    const etaCell = eta.span || '<span class="vlt-subtle-dash" title="No parts ETA">—</span>';
    const rftSpan = p.rft && !p.work && [p.age, p.status, p.action].every(isBlank);
    const cells = [
      td('c-sel', html(p.select)),
      td('c-key', identityFallback ? '' : html(p.key)),
      td('c-stock', identityFallback ? html(p.stock) : html(p.stockNo)),
      td('c-job', identityFallback || !p.job ? '<span class="vlt-subtle-dash" title="No job card">—</span>' : html(p.job)),
      td('c-cust', html(p.name)),
      td('c-unit', eta.unit),
      td('c-ploc', ploc),
      td('c-eta', etaCell),
      td(`c-work${p.rft && !p.work ? ' is-rft' : ''}`, html(p.work || p.rft), rftSpan ? ' colspan="4"' : ''),
    ];
    if (!rftSpan) cells.push(td('c-age', html(p.age)), td('c-status', html(p.status)), td('c-action', html(p.action)));
    void tile; void bucketLabel;
    return `<tr class="${classes.join(' ')}" data-vlt-key="${escapeText(rowKey)}" data-vlt-bucket="${escapeText(bucket)}" data-vlt-parts-loc="${escapeText(parts.text)}" data-vlt-parts-eta="${escapeText(eta.eta)}" tabindex="0"${p.identityTitle ? ` aria-label="${escapeText(p.identityTitle)}"` : ''}>${cells.join('')}</tr>`;
  }

  // r462: the card's own parts-location span (pdc-service-locations.js puts it inside .incoming-card-main), lifted out
  // verbatim. Returns the Vehicle cell without it, the span, and its text for sorting.
  const PARTS_SPAN = /<span class="tune-parts-location"[^>]*>([^<]*)<\/span>/;
  function extractPartsLocation(unitHtml = '') {
    const m = PARTS_SPAN.exec(unitHtml);
    if (!m) return { unit: unitHtml, span: '', text: '' };
    const text = m[1].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();
    return { unit: unitHtml.replace(m[0], ''), span: m[0], text };
  }
  // r475: the parts ETA chip (pdc-parts-eta.js chipHtml, r436 or r475 markup) lifted out of the Vehicle cell verbatim; the
  // wrapper it sat in is dropped once empty. Returns the Vehicle cell without it, the chip, and its ISO date.
  const ETA_CHIP = /<span class="pdc-parts-eta pdc-parts-eta-(?:ok|due|overdue)"[^>]*>(?:<span class="pdc-parts-eta-k">[^<]*<\/span>)?[^<]*<\/span>/;
  function extractPartsEta(unitHtml = '') {
    const m = ETA_CHIP.exec(unitHtml);
    if (!m) return { unit: unitHtml, span: '', eta: '' };
    const unit = unitHtml.replace(m[0], '').replace(/<span class="pdc-parts-eta-wrap">\s*<\/span>/, '');
    return { unit, span: m[0], eta: attrOf(m[0], 'data-parts-eta') };
  }
  // Table-only parts-location sort: text order (natural, so 05E2A < 12B1), missing values last in both directions.
  function comparePartsLocation(a = '', b = '', direction = 'asc') {
    if (!a && !b) return 0;
    if (!a) return 1;
    if (!b) return -1;
    const order = String(a).localeCompare(String(b), 'en', { numeric: true, sensitivity: 'base' });
    return direction === 'desc' ? -order : order;
  }

  // ---- r462 column widths ----
  function columnStorageKey(userId) { return `${COLUMN_STORAGE_PREFIX}${String(userId || 'signed-out')}`; }
  const clampWidth = (key, px) => Math.round(Math.min(COLUMN_MAX, Math.max(COLUMNS[key].min, Number(px))));
  // Only known columns with finite numbers survive; everything is clamped to [min, max].
  function sanitizeWidths(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object') return out;
    Object.keys(COLUMNS).forEach(key => { const n = Number(raw[key]); if (Number.isFinite(n) && n > 0) out[key] = clampWidth(key, n); });
    return out;
  }
  function readWidths(storage, userId) {
    try { return sanitizeWidths(JSON.parse(storage?.getItem(columnStorageKey(userId)) || 'null')); } catch (_) { return {}; }
  }
  function writeWidths(storage, userId, widths) {
    const clean = sanitizeWidths(widths);
    try {
      if (Object.keys(clean).length) storage?.setItem(columnStorageKey(userId), JSON.stringify(clean));
      else storage?.removeItem(columnStorageKey(userId));
      return true;
    } catch (_) { return false; }
  }
  function resetWidths(storage, userId) { try { storage?.removeItem(columnStorageKey(userId)); return true; } catch (_) { return false; } }
  // r476: every column's width for a table area `available` px wide. Fixed columns (and any column with a saved width)
  // keep their px; flex columns without a saved width get their base plus a weighted share of what is left. Columns in
  // `hidden` (e.g. Status on a narrow iPad screen) take no width. `min` is the narrowest the table may be.
  function layoutWidths(widths = {}, { available = 0, select = false, hidden = [] } = {}) {
    const clean = sanitizeWidths(widths);
    const sel = select ? SEL_WIDTH : 0;
    const cols = {}; const flex = {};
    Object.entries(COLUMNS).forEach(([key, col]) => {
      if (hidden.includes(key)) cols[key] = 0;
      else if (clean[key] != null) cols[key] = clean[key];
      else { cols[key] = col.width; if (col.flex) flex[key] = col.width; }
    });
    const min = sel + Object.values(cols).reduce((sum, px) => sum + px, 0);
    const spare = Math.max(0, Math.floor(Number(available) || 0) - min);
    const weight = Object.keys(flex).reduce((sum, key) => sum + COLUMNS[key].flex, 0);
    if (spare && weight) {
      let given = 0; const keys = Object.keys(flex);
      keys.forEach((key, index) => {
        const add = index === keys.length - 1 ? spare - given : Math.floor(spare * COLUMNS[key].flex / weight);
        given += add; cols[key] += add; flex[key] = cols[key];
      });
    }
    return { sel, cols, flex, min, total: sel + Object.values(cols).reduce((sum, px) => sum + px, 0) };
  }
  // CSS variables for the table: one per saved column, the flex widths, the select column, the pinned Key / Stock
  // offsets and the table's minimum width. No saved widths and no layout to apply: no inline style at all.
  function widthStyle(widths = {}, { available = 0, select = false, hidden = [] } = {}) {
    const clean = sanitizeWidths(widths);
    if (!Object.keys(clean).length && !available && !select) return '';
    const lay = layoutWidths(clean, { available, select, hidden });
    const vars = Object.keys(clean).map(key => `--vlt-w-${key}:${clean[key]}px`);
    Object.entries(lay.flex).forEach(([key, px]) => vars.push(`--vlt-flex-${key}:${px}px`));
    vars.push(`--vlt-w-sel:${lay.sel}px`, `--vlt-left-key:${lay.sel}px`, `--vlt-left-stock:${lay.sel + lay.cols.key}px`, `--vlt-table-min:${lay.min}px`);
    return vars.join(';');
  }

  // Bucket order for tiles and rows: Craig's journey first, then any bucket the board adds later (never dropped).
  function journeyOrder(defs = []) {
    const keys = defs.map(def => def.key);
    return [...JOURNEY.filter(key => keys.includes(key)), ...keys.filter(key => !JOURNEY.includes(key))];
  }

  function storageKey(userId) { return `${STORAGE_PREFIX}${String(userId || 'signed-out')}`; }
  function readView(storage, userId) {
    try { return storage?.getItem(storageKey(userId)) === VIEWS.table ? VIEWS.table : VIEWS.dropdown; } catch (_) { return VIEWS.dropdown; }
  }
  function writeView(storage, userId, view) {
    try { storage?.setItem(storageKey(userId), view === VIEWS.table ? VIEWS.table : VIEWS.dropdown); return true; } catch (_) { return false; }
  }

  const api = { VERSION, VIEWS, JOURNEY, TILE, STORAGE_PREFIX, topLevelElements, splitCard, tableRowHtml, journeyOrder, storageKey, readView, writeView,
    COLUMNS, COLUMN_MAX, COLUMN_STORAGE_PREFIX, SEL_WIDTH, extractPartsLocation, extractPartsEta, comparePartsLocation, columnStorageKey, sanitizeWidths, readWidths, writeWidths, resetWidths, widthStyle, layoutWidths };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (!root || !root.document || typeof root.renderIncomingDashboardBoard !== 'function' || root.PDC_VEHICLE_LOCATIONS_TABLE) {
    if (root && !root.PDC_VEHICLE_LOCATIONS_TABLE) root.PDC_VEHICLE_LOCATIONS_TABLE = api;
    return;
  }

  // ---------- Browser ----------
  const doc = root.document;
  const state = { bucket: '', stoppages: false, openKey: '', view: VIEWS.dropdown, partsSort: '', widths: {} };
  let drawerOpener = null; // r462: { open(key, bucket), refresh(key, bucket), close() } from pdc-vehicle-slideout.js
  const userId = () => root.PDC_AUTH_CONTEXT?.userId || '';
  const storage = () => { try { return root.localStorage; } catch (_) { return null; } };
  const originalRender = root.renderIncomingDashboardBoard;
  const tableOn = () => state.view === VIEWS.table;

  function loadStyles() {
    if (doc.querySelector('link[data-pdc-vehicle-locations-table]')) return;
    const link = doc.createElement('link');
    link.rel = 'stylesheet';
    link.href = `pdc-vehicle-locations-table.css?vehicle-locations-table=${VERSION}`;
    link.dataset.pdcVehicleLocationsTable = '1';
    doc.head.appendChild(link);
  }

  function switchHtml() {
    const button = (view, label) => `<button type="button" data-vlt-view="${view}" aria-pressed="${state.view === view}" class="${state.view === view ? 'is-active' : ''}">${label}</button>`;
    return `<span class="vlt-view-switch-label">View</span>${button(VIEWS.dropdown, 'Drop-down view')}${button(VIEWS.table, 'Table view')}`;
  }
  function ensureSwitch() {
    const panel = doc.querySelector('#dashboard .incoming-search-panel');
    if (!panel) return;
    let wrap = doc.getElementById('vlt-view-switch');
    if (!wrap) {
      wrap = doc.createElement('div');
      wrap.id = 'vlt-view-switch';
      wrap.className = 'vlt-view-switch';
      wrap.setAttribute('role', 'group');
      wrap.setAttribute('aria-label', 'Vehicle Locations view');
      wrap.addEventListener('click', event => {
        const button = event.target.closest?.('[data-vlt-view]');
        if (button) setView(button.dataset.vltView);
      });
      const summary = panel.querySelector('#incoming-filter-summary');
      if (summary) summary.after(wrap); else panel.appendChild(wrap);
    }
    wrap.innerHTML = switchHtml();
  }

  function setView(view, { save = true } = {}) {
    const next = view === VIEWS.table ? VIEWS.table : VIEWS.dropdown;
    if (save) writeView(storage(), userId(), next);
    if (next === state.view && save) { ensureSwitch(); return; }
    state.view = next;
    applyViewChrome();
    root.renderIncomingDashboardBoard();
  }

  function applyViewChrome() {
    doc.body.classList.toggle('vlt-table-on', tableOn());
    const board = doc.getElementById('incoming-main-board');
    const panel = doc.querySelector('#dashboard .incoming-search-panel');
    if (tableOn()) {
      if (board) { board.innerHTML = ''; board.hidden = true; }
      panel?.classList.add('vlt-slim-bar');
    } else {
      if (drawerOpener && state.openKey) drawerOpener.close();
      state.openKey = '';
      const host = doc.getElementById('vlt-table-host');
      if (host) host.remove();
      doc.getElementById('vlt-nav-status')?.remove();
      panel?.classList.remove('vlt-slim-bar');
      if (board) board.hidden = false;
    }
    ensureSwitch();
  }

  function navStatus() {
    const panel = doc.querySelector('#dashboard .incoming-search-panel');
    if (!panel) return;
    let nav = doc.getElementById('vlt-nav-status');
    if (!nav) { nav = doc.createElement('div'); nav.id = 'vlt-nav-status'; panel.appendChild(nav); }
    nav.innerHTML = root.sharedNavisionLocationsStatusHtml();
    nav.querySelectorAll('span, small, p').forEach(node => { if (!node.title && !node.children.length) node.title = node.textContent.trim(); });
  }

  function ensureHost() {
    let host = doc.getElementById('vlt-table-host');
    const board = doc.getElementById('incoming-main-board');
    if (!host && board) {
      host = doc.createElement('div');
      host.id = 'vlt-table-host';
      host.className = 'vlt-table-host';
      board.before(host);
    }
    return host;
  }

  // Full text of anything the compact layout may cut off stays available on hover.
  function addTooltips(scope) {
    scope.querySelectorAll('button, .vehicle-identity-value, .incoming-card-main strong, .incoming-card-meta > span').forEach(node => {
      if (node.closest('.pdc-station-strip')) return; // station cells keep exactly today's tooltip
      if (!node.getAttribute('title')) { const text = node.textContent.replace(/\s+/g, ' ').trim(); if (text) node.setAttribute('title', text); }
    });
  }

  function captureUi(host) {
    const drawer = host?.querySelector('#vlt-drawer');
    const active = doc.activeElement;
    return {
      tableScroll: host?.querySelector('.vlt-table-wrap')?.scrollTop || 0,
      drawerScroll: drawer?.querySelector('.vlt-drawer-body')?.scrollTop || 0,
      drawerOpenDetails: drawer ? [...drawer.querySelectorAll('.vlt-drawer-body details details')].map(d => d.open) : [],
      // Someone typing or choosing in the side panel keeps that panel as it is until they finish.
      keepDrawer: Boolean(drawer && !drawer.hidden && active && drawer.contains(active) && active.matches?.('input, textarea, select, [contenteditable="true"]')),
      drawerNode: drawer,
    };
  }

  function renderTable() {
    const host = ensureHost();
    if (!host) return;
    const ui = captureUi(host);
    const workshopProjectionAvailable = root.ensureDashboardWorkshopProjectionReady();
    const workshopPlans = workshopProjectionAvailable && typeof root.workshopLoadPlans === 'function' ? root.workshopLoadPlans() : null;
    const rows = root.vehicleLocationsScreenRows();
    const appState = app;
    // Same housekeeping as the drop-down render (renderIncomingDashboardBoardContent).
    if (!root.sharedNavisionLocationAuthorityReady() && appState.vehicleLocationsRefreshState !== 'refreshing') appState.selectedRows.clear();
    else [...appState.selectedRows].forEach(key => { if (appState.sharedNavisionLocationReadOnlyKeys?.has(key)) appState.selectedRows.delete(key); });
    root.updateIncomingDashboardFilterOptions(rows);
    const filters = root.incomingDashboardFilterValues();
    root.updateIncomingMoreFiltersState(filters);
    const sort = appState.incomingDashboardSort || {};
    const needle = String(filters.search || '').trim().toLowerCase();
    const searchless = needle ? { ...filters, search: '' } : null;
    const filteredRows = rows.filter(vehicle => root.incomingVehicleMatchesFilters(vehicle, filters)
      || (needle && partsLocationValues(vehicle).some(value => value.toLowerCase().includes(needle)) && root.incomingVehicleMatchesFilters(vehicle, searchless)));
    root.pruneIncomingDepartmentSelection(filteredRows);
    const loading = rows.length === 0 && appState.vehicleLocationsRefreshState !== 'success' && appState.vehicleLocationsRefreshState !== 'error'
      && (appState.vehicleLocationsRefreshState === 'refreshing' || appState.sharedNavisionVisibleState === 'loading'
        || (Boolean(root.PDC_AUTH_CONTEXT) && (appState.sharedNavisionVisibleState === 'idle' || appState.sharedNavisionVisibleState == null)));
    const defs = VEHICLE_LOCATION_BUCKET_DEFS;
    const order = journeyOrder(defs);
    const rank = new Map(order.map((key, index) => [key, index]));
    const priorityRows = root.incomingDepartmentPriorityRows(filters);
    const stoppageKeys = new Set(priorityRows.map(row => root.vehicleKey(row.vehicle)));
    const entries = filteredRows.map(vehicle => ({ vehicle, bucket: root.incomingBucketForVehicle(vehicle), key: root.vehicleKey(vehicle) }))
      .filter(entry => rank.has(entry.bucket) && (!filters.bucket || filters.bucket === entry.bucket));
    const counts = new Map();
    entries.forEach(entry => counts.set(entry.bucket, (counts.get(entry.bucket) || 0) + 1));
    if (state.bucket && !rank.has(state.bucket)) state.bucket = '';
    const cardFor = entry => root.incomingVehicleDetailRow(entry.vehicle, entry.bucket, { workshopPlans, workshopProjectionAvailable, subletNavigation: true });
    const shown = entries
      .filter(entry => (!state.bucket || entry.bucket === state.bucket) && (!state.stoppages || stoppageKeys.has(entry.key)))
      .map(entry => { const card = cardFor(entry); return { ...entry, card, partsLoc: extractPartsLocation(html(splitCard(card).unit)).text }; })
      .sort((a, b) => rank.get(a.bucket) - rank.get(b.bucket)
        || (state.partsSort ? comparePartsLocation(a.partsLoc, b.partsLoc, state.partsSort) : 0)
        || root.incomingCompareVehicles(a.vehicle, b.vehicle, sort, a.bucket));
    const summary = doc.getElementById('incoming-filter-summary');
    if (summary) {
      const workCount = Array.isArray(filters.work) ? filters.work.length : (filters.work ? 1 : 0);
      const active = [filters.department && `Department ${filters.department}`, filters.search && `search “${filters.search}”`, filters.status,
        filters.bucket && root.incomingBucketLabel(filters.bucket), filters.rep, workCount && `${workCount} work type${workCount === 1 ? '' : 's'}`,
        state.bucket && `${TILE[state.bucket]?.[0] || state.bucket} tile`, state.stoppages && 'STOPPAGES tile'].filter(Boolean);
      summary.textContent = loading ? 'Loading vehicles…' : `${shown.length} of ${rows.length} vehicles shown${active.length ? ` · ${active.join(' · ')}` : ''}`;
    }
    const esc = value => root.escapeHtml(String(value ?? ''));
    const tile = (key, label, count, caption, tone, active, title) => `<button type="button" class="vlt-tile ${esc(tone)}${active ? ' active' : ''}" data-vlt-tile="${esc(key)}" aria-pressed="${active}" title="${esc(title || caption)}"><span>${esc(label)}</span><strong>${loading ? '…' : count}</strong><small>${esc(caption)}</small></button>`;
    const defFor = key => defs.find(def => def.key === key) || {};
    const tilesHtml = `<div class="vlt-tiles" role="toolbar" aria-label="Filter Vehicle Locations by location">${
      tile('', 'All vehicles', entries.length, 'Every active vehicle', 'all', !state.bucket && !state.stoppages, 'Show every vehicle')}${
      order.map(key => tile(key, TILE[key]?.[0] || defFor(key).label || key, counts.get(key) || 0, TILE[key]?.[1] || '', TILE[key]?.[2] || 'unknown', state.bucket === key, defFor(key).hint)).join('')}${
      tile(STOPPAGES, 'STOPPAGES', priorityRows.length, 'Fix first', 'stoppage', state.stoppages, 'STOPPAGES / Fix First — the same list as the drop-down view')}</div>`;
    const headingSort = state.partsSort ? {} : sort; // only one column shows as sorted
    const heading = (label, key) => root.incomingSortHeadingHtml(label, key, headingSort);
    const partsNext = state.partsSort === 'asc' ? 'desc' : 'asc';
    const partsHeading = `<button type="button" class="incoming-sort-heading${state.partsSort ? ' is-active' : ''}" data-vlt-sort="parts-location" aria-label="Sort Parts loc: ${partsNext === 'asc' ? 'ascending' : 'descending'}" title="Sort Parts loc: ${partsNext === 'asc' ? 'ascending' : 'descending'}. Missing values stay last.">Parts loc <span aria-hidden="true">${state.partsSort === 'asc' ? '↑' : state.partsSort === 'desc' ? '↓' : '↕'}</span></button>`;
    const grip = key => `<span class="vlt-col-resize" data-vlt-resize="${key}" role="separator" aria-orientation="vertical" tabindex="0" aria-label="Resize ${esc(COLUMNS[key].label)} column (arrow keys)" title="Drag to resize · double-click to reset this column"></span>`;
    const filterNote = state.bucket ? `${esc(TILE[state.bucket]?.[0] || state.bucket)} only · click All vehicles to clear`
      : state.stoppages ? 'STOPPAGES only · click All vehicles to clear' : 'Click a tile to filter · click a vehicle to open it';
    const bodyHtml = shown.map(entry => tableRowHtml(entry.card,
      entry.bucket, { key: entry.key, openKey: state.openKey, bucketLabel: root.incomingBucketLabel(entry.bucket) })).join('')
      || `<tr><td colspan="12" class="vlt-empty">${loading ? 'Loading vehicles…' : 'No vehicles match this tile and the search filters'}</td></tr>`;
    const keepDrawer = !drawerOpener && ui.keepDrawer && state.openKey && shown.some(entry => entry.key === state.openKey) ? ui.drawerNode : null;
    host.innerHTML = `${tilesHtml}
      <section class="vlt-panel" aria-label="Vehicle locations table">
        <div class="vlt-panel-header"><h2>Vehicle locations</h2><p>${filterNote}</p>${root.workStatusLegendHtml()}<button type="button" class="vlt-reset-cols" data-vlt-reset-cols${Object.keys(state.widths).length ? '' : ' disabled'} title="Put every column back to its standard width">Reset columns</button></div>
        <div class="vlt-table-wrap"><table class="vlt-table${Object.keys(state.widths).length ? ' has-custom-widths' : ''}${/data-select-stock/.test(bodyHtml) ? ' has-select' : ''}">
          <colgroup><col class="c-sel"><col class="c-key"><col class="c-stock"><col class="c-job"><col class="c-cust"><col class="c-unit"><col class="c-ploc"><col class="c-eta"><col class="c-work"><col class="c-age"><col class="c-status"><col class="c-action"></colgroup>
          <thead><tr><th class="c-sel"></th><th class="c-key">${heading('Key', 'key')}${grip('key')}</th><th class="c-stock">${heading('Stock', 'stock')}${grip('stock')}</th><th class="c-job">${heading('Job Card', 'jobcard')}${grip('job')}</th><th class="c-cust">${heading('Customer', 'customer')}${grip('cust')}</th><th class="c-unit">${heading('Vehicle', 'vehicle')}${grip('unit')}</th><th class="c-ploc">${partsHeading}${grip('ploc')}</th><th class="c-eta"><span title="Parts ETA from parts staff emails (Perth dates). Hover a date for the source email.">Parts ETA</span>${grip('eta')}</th><th class="c-work">${grip('work')}</th><th class="c-age">${heading('Age / ETA', 'age')}${grip('age')}</th><th class="c-status">Status${grip('status')}</th><th class="c-action">Booking${grip('action')}</th></tr></thead>
          <tbody>${bodyHtml}</tbody></table></div>
      </section>`;
    const holder = doc.createElement('div');
    holder.innerHTML = root.productionGridHeaderHtml('incoming-production-grid-header', { actionLabel: 'Booking', incomingSort: sort });
    const stations = holder.querySelector('.pdc-grid-stations-heading');
    if (stations) host.querySelector('thead th.c-work').append(stations);
    applyWidths(host); // r476: flex / select-column widths for this screen, before the first paint
    observeHostWidth(host);
    if (keepDrawer) host.append(keepDrawer);
    else if (!drawerOpener) host.insertAdjacentHTML('beforeend', '<aside class="vlt-drawer" id="vlt-drawer" hidden aria-label="Vehicle detail"></aside>');
    const body = host.querySelector('tbody');
    addTooltips(body);
    bindBoardHandlers(body);
    bindTableEvents(host, sort);
    navStatus();
    const wrap = host.querySelector('.vlt-table-wrap');
    if (wrap) wrap.scrollTop = ui.tableScroll;
    if (state.openKey && !keepDrawer) {
      const open = shown.find(entry => entry.key === state.openKey) || entries.find(entry => entry.key === state.openKey);
      if (open && drawerOpener) drawerOpener.refresh(open.key, open.bucket);
      else if (open) openDrawer(open.key, open.bucket, ui); else closeDrawer();
    }
    revealSingleResult(shown, filters.search);
    root.updateInlineSelectionBars(filteredRows);
    root.updateCollapseToggleButtons?.();
    if (appState.vehicleLocationsRefreshState !== 'refreshing') appState.vehicleLocationsRefreshDisclosure = null;
    root.ensureOperationalRefreshControls?.();
  }

  // Search narrowing to one vehicle opens it once (the drop-down view opens and scrolls to it the same way).
  function revealSingleResult(shown, query) {
    const needle = String(query || '').trim().toLowerCase();
    const focus = app.singleSearchFocus || (app.singleSearchFocus = {});
    if (!needle || shown.length !== 1) { focus['incoming-table'] = ''; return; }
    const token = `${needle}|${shown[0].key}`;
    if (focus['incoming-table'] === token) return;
    focus['incoming-table'] = token;
    openVehicle(shown[0].key, shown[0].bucket);
  }

  function bindTableEvents(host, sort) {
    host.querySelectorAll('[data-vlt-tile]').forEach(button => button.addEventListener('click', () => {
      const key = button.dataset.vltTile;
      if (key === STOPPAGES) { state.stoppages = !state.stoppages; state.bucket = ''; } else { state.stoppages = false; state.bucket = state.bucket === key ? '' : key; }
      const wrap = host.querySelector('.vlt-table-wrap');
      if (wrap) wrap.scrollTop = 0;
      renderTable();
    }));
    host.querySelectorAll('thead [data-incoming-sort]').forEach(button => button.addEventListener('click', event => {
      event.preventDefault(); event.stopPropagation();
      const key = button.dataset.incomingSort;
      const wasParts = Boolean(state.partsSort);
      state.partsSort = '';
      app.incomingDashboardSort = { key, direction: !wasParts && sort.key === key && sort.direction === 'asc' ? 'desc' : 'asc' };
      renderTable();
      [...host.querySelectorAll('thead [data-incoming-sort]')].find(control => control.dataset.incomingSort === key)?.focus({ preventScroll: true });
    }));
    host.querySelector('thead [data-vlt-sort="parts-location"]')?.addEventListener('click', event => {
      event.preventDefault(); event.stopPropagation();
      state.partsSort = state.partsSort === 'asc' ? 'desc' : 'asc';
      renderTable();
      host.querySelector('thead [data-vlt-sort="parts-location"]')?.focus({ preventScroll: true });
    });
    host.querySelector('[data-vlt-reset-cols]')?.addEventListener('click', event => { event.preventDefault(); resetColumns(); });
    bindColumnResize(host);
    const body = host.querySelector('tbody');
    body.addEventListener('click', event => {
      if (event.target.closest('button, a, input, select, label, textarea, summary, [role="button"]')) return;
      const tr = event.target.closest('tr[data-vlt-key]');
      if (tr) openVehicle(tr.dataset.vltKey, tr.dataset.vltBucket);
    });
    body.addEventListener('keydown', event => {
      const tr = event.target.closest?.('tr[data-vlt-key]');
      if (tr && event.target === tr && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); openVehicle(tr.dataset.vltKey, tr.dataset.vltBucket); }
    });
    body.addEventListener('change', event => {
      const input = event.target.closest?.('[data-select-stock]');
      if (input) input.closest('tr')?.classList.toggle('selected', input.checked);
    });
  }

  // ---- r462: column resize (pointer drag on a header edge, arrow keys on the focused edge, double-click resets it) ----
  function applyWidths(host) {
    const table = host?.querySelector('.vlt-table');
    if (!table) return;
    const wrap = host.querySelector('.vlt-table-wrap');
    const statusTh = table.querySelector('thead th.c-status');
    const hidden = statusTh && root.getComputedStyle?.(statusTh).display === 'none' ? ['status'] : [];
    const css = widthStyle(state.widths, { available: wrap?.clientWidth || 0, select: table.classList.contains('has-select'), hidden });
    table.setAttribute('style', css);
    if (!css) table.removeAttribute('style');
    table.classList.toggle('has-custom-widths', Boolean(Object.keys(state.widths).length));
    lastLayoutWidth = wrap?.clientWidth || 0;
    const reset = host.querySelector('[data-vlt-reset-cols]');
    if (reset) reset.disabled = !Object.keys(state.widths).length;
  }
  // r476: flex widths follow the table area (window resize, side menu, scrollbar); only a real width change re-applies.
  let lastLayoutWidth = 0; let observedHost = null;
  function observeHostWidth(host) {
    if (!host || observedHost === host) return;
    observedHost = host;
    const recheck = () => { const wrap = host.querySelector('.vlt-table-wrap'); if (tableOn() && wrap && wrap.clientWidth !== lastLayoutWidth) applyWidths(host); };
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(recheck).observe(host);
    else root.addEventListener?.('resize', recheck);
  }
  function saveWidths() { writeWidths(storage(), userId(), state.widths); }
  function setColumnWidth(key, px, { save = true } = {}) {
    if (!COLUMNS[key]) return;
    state.widths = { ...state.widths, [key]: clampWidth(key, px) };
    applyWidths(doc.getElementById('vlt-table-host'));
    if (save) saveWidths();
  }
  function resetColumns() {
    state.widths = {};
    resetWidths(storage(), userId());
    applyWidths(doc.getElementById('vlt-table-host'));
  }
  function bindColumnResize(host) {
    host.querySelectorAll('[data-vlt-resize]').forEach(grip => {
      const key = grip.dataset.vltResize;
      const current = () => grip.closest('th')?.getBoundingClientRect().width || state.widths[key] || COLUMNS[key].width;
      grip.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); });
      grip.addEventListener('dblclick', event => {
        event.preventDefault(); event.stopPropagation();
        const next = { ...state.widths }; delete next[key]; state.widths = next;
        applyWidths(host); saveWidths();
      });
      grip.addEventListener('keydown', event => {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        event.preventDefault(); event.stopPropagation();
        setColumnWidth(key, current() + (event.key === 'ArrowRight' ? 8 : -8));
      });
      grip.addEventListener('pointerdown', event => {
        if (event.button !== 0) return;
        event.preventDefault(); event.stopPropagation();
        const startX = event.clientX; const startWidth = current();
        grip.setPointerCapture?.(event.pointerId);
        doc.body.classList.add('vlt-resizing');
        const move = e => setColumnWidth(key, startWidth + (e.clientX - startX), { save: false });
        const up = () => {
          grip.removeEventListener('pointermove', move); grip.removeEventListener('pointerup', up); grip.removeEventListener('pointercancel', up);
          doc.body.classList.remove('vlt-resizing');
          saveWidths();
        };
        grip.addEventListener('pointermove', move); grip.addEventListener('pointerup', up); grip.addEventListener('pointercancel', up);
      });
    });
  }
  // Parts locations shown on the card (pdc-service-locations.js): Tune parts_location for an on-site (PMB) vehicle.
  function partsLocationValues(vehicle) {
    if (!root.PDC_SERVICE_LOCATIONS || typeof root.vehiclePdcLocation !== 'function' || root.vehiclePdcLocation(vehicle) !== 'PMB') return [];
    return [...new Set((vehicle?.tuneServiceLocations?.jobs || []).map(job => String(job.parts_location ?? '').trim()).filter(Boolean))];
  }

  function openVehicle(key, bucket) {
    if (drawerOpener) { state.openKey = key; drawerOpener.open(key, bucket); return; }
    openDrawer(key, bucket);
  }
  function setDrawerOpener(opener) {
    drawerOpener = opener && typeof opener.open === 'function' ? opener : null;
    return true;
  }
  // The slide-out panel tells the table it closed (clears the open row; nothing else changes).
  function drawerClosed() {
    state.openKey = '';
    doc.querySelectorAll('#vlt-table-host tr.is-open').forEach(row => row.classList.remove('is-open'));
  }

  function openDrawer(key, bucket, ui = null) {
    const drawer = doc.getElementById('vlt-drawer');
    const vehicle = root.vehicleLocationsScreenRows().find(row => root.vehicleKey(row) === key);
    if (!drawer || !vehicle) return;
    state.openKey = key;
    doc.querySelectorAll('#vlt-table-host tr.is-open').forEach(row => row.classList.remove('is-open'));
    doc.querySelector(`#vlt-table-host tr[data-vlt-key="${CSS.escape(key)}"]`)?.classList.add('is-open');
    const workshopProjectionAvailable = root.ensureDashboardWorkshopProjectionReady();
    const workshopPlans = workshopProjectionAvailable && typeof root.workshopLoadPlans === 'function' ? root.workshopLoadPlans() : null;
    const esc = value => root.escapeHtml(String(value ?? ''));
    const tile = TILE[bucket] || [bucket, '', 'unknown', String(bucket || '').toUpperCase()];
    const card = root.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans, workshopProjectionAvailable, subletNavigation: true })
      .replace('<details class="incoming-vehicle-card', '<details open class="incoming-vehicle-card vlt-drawer-card');
    drawer.innerHTML = `<div class="vlt-drawer-head"><div><span class="vlt-pill ${esc(tile[2])}">${esc(tile[3])}</span><h3>${esc(root.displayStockNumber(vehicle) || key)}</h3><p>${esc(root.displayVehicle(vehicle) || '')}</p></div><button type="button" class="small-button" data-vlt-close>Close</button></div>
      <div class="vlt-drawer-body">${card}</div>`;
    drawer.hidden = false;
    drawer.querySelector('summary')?.addEventListener('click', event => { if (!event.target.closest('button, a, input, select, label')) event.preventDefault(); });
    drawer.querySelector('[data-vlt-close]').addEventListener('click', closeDrawer);
    bindBoardHandlers(drawer);
    if (ui) {
      const nested = [...drawer.querySelectorAll('.vlt-drawer-body details details')];
      ui.drawerOpenDetails.forEach((open, index) => { if (nested[index]) nested[index].open = open; });
      const scroller = drawer.querySelector('.vlt-drawer-body');
      if (scroller) scroller.scrollTop = ui.drawerScroll;
    }
  }

  function closeDrawer() {
    if (drawerOpener) { drawerOpener.close(); drawerClosed(); return; }
    state.openKey = '';
    const drawer = doc.getElementById('vlt-drawer');
    if (drawer) { drawer.hidden = true; drawer.innerHTML = ''; }
    doc.querySelectorAll('#vlt-table-host tr.is-open').forEach(row => row.classList.remove('is-open'));
  }

  // The same listeners renderIncomingDashboardBoardContent() attaches to the drop-down board today.
  function bindBoardHandlers(scope) {
    const all = selector => [...scope.querySelectorAll(selector)];
    all('[data-open-stock]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.openVehicleCardFromVisibleBoard(button.dataset.openStock, button); }));
    root.bindIncomingSubletLinks(scope);
    root.bindVehicleLabelButtons(scope);
    all('[data-incoming-delete]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.deleteIncomingVehicleFromMain(button.dataset.incomingDelete); }));
    all('[data-yh-transfer-pmb]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.transferYhVehicleToPmb(button.dataset.yhTransferPmb); }));
    all('[data-pit-transfer]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.moveVehiclePitLocation(button.dataset.pitTransfer, 'to_pit'); }));
    all('[data-pit-return-pmb]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.moveVehiclePitLocation(button.dataset.pitReturnPmb, 'to_pmb'); }));
    all('[data-ready-for-qc]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.markVehicleReadyForQualityControl(button.dataset.readyForQc); }));
    all('[data-open-qc-vehicle]').forEach(button => button.addEventListener('click', event => {
      event.stopPropagation();
      qcSelectedVehicleKey = button.dataset.openQcVehicle || ''; // app.js script-level binding, as the drop-down handler does
      root.showView('qc');
      root.renderQualityControlPage();
    }));
    all('[data-pmb-bay-provider-key]').forEach(select => {
      select.addEventListener('click', event => event.stopPropagation());
      select.addEventListener('change', () => root.updatePmbBaySubletProvider(select.dataset.pmbBayProviderKey, select.dataset.pmbBayProviderStage, select.value));
    });
    all('[data-auth-operation-work]').forEach(button => button.addEventListener('click', event => { event.stopPropagation(); root.openAuthenticatedOperationWorkshop(button.dataset.authOperationWork); }));
    root.bindAuthenticatedOperationSummaries(scope);
    root.bindRftCollectedInputs(scope);
    root.bindIncomingCardSelection(scope);
  }
  function renderWithCache() {
    // Same per-render JSON cache the drop-down render uses (app.js renderIncomingDashboardBoard).
    const previous = activeRenderJsonCache;
    activeRenderJsonCache = previous || new Map();
    try { return renderTable(); } finally { activeRenderJsonCache = previous; }
  }

  root.renderIncomingDashboardBoard = function renderIncomingDashboardBoardWithViewSwitch(...args) {
    ensureSwitch();
    if (!tableOn()) return originalRender.apply(this, args);
    return renderWithCache();
  };

  // Read-only self-check, runnable on any signed-in page: PDC_VEHICLE_LOCATIONS_TABLE.parity().
  // Draws the drop-down view, then the table view, compares every station cell of every vehicle (state classes,
  // symbol, tooltip, computed colours), the RFT controls and the status / age / booking items, then restores the view.
  // Nothing is saved and nothing is sent.
  async function parity() {
    const frame = () => new Promise(resolve => (root.requestAnimationFrame || setTimeout)(() => resolve()));
    const props = ['color', 'backgroundColor', 'backgroundImage', 'borderTopColor', 'borderLeftColor', 'opacity'];
    const look = (el, pseudo) => { const cs = root.getComputedStyle(el, pseudo || null); const out = {}; props.forEach(name => { out[name] = cs[name]; }); if (pseudo) out.content = cs.content; return out; };
    const cellsOf = strip => strip ? [...strip.querySelectorAll(':scope > .incoming-work-check')].map(cell => ({
      station: [...cell.classList].find(name => name.startsWith('pdc-station-')) || '',
      classes: [...cell.classList].sort().join(' '),
      symbol: [...cell.querySelectorAll('.incoming-work-box, .parts-jita-marker')].map(marker => marker.textContent.trim()).join('|'),
      title: cell.getAttribute('title') || '', aria: cell.getAttribute('aria-label') || '',
      look: look(cell), before: look(cell, '::before'), after: look(cell, '::after'),
      markers: [...cell.querySelectorAll('.incoming-work-box, .parts-jita-marker')].map(marker => ({ text: marker.textContent.trim(), look: look(marker) })),
    })) : [];
    const collect = view => {
      const rows = view === VIEWS.dropdown
        ? [...doc.querySelectorAll('#incoming-main-board details.incoming-vehicle-card[data-incoming-row]')].map(card => [card.dataset.incomingRow, card.querySelector(':scope > summary') || card])
        : [...doc.querySelectorAll('#vlt-table-host tr[data-vlt-key]')].map(row => [row.dataset.vltKey, row]);
      const out = new Map();
      rows.forEach(([key, scope]) => {
        const cells = cellsOf(scope.querySelector('.pdc-station-strip'));
        const rft = [...scope.querySelectorAll('.rft-action')].map(el => ({ classes: el.className, text: el.textContent.trim(), title: el.getAttribute('title') || '', disabled: Boolean(el.disabled), look: look(el) }));
        const others = [...scope.querySelectorAll('[class*="badge"], button, .incoming-card-age, .incoming-card-status, select')]
          .filter(el => !el.closest('.pdc-station-strip, .rft-transport-controls'))
          .map(el => JSON.stringify([String(el.className?.baseVal ?? el.className), el.textContent.replace(/\s+/g, ' ').trim(), Boolean(el.disabled), root.getComputedStyle(el).color])).sort();
        out.set(key, { cells, rft, others });
      });
      return out;
    };
    const before = { view: state.view, bucket: state.bucket, stoppages: state.stoppages, openKey: state.openKey };
    const report = { version: VERSION, at: new Date().toISOString(), vehicles: 0, stationCells: 0, rftControls: 0, otherItems: 0, states: {}, mismatches: [], dropDownCardsInTableView: 0 };
    const miss = (vehicle, where, field, today, table) => { if (report.mismatches.length < 200) report.mismatches.push({ vehicle, where, field, today, table }); report.mismatchCount = (report.mismatchCount || 0) + 1; };
    report.mismatchCount = 0;
    try {
      setView(VIEWS.dropdown, { save: false }); await frame();
      const today = collect(VIEWS.dropdown);
      Object.assign(state, { bucket: '', stoppages: false, openKey: '' });
      setView(VIEWS.table, { save: false }); await frame();
      report.dropDownCardsInTableView = doc.querySelectorAll('#incoming-main-board .incoming-vehicle-card').length;
      const table = collect(VIEWS.table);
      report.vehicles = today.size;
      today.forEach((t, key) => {
        const n = table.get(key);
        if (!n) { miss(key, 'row', 'missing from table view'); return; }
        if (t.cells.length !== n.cells.length) miss(key, 'stations', 'cell count', t.cells.length, n.cells.length);
        t.cells.forEach((cell, index) => {
          report.stationCells += 1;
          const label = /is-blocked/.test(cell.classes) ? 'stoppage' : /is-complete/.test(cell.classes) ? 'complete' : /is-booked/.test(cell.classes) ? 'booked'
            : /imported-parts-/.test(cell.classes) ? `parts ${(cell.classes.match(/imported-parts-(\w+)/) || [])[1]}` : /is-not-required/.test(cell.classes) ? 'not required' : /is-required/.test(cell.classes) ? 'required' : 'other';
          report.states[label] = (report.states[label] || 0) + 1;
          const other = n.cells[index] || {};
          ['station', 'classes', 'symbol', 'title', 'aria', 'look', 'before', 'after', 'markers'].forEach(field => {
            if (JSON.stringify(cell[field]) !== JSON.stringify(other[field])) miss(key, cell.station, field, cell[field], other[field]);
          });
        });
        if (t.rft.length !== n.rft.length) miss(key, 'rft', 'control count', t.rft.length, n.rft.length);
        t.rft.forEach((control, index) => { report.rftControls += 1; if (JSON.stringify(control) !== JSON.stringify(n.rft[index])) miss(key, 'rft', control.classes, control, n.rft[index]); });
        report.otherItems += t.others.length;
        if (JSON.stringify(t.others) !== JSON.stringify(n.others)) miss(key, 'status/age/booking', 'items', t.others, n.others);
      });
      table.forEach((_, key) => { if (!today.has(key)) miss(key, 'row', 'extra in table view'); });
      if (report.dropDownCardsInTableView) miss('*', 'render', 'drop-down cards drawn in table view', 0, report.dropDownCardsInTableView);
      // r462: the slide-out panel's station strip for every vehicle against today's drop-down strip (same fields).
      // parityStrip() only draws the card HTML off-screen inside the panel; it binds nothing and loads nothing.
      if (drawerOpener && typeof drawerOpener.parityStrip === 'function') {
        report.panelVehicles = 0; report.panelStationCells = 0;
        try {
          today.forEach((t, key) => {
            const row = [...doc.querySelectorAll('#vlt-table-host tr[data-vlt-key]')].find(tr => tr.dataset.vltKey === key);
            const cells = cellsOf(drawerOpener.parityStrip(key, row?.dataset.vltBucket || ''));
            report.panelVehicles += 1;
            if (t.cells.length !== cells.length) miss(key, 'panel stations', 'cell count', t.cells.length, cells.length);
            t.cells.forEach((cell, index) => {
              report.panelStationCells += 1;
              ['station', 'classes', 'symbol', 'title', 'aria', 'look', 'before', 'after', 'markers'].forEach(field => {
                if (JSON.stringify(cell[field]) !== JSON.stringify((cells[index] || {})[field])) miss(key, `panel ${cell.station}`, field, cell[field], (cells[index] || {})[field]);
              });
            });
          });
        } finally { drawerOpener.parityDone?.(); }
      }
    } finally {
      Object.assign(state, { bucket: before.bucket, stoppages: before.stoppages, openKey: before.openKey });
      setView(before.view, { save: false });
    }
    return report;
  }

  function syncViewForUser() {
    state.widths = readWidths(storage(), userId());
    const view = readView(storage(), userId());
    if (view !== state.view) { state.view = view; applyViewChrome(); if (app?.currentView === 'dashboard') root.renderIncomingDashboardBoard(); }
    else ensureSwitch();
  }

  loadStyles();
  state.view = readView(storage(), userId());
  state.widths = readWidths(storage(), userId());
  applyViewChrome();
  if (tableOn() && app?.currentView === 'dashboard') root.renderIncomingDashboardBoard();
  root.addEventListener?.('pdc-auth-ready', syncViewForUser);
  root.addEventListener?.('storage', event => {
    if (event.key === storageKey(userId())) syncViewForUser();
    if (event.key === columnStorageKey(userId()) && tableOn()) { state.widths = readWidths(storage(), userId()); applyWidths(doc.getElementById('vlt-table-host')); }
  });
  doc.addEventListener('keydown', event => { if (event.key === 'Escape' && tableOn() && state.openKey && !doc.querySelector('.modal[open], dialog[open]')) closeDrawer(); });

  root.PDC_VEHICLE_LOCATIONS_TABLE = Object.freeze({ ...api, state, setView, openDrawer, closeDrawer, parity, render: () => root.renderIncomingDashboardBoard(),
    bindBoardHandlers, setDrawerOpener, drawerClosed, setColumnWidth, resetColumns, addTooltips });
}(typeof window !== 'undefined' ? window : globalThis));
