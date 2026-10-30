/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r443 (F56, change request from Craig): the vehicle drop-down's "Operations from authenticated PD documents and job
   cards" laid out as packed category panels. Layout only: lines, categories, hours, PO chips/ticks, Review controls,
   edits and bookings are untouched (each original category box is moved, as is, into its panel).
   - Seven panels in two columns: Tint, Bus 4x4 (with its sub-categories), Hoist / GVM, Fitting, Fabrication,
     Electrical, Tyres. Each panel is only as tall as its lines.
   - Balancing (deterministic, largest first): weight = 1 (header) + number of lines (an empty panel weighs 1). Panels are
     placed heaviest first (equal weights in the standard order), each into the column with the smaller running weight
     (ties go left). Each column then lists its panels in the standard order.
   - Sublet runs full width under both columns (only when the vehicle has sublets), then Review and any other boxes.
   - r444 (F57): a category with no operation lines is not shown; inside Bus 4x4 each sub-group (Mechanical, Accessories,
     Electrical, QA) is its own grey framed box; the Sublet box header shows "N sublets" and the done state (orange/green).
   - The panels never run past the right edge of the window (CSS cap, refined to the row's real position).
   - A line whose hours are not a number shows "Hours not stated" (as today), never "NaN h".
   Works on the HTML string and wraps outermost (canonical-entry.js loads it after pdc-sublet-po.js, whose Sublet box rows
   and state it reads); the original sections keep their exact class attribute and markers are data attributes, so
   pdc-review-stations.js binds as before. Idempotent. */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r444';
  const PANELS = Object.freeze([
    { id: 'tint', label: 'Tint', keys: ['tint'] },
    { id: 'bus4x4', label: 'Bus 4x4', keys: ['bus4x4', 'bus_mechanical', 'bus_accessories', 'bus_electrical', 'bus_qa', 'bus_pit'] },
    { id: 'hoist', label: 'Hoist / GVM', keys: ['hoist'] },
    { id: 'fitting', label: 'Fitting', keys: ['fitting'] },
    { id: 'fabrication', label: 'Fabrication', keys: ['fabrication'] },
    { id: 'electrical', label: 'Electrical', keys: ['electrical'] },
    { id: 'tyre', label: 'Tyres', keys: ['tyre'] },
  ]);
  const SUBLET = Object.freeze({ id: 'sublet', label: 'Sublet', keys: ['sublet'] });
  const FALLBACK_COLOURS = { tint: ['#227889', '#eaf7f9'], bus4x4: ['#3e6690', '#edf2f8'], hoist: ['#805b43', '#f5eee8'], fitting: ['#79528f', '#f4eef8'],
    fabrication: ['#8c671d', '#fbf5e5'], electrical: ['#557649', '#eef4eb'], tyre: ['#a05270', '#faedf2'], sublet: ['#8c671d', '#fbf5e5'] };
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function colours(id) {
    try {
      const order = typeof AUTHENTICATED_OPERATION_STATION_ORDER !== 'undefined' ? AUTHENTICATED_OPERATION_STATION_ORDER : null;
      const hit = Array.isArray(order) && order.find(s => s.key === id);
      if (hit && hit.colour && hit.tint) return [hit.colour, hit.tint];
    } catch (_) { /* fallback */ }
    return FALLBACK_COLOURS[id];
  }
  /**
   * Two-column split. items: [{ id, weight }] in the standard order. Largest first (equal weights keep the standard
   * order), each to the column with the smaller running weight, ties left; each column is listed in the standard order.
   */
  function balance(items) {
    const seq = items.map((it, i) => ({ id: it.id, weight: Number(it.weight) || 0, i })).sort((a, b) => b.weight - a.weight || a.i - b.i);
    const side = new Map(); let left = 0, right = 0;
    for (const it of seq) { if (left <= right) { side.set(it.id, 'left'); left += it.weight; } else { side.set(it.id, 'right'); right += it.weight; } }
    const pick = s => items.filter(it => side.get(it.id) === s).map(it => it.id);
    return { left: pick('left'), right: pick('right'), weights: { left, right } };
  }
  /** A line's hours cell that is not a number ("NaN h", "Infinity h") reads "Hours not stated", as for blank hours. */
  function guardHours(html) {
    return String(html).replace(/(<em\b[^>]*>)\s*-?(?:NaN|Infinity) h/g, '$1Hours not stated')
      .replace(/(<header><strong>[^<]*<\/strong><small>[^<]*· )-?(?:NaN|Infinity) h(<\/small>)/g, '$1Unknown hours$2');
  }
  const GRID_OPEN = '<div class="authenticated-operation-station-grid">';
  const SECTION_AT = /^\s*(<section class="authenticated-operation-station"([^>]*)>)([\s\S]*?)<\/section>/;
  /** Split the summary into the station grid's sections. Returns null when the shape is not the expected one. */
  function parse(html) {
    const start = html.indexOf(GRID_OPEN);
    if (start < 0) return null;
    let pos = start + GRID_OPEN.length; const sections = [];
    for (;;) {
      const m = html.slice(pos).match(SECTION_AT);
      if (!m) break;
      const attrs = m[2];
      sections.push({ html: m[0].trim(), open: m[1], attrs, inner: m[3], key: ((attrs.match(/data-operation-category="([^"]*)"/) || [])[1] || '').toLowerCase(),
        lines: (m[3].match(/<li data-operation-source-id=/g) || []).length });
      pos += m[0].length;
    }
    const close = html.slice(pos).match(/^\s*<\/div>/);
    if (!close) return null;
    return { before: html.slice(0, start), sections, after: html.slice(pos + close[0].length) };
  }
  const mark = (section, attrs) => section.html.replace(section.open, section.open.slice(0, -1) + attrs + '>');
  const headerSmall = section => (section.inner.match(/<header><strong>[^<]*<\/strong><small>([^<]*)<\/small><\/header>/) || [])[1] || '';
  function panelHtml(p, found, extraClass = '') {
    extraClass = String(extraClass);
    const [colour, tint] = colours(p.id);
    const jobs = found.reduce((n, s) => n + s.lines, 0);
    let small = '';
    if (p.id === 'sublet') { const n = found.reduce((t, s) => t + (s.inner.match(/<li\b(?![^>]*pdc-sublet-group)/g) || []).length, 0); small = `${n} sublet${n === 1 ? '' : 's'}`; } // r747: group headings are not sublets
    else if (found.length === 1) small = headerSmall(found[0]);
    else if (found.length > 1) {
      const known = found.map(s => headerSmall(s).match(/([0-9]+(?:\.[0-9]+)?) h$/)).filter(Boolean);
      small = `${jobs} job${jobs === 1 ? '' : 's'} · ${known.length ? `${known.reduce((t, m) => t + Number(m[1]), 0).toFixed(2)} h` : 'Unknown hours'}`;
    }
    const sole = found.length === 1 && p.keys.length === 1;
    // r444: the Sublet box shows the vehicle's sublet state (same rule as the board's Sublet station box): orange while a
    // GP PO line is not ticked, green when all are ticked.
    const st = p.id === 'sublet' && found.length ? (found[0].attrs.match(/data-pdc-sublet-state="(ordered|done)"/) || [])[1] : '';
    const count = st ? ((found[0].attrs.match(/data-pdc-sublet-count="([0-9]+)\/([0-9]+)"/) || []).slice(1)) : [];
    if (st && count.length) small += `${small ? ' ' : ''}<span class="pdc-op-sublet-state is-${st}">${st === 'done' ? '✓ all sublets done' : `${count[0]} of ${count[1]} sublet${count[1] === '1' ? '' : 's'} done`}</span>`;
    if (st) extraClass += ` is-sublet-${st}`;
    const body = found.length ? found.map(s => mark(s, sole ? ' data-pdc-op-sub data-pdc-op-sole' : ' data-pdc-op-sub')).join('') : '<p class="pdc-op-empty">No jobs</p>';
    return { weight: 1 + jobs, html: `<section class="authenticated-operation-station pdc-op-panel${found.length ? '' : ' is-empty'}${extraClass}" data-operation-panel="${p.id}" style="--station-colour:${esc(colour)};--station-tint:${esc(tint)}">`
      + `<header><strong>${esc(p.label)}</strong>${small ? `<small>${small}</small>` : ''}</header><div class="pdc-op-panel-body">${body}</div></section>` };
  }
  /** Rearrange one operations summary (HTML string). Unknown shapes and already arranged summaries are returned unchanged. */
  function arrange(html) {
    if (typeof html !== 'string' || !html.includes(GRID_OPEN)) return html;
    const guarded = guardHours(html);
    const parsed = parse(guarded);
    if (!parsed || !parsed.sections.length) return guarded;
    const used = new Set();
    const take = p => { const f = p.keys.map(k => parsed.sections.find(s => s.key === k)).filter(Boolean); f.forEach(s => used.add(s)); return f; };
    // r444 (F57): a category with no operation lines is not shown; Sublet only when the vehicle has sublets.
    const built = PANELS.map(p => ({ id: p.id, found: take(p) })).filter(b => b.found.length).map(b => ({ id: b.id, ...panelHtml(PANELS.find(p => p.id === b.id), b.found) }));
    const subletFound = take(SUBLET);
    const sublet = subletFound.length ? panelHtml(SUBLET, subletFound, ' is-full') : { html: '' };
    const split = balance(built);
    const col = side => `<div class="pdc-op-col is-${side}" data-pdc-op-column="${side}">${split[side].map(id => built.find(b => b.id === id).html).join('')}</div>`;
    const rest = parsed.sections.filter(s => !used.has(s));
    return parsed.before + `<div class="authenticated-operation-station-grid" data-pdc-panels="${VERSION}">`
      + `<div class="pdc-op-panels">${col('left')}${col('right')}${sublet.html}</div>`
      + (rest.length ? `<div class="authenticated-operation-station-grid pdc-op-below">${rest.map(s => s.html).join('')}</div>` : '')
      + '</div>' + parsed.after;
  }
  const IN = '.authenticated-email-operations .pdc-op-panels';
  const LINE = IN + ' .authenticated-operation-station[data-pdc-op-sub] li';
  const CSS = [
    '.authenticated-email-operations .authenticated-operation-station-grid[data-pdc-panels]{display:block;max-width:calc(100vw - 110px)}',
    IN + '{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.65rem;align-items:start}',
    IN + ' .pdc-op-col{display:flex;flex-direction:column;gap:.65rem;min-width:0}',
    IN + ' .pdc-op-panel{display:flex;flex-direction:column;min-width:0;margin:0}',
    IN + ' .pdc-op-panel.is-full{grid-column:1/-1}',
    IN + ' .pdc-op-panel-body{min-width:0}',
    // Compact empty panel: one short row with the name and a muted "No jobs".
    IN + ' .pdc-op-panel.is-empty{flex-direction:row;align-items:center;opacity:.8}',
    IN + ' .pdc-op-panel.is-empty>header{flex:1;min-height:0;padding:.3rem .6rem;border-bottom:0}',
    IN + ' .pdc-op-panel.is-empty>.pdc-op-panel-body{flex:0 0 auto}',
    '.pdc-op-empty{margin:0;padding:.3rem .6rem;color:#94a3b8;font-size:.7rem;font-weight:700;white-space:nowrap}',
    // The original category box sits inside its panel without its own frame; a single-category panel hides the duplicate header.
    IN + ' .authenticated-operation-station[data-pdc-op-sub]{border:0;border-radius:0;box-shadow:none;background:transparent;overflow:visible;margin:0}',
    IN + ' .authenticated-operation-station[data-pdc-op-sole]>header{display:none}',
    // r444 (F57): inside a panel with sub-groups (Bus 4x4), each sub-group is its own grey framed box.
    IN + ' .authenticated-operation-station[data-pdc-op-sub]:not([data-pdc-op-sole]){border:2px solid #94a3b8;border-radius:8px;background:#fff;margin:.45rem .5rem;overflow:hidden}',
    IN + ' .authenticated-operation-station[data-pdc-op-sub]:not([data-pdc-op-sole])+.authenticated-operation-station[data-pdc-op-sub]{margin-top:.55rem}',
    IN + ' .authenticated-operation-station[data-pdc-op-sub]:not([data-pdc-op-sole])>header{min-height:0;padding:.3rem .6rem;background:#e2e8f0;border-bottom:2px solid #94a3b8}',
    IN + ' .authenticated-operation-station[data-pdc-op-sub]:not([data-pdc-op-sole])>header strong{color:#1e293b}',
    IN + ' .pdc-op-panel.is-sublet-ordered{border-color:#f97316;box-shadow:0 0 0 1px #f97316 inset}',
    IN + ' .pdc-op-panel.is-sublet-done{border-color:#16a34a;box-shadow:0 0 0 1px #16a34a inset}',
    '.pdc-op-sublet-state{display:inline-block;margin-left:.4rem;padding:0 .4rem;border-radius:999px;font-size:.66rem;font-weight:800;line-height:1.3rem;vertical-align:middle}',
    '.pdc-op-sublet-state.is-ordered{background:#ffedd5;color:#9a3412;border:1px solid #fdba74}.pdc-op-sublet-state.is-done{background:#dcfce7;color:#166534;border:1px solid #86efac}',
    IN + ' .pdc-op-panel.is-full li.pdc-sublet-linked{background:#fffbf5}',
    LINE + '>.pdc-sublet-po-ref{grid-column:4;grid-row:1;justify-self:end;margin:0}',
    // One row per line: label | description | hours | PO chip + tick (or "No PO"). Hours take their own width (incl. "Hours not stated").
    LINE + '{grid-template-columns:minmax(4.4rem,max-content) minmax(0,1fr) max-content auto;align-items:center;column-gap:.45rem;padding:.3rem .55rem}',
    LINE + '>em{text-align:right}',
    LINE + '>.pdc-sublet-po-inline,' + LINE + '>.pdc-sublet-po-nopo{grid-column:4;grid-row:1;justify-self:end;margin:0}',
    '.authenticated-email-operations .pdc-op-below{margin-top:.65rem}',
    '@media (max-width:900px){' + IN + '{grid-template-columns:1fr}}',
    '@media (max-width:440px){' + LINE + '{grid-template-columns:auto minmax(0,1fr)}' + LINE + '>.pdc-sublet-po-inline,' + LINE + '>.pdc-sublet-po-nopo{grid-column:2/-1;grid-row:auto;justify-self:start}}',
  ].join('');
  const api = { PANELS, SUBLET, balance, guardHours, arrange, CSS, VERSION };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_OPERATION_PANELS_VERSION) return;
  window.PDC_OPERATION_PANELS_VERSION = VERSION;
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);
  /** Tighten the width cap to the summary's real position so the right column is never past the window edge. */
  let fitQueued = false;
  const fit = () => {
    fitQueued = false;
    try {
      const width = document.documentElement.clientWidth || window.innerWidth;
      document.querySelectorAll('.authenticated-operation-station-grid[data-pdc-panels]').forEach(grid => {
        const left = grid.getBoundingClientRect().left;
        grid.style.maxWidth = `${Math.max(520, Math.floor(width - Math.max(0, left) - 16))}px`;
      });
    } catch (_) { /* CSS cap stays */ }
  };
  const queueFit = () => { if (fitQueued) return; fitQueued = true; (window.requestAnimationFrame || setTimeout)(fit); };
  window.addEventListener('resize', queueFit);
  if (typeof authenticatedEmailOperationLinesHtml === 'function') {
    const prior = authenticatedEmailOperationLinesHtml;
    authenticatedEmailOperationLinesHtml = function (vehicle = {}, ...args) {
      const html = prior.call(this, vehicle, ...args);
      const out = arrange(html);
      if (out !== html) queueFit();
      return out;
    };
    // Rows opened before this file loaded switch to the panels now (same refresh the PO module and Review use).
    try {
      if (typeof refreshAuthenticatedOperationSummaryRow === 'function') {
        document.querySelectorAll('[data-incoming-row][open]').forEach(row => { try { refreshAuthenticatedOperationSummaryRow(row); } catch (_) { /* next render */ } });
      }
    } catch (_) { /* next render */ }
  }
})();
