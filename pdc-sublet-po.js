/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r439 (F50): sublet purchase orders. Sublet contractors come on site, so no line changes category, bay or booking.
   r444 (F57): the vehicle drop-down's Sublet box lists every sublet: each operation line with a GP PO gets a row there (PD
   line, the 'Description of sublet' from the upload, the PO and the 'sublet done' tick), and Sublet jobs raised as their own
   lines show their description, PO and tick (or a muted "No PO"; lines without a GP PO cannot be ticked). Operation lines
   keep only a small read-only PO reference. One tick per line (the r439 tick record). The vehicle's Sublet box is orange
   while a GP PO exists and not all of those lines are ticked, green once they all are, and unchanged (neutral) when the
   vehicle has no GP PO. Controllers, administrators and fitters tick (the server checks again); others read.
   r494 (F107, Craig 22 Oct 18:41): a whole line sublet (a line in the Sublet category) with no GP PO yet turns the board's
   Sublet box orange with 'PO to raise' (and shows 'PO to raise' on the line); a GP PO that an import brings onto a line in
   another category shows in the Sublet box as a sublet item with 'PO raised for this line' until it is ticked done or
   the user presses 'Got it' (remembered for that user in this browser). The supplier is the sublet provider.
   r494b (F107, Craig 22 Oct 18:55): the vehicle's Sublet box is uniform: every line ends in one same-size chip (the GP PO
   number or 'PO to raise'), no 'Hours not stated', no 'Op line PO' caption, and no 'PO raised for this line' / 'Got it'
   (the GP number on the right already shows it). One text size in the box. The Got it storage below stays but is unused.
   r494c (F107b, Craig 22 Oct: 'now the website is extremely slow'): the board's 'PO to raise' makes no per-vehicle call
   and no board redraw while it renders; see raiseFor. */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r444';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const stockKey = value => String(value ?? '').trim().toUpperCase();
  const idKey = value => String(value ?? '').trim().toLowerCase();
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  /** Index the board payload (vehicles with a sublet PO or a tick) by vehicle id and stock number. */
  function indexBoard(payload) {
    const byId = new Map(), byStock = new Map();
    for (const entry of Array.isArray(payload?.vehicles) ? payload.vehicles : []) {
      if (!entry || !(Number(entry.total) > 0)) continue;
      if (entry.vehicle_id) byId.set(idKey(entry.vehicle_id), entry);
      if (stockKey(entry.stock_number)) byStock.set(stockKey(entry.stock_number), entry);
    }
    return { byId, byStock };
  }
  function vehicleIds(vehicle) {
    const ids = [vehicle?.__emailVehicleId, vehicle?.id, vehicle?.permanentVehicleId];
    try { if (typeof vehicleWorkshopDetailCanonicalId === 'function') ids.unshift(vehicleWorkshopDetailCanonicalId(vehicle)); } catch (_) { /* optional */ }
    return ids.map(idKey).filter(id => UUID.test(id));
  }
  function entryFor(index, vehicle) {
    if (!index || !vehicle) return null;
    for (const id of vehicleIds(vehicle)) { const hit = index.byId.get(id); if (hit) return hit; }
    return index.byStock.get(stockKey(vehicle.stock)) || null;
  }
  /** Box look for one vehicle: done = green ✓ (every GP PO line ticked); ordered = orange ! with n/m; no GP PO = null (box unchanged). */
  function boxState(entry, toRaise = 0) {
    const raise = Number(toRaise) > 0 ? Math.floor(Number(toRaise)) : 0;
    if ((!entry || !(Number(entry.total) > 0)) && !raise) return null;
    if (raise) {
      const poTotal = entry && Number(entry.total) > 0 ? Number(entry.total) : 0, poTicked = poTotal ? Number(entry.ticked) || 0 : 0;
      const title = `Sublet: PO to raise: ${raise} whole line sublet${raise === 1 ? ' has' : 's have'} no GP PO yet`
        + (poTotal ? `; ${poTicked} of ${poTotal} GP PO line${poTotal === 1 ? '' : 's'} ticked sublet done` : '');
      return { cls: 'is-ordered', marker: '!', count: 'PO to raise', title, raise };
    }
    const total = Number(entry.total) || 0, ticked = Number(entry.ticked) || 0, withPo = Number(entry.with_po) || 0;
    const count = `${ticked}/${total}`;
    if (entry.state === 'done') return { cls: 'is-complete', marker: '✓', count, title: `Sublet: all ${total} GP PO line${total === 1 ? '' : 's'} ticked sublet done` };
    if (entry.state === 'ordered') return { cls: 'is-ordered', marker: '!', count, title: `Sublet: ${withPo} line${withPo === 1 ? '' : 's'} with a GP PO, ${ticked} of ${total} ticked sublet done` };
    return null;
  }
  /** r494: the vehicle's whole line sublets (lines the board shows in the Sublet category, still open). */
  function subletJobs(vehicle) {
    if (!vehicle || vehicle.pdcQcOperationLinesProjectionPresent !== true) return [];
    return (Array.isArray(vehicle.pdcQcOperationLines) ? vehicle.pdcQcOperationLines : []).filter(l => l && l.active !== false
      && l.completed !== true && l.rejected !== true && String(l.stageCode || l.stage_code || '').toUpperCase() === 'SUBLET');
  }
  /** r494: how many whole line sublets have no GP PO yet. No board entry = the vehicle has no GP PO at all. With an entry,
   *  the vehicle's GP PO lines decide (known:false until they are loaded).
   *  r494c (F107b): until they are loaded, the board's own counts give a safe lower bound with no extra call: the entry's
   *  with_po lines are all the lines carrying a GP PO, so at most that many Sublet lines can have one. */
  function poToRaise(vehicle, entry, payload) {
    const jobs = subletJobs(vehicle);
    if (!jobs.length) return { count: 0, known: true };
    if (!entry) return { count: jobs.length, known: true };
    if (!payload || !Array.isArray(payload.lines)) {
      const withPo = Math.max(0, Number(entry.with_po ?? entry.total) || 0);
      return { count: Math.max(0, jobs.length - withPo), known: false };
    }
    const withPo = new Set(payload.lines.filter(l => l && l.has_po !== false).map(l => sourceId(l.line_identity)).filter(Boolean));
    return { count: jobs.filter(l => !withPo.has(sourceId(l.lineIdentity || l.line_identity))).length, known: true };
  }
  /** r494: 'PO raised for this line' until the sublet item is ticked done or this user has pressed 'Got it'. */
  const seenKey = (vehicleId, line, po) => [idKey(vehicleId), String(line?.line_key || ''), String(po || '')].join('|');
  function isNewPo(line, vehicleId, seen) {
    if (!line || line.ticked === true || !seen || typeof seen.has !== 'function') return false; // no seen list = no notes (tests, other callers)
    const pos = poDetails(line).map(d => d.po);
    return pos.length > 0 && pos.some(po => !seen.has(seenKey(vehicleId, line, po)));
  }
  function newPoHtml(line, vehicleId) {
    return ` <span class="pdc-sublet-new-po" title="An import attached a GP PO to this line. It stays highlighted until the sublet is ticked done or you press Got it.">PO raised for this line</span>`
      + `<button type="button" class="pdc-sublet-new-ack" data-pdc-sublet-ack="${esc(poDetails(line).map(d => seenKey(vehicleId, line, d.po)).join(' '))}" title="Hide this note (for you, in this browser)">Got it</button>`;
  }
  const BOX = /<(span|button)([^>]*\bclass="incoming-work-check pdc-station-sublet\b[^"]*")([^>]*)>((?:\s*<span\b[^>]*>[^<]*<\/span>)*\s*)<\/\1>/;
  /** Recolour the Sublet station box in a strip. A Sublet already marked complete on the board stays green. Idempotent. */
  function decorateStrip(html, entry, toRaise = 0) {
    const s = boxState(entry, toRaise);
    if (!s || typeof html !== 'string' || !BOX.test(html)) return html;
    return html.replace(BOX, (all, tag, classAttr, rest, inner) => {
      if (classAttr.includes('pdc-sublet-po-box')) return all;
      const classes = classAttr.match(/class="([^"]*)"/)[1].split(/\s+/);
      const complete = classes.includes('is-complete');
      let next = classes.concat('pdc-sublet-po-box');
      if (s.cls && !complete) {
        next = next.filter(c => !['is-required', 'is-ordered', 'is-booked', 'is-complete', 'is-not-required'].includes(c));
        if (s.cls === 'is-ordered') next.push('is-required');
        next.push(s.cls);
      }
      let body = inner;
      // r494 (F107): 'PO to raise' is written in the box itself (the box is otherwise a symbol only).
      const marker = s.raise ? '<b class="pdc-sublet-po-raise">PO to raise</b>' : s.marker;
      if (s.raise && !complete) next.push('is-po-to-raise');
      if (marker && !complete) body = body.replace(/(<span class="incoming-work-box"[^>]*>)[\s\S]*?(<\/span>)/, `$1${marker}$2`);
      body = body.replace(/(<span class="incoming-work-label">[\s\S]*?)(<\/span>)/, `$1 <small class="pdc-sublet-po-count">${esc(s.count)}</small>$2`);
      const attrs = (classAttr.replace(/class="[^"]*"/, `class="${next.join(' ')}"`) + rest)
        .replace(/title="[^"]*"/, `title="${esc(s.title)}"`).replace(/aria-label="([^"]*)"/, (_, a) => `aria-label="${a}; ${esc(s.title)}"`);
      return `<${tag}${attrs}>${body}</${tag}>`;
    });
  }
  const when = value => {
    const d = new Date(value || '');
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false });
  };
  /** Same label the operations summary prints for a line ("PD line 12"). */
  function lineLabel(operationNo) {
    const key = String(operationNo || '').trim().toUpperCase();
    const pd = key.match(/^PD([0-9]{3})-/);
    return pd ? `PD line ${Number(pd[1])}` : key;
  }
  const sourceId = identity => String(identity || '').trim().toLowerCase().replace(/^(source|manual):/, '');
  /** Clean a Revolution 'Description of sublet' for display: '^' is its line break; blanks and repeats collapse. */
  function cleanDescription(text) {
    return String(text ?? '').split('^').map(part => part.replace(/\s+/g, ' ').trim()).filter(Boolean).join(' · ');
  }
  /** [{ po, description }] for a line: r444 po_details when present, else the bare po_numbers (no description yet). */
  function poDetails(line) {
    const details = Array.isArray(line?.po_details) ? line.po_details : [];
    const byPo = new Map(details.filter(d => d && d.po_number).map(d => [String(d.po_number), cleanDescription(d.description)]));
    const pos = Array.isArray(line?.po_numbers) ? line.po_numbers.map(String) : [];
    for (const po of byPo.keys()) if (!pos.includes(po)) pos.push(po);
    return pos.map(po => ({ po, description: byPo.get(po) || '' }));
  }
  /** PO chip(s) + the line's 'sublet done' tick (the r439 per-line tick record; no caption, the tick has a title and aria-label). */
  function inlineHtml(line, vehicleId, canTick) {
    const pos = poDetails(line).map(d => d.po);
    const ticked = line?.ticked === true;
    const label = lineLabel(line?.operation_no) || (line?.line_no != null ? `Line ${line.line_no}` : 'Line');
    const by = ticked && line.ticked_at ? ` (${[line.ticked_by_email, when(line.ticked_at)].filter(Boolean).join(' ')})` : '';
    const title = !canTick ? `Sublet done: ${ticked ? 'yes' : 'not yet'}${by}. Read only: controllers, administrators and fitters tick sublet done`
      : ticked ? `Sublet done${by}. Untick if the sublet is not done` : 'Sublet done? Tick when the sublet contractor has finished this line';
    const disabled = !canTick || line?.tickable === false ? ' disabled' : '';
    return ` <span class="pdc-sublet-po-inline is-${ticked ? 'done' : 'ordered'}" data-pdc-sublet-vehicle="${esc(vehicleId)}" data-line-key="${esc(line?.line_key || '')}" data-version="${esc(Number(line?.version) || 0)}">`
      + pos.map(po => `<span class="pdc-sublet-po-chip">${esc(po)}</span>`).join('')
      + `<input type="checkbox" class="pdc-sublet-po-tick" title="${esc(title)}" aria-label="${esc(`${label} sublet done`)}"${ticked ? ' checked' : ''}${disabled}></span>`;
  }
  /** r444: read-only PO reference on an operation line; its tick lives in the Sublet box. */
  function refHtml(line) {
    const details = poDetails(line), ticked = line?.ticked === true;
    const title = details.map(d => `${d.po}${d.description ? `: ${d.description}` : ''}`).join('; ') + ` (${ticked ? 'sublet done' : 'sublet not done yet'}; tick it in the Sublet box)`;
    return ` <span class="pdc-sublet-po-ref is-${ticked ? 'done' : 'ordered'}" title="${esc(title)}">${details.map(d => esc(d.po)).join(', ')}<span aria-hidden="true"> ↓</span></span>`;
  }
  /** The sublet description(s) of a line, shown in the Sublet box. One PO: its text; several: "GP…: text" per PO. */
  function descriptionHtml(line) {
    const details = poDetails(line);
    if (!details.length) return '';
    const missing = '<i class="pdc-sublet-desc-missing">No sublet description in the upload yet</i>';
    if (details.length === 1) return `<b class="pdc-sublet-desc">${details[0].description ? esc(details[0].description) : missing}</b>`;
    return details.map(d => `<b class="pdc-sublet-desc"><span class="pdc-sublet-desc-po">${esc(d.po)}</span> ${d.description ? esc(d.description) : missing}</b>`).join('');
  }
  // r494 (F107): a whole line sublet without a GP PO says what to do: raise the PO (the box stays orange until it is ticked).
  const NO_PO = ' <span class="pdc-sublet-po-nopo" title="No GP purchase order on this whole line sublet yet: raise the PO. The done tick appears once the GP PO import attaches it.">PO to raise</span>';
  const SECTION = /(<section class="authenticated-operation-station" data-operation-station="([^"]*)"[^>]*>)([\s\S]*?)(<\/section>)/g;
  const LI = /<li data-operation-source-id="([^"]*)"([^>]*)>([\s\S]*?)<\/li>/g;
  const LABEL = /^\s*<strong>([^<]*)<\/strong>/;
  const SPAN = /(<span>)([\s\S]*?)(<\/span>)/;
  const unescape = text => String(text).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  // r439c (F55): the chip/tick (or "No PO") is its own grid item after the hours.
  function addToLine(body, extra) {
    if (/pdc-sublet-po-(inline|nopo|ref)/.test(body)) return body;
    const em = body.indexOf('</em>');
    return em >= 0 ? body.slice(0, em + 5) + extra + body.slice(em + 5) : body + extra;
  }
  /** r494b: drop a line's 'Hours not stated' (or a NaN / Infinity hours) cell; only used inside the Sublet box. */
  const NO_HOURS = /<em\b[^>]*>\s*(?:Hours not stated|-?NaN h|-?Infinity h)[\s\S]*?<\/em>/g;
  const stripNoHours = body => String(body).replace(NO_HOURS, '');
  const lineNo = label => { const m = String(label).match(/([0-9]+)\s*$/); return m ? Number(m[1]) : 1e9; };
  // r747 (F351, Craig 30 Oct 10:12): the Sublet box is two groups. "Standard sublets" are the ones done all the time:
  // Malaga Motor Trimmers (MMT seat covers), Perth Signcraft, Full tank of fuel, Pit and weigh. "Other sublets" is the
  // rest (Silverstone, Tyrepower, suspension on another line, ...). A row is standard when any of its text (PD line
  // description, sublet description from the upload, the operation line it sits on) names one of them. A line anywhere
  // on the board that names a standard sublet but has no GP PO is still listed under Standard sublets (no tick).
  const STANDARD_SUBLETS = Object.freeze([
    { id: 'mmt', name: 'Malaga Motor Trimmers', re: /malaga\s*motor\s*trim|\bmmt\b|seat\s*covers?/i },
    { id: 'signcraft', name: 'Perth Signcraft', re: /sign\s*craft/i },
    { id: 'fuel', name: 'Full tank of fuel', re: /full\s*tank|tank\s*of\s*fuel/i },
    { id: 'pit', name: 'Pit and weigh', re: /\bpit\b|\bweigh\b/i },
  ]);
  const plainText = html => unescape(String(html).replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
  const standardSublet = html => STANDARD_SUBLETS.find(s => s.re.test(plainText(html))) || null;
  /** Two groups inside the Sublet box, each with its own heading and done count; an empty group is not shown. */
  function groupRowsHtml(rowsHtml) {
    const groups = { standard: [], other: [] };
    for (const html of rowsHtml) groups[standardSublet(html) ? 'standard' : 'other'].push(html);
    const head = (id, label, hint, list) => {
      const total = list.filter(h => /pdc-sublet-po-inline|pdc-sublet-po-nopo/.test(h)).length;
      const done = list.filter(h => /pdc-sublet-po-inline is-done/.test(h)).length;
      const state = total ? `<em class="pdc-sublet-group-state is-${done === total ? 'done' : 'ordered'}">${done} of ${total} done</em>` : '';
      return `<li class="pdc-sublet-group" data-pdc-sublet-group="${id}"><strong>${label}</strong><span>${hint}</span>${state}</li>`;
    };
    const standard = groups.standard.length ? head('standard', 'Standard sublets', STANDARD_SUBLETS.map(s => esc(s.name)).join(' · '), groups.standard) + groups.standard.join('') : '';
    const other = groups.other.length ? head('other', 'Other sublets', 'Sublets attached to a line or a one-off provider', groups.other) + groups.other.join('') : '';
    return standard + other;
  }
  /** A line in another category that names a standard sublet but has no GP PO: listed under Standard sublets, no tick. */
  const standardLineRow = ({ label, op, category, catName }) => ({ n: lineNo(label), html: `<li class="pdc-sublet-linked pdc-sublet-standard-line" data-pdc-sublet-row="standard-line"><strong>${esc(label)}</strong>`
    + `<span><b class="pdc-sublet-desc">${esc(op)}</b><small class="pdc-sublet-on">On operation line: ${esc([op, catName(category)].filter(Boolean).join(' · '))}</small></span><em class="pdc-sublet-kind">No PO</em></li>` });
  /**
   * r444 (F57, Craig 21 Oct): the vehicle's Sublet box lists every sublet. Operation lines stay in their category boxes with
   * a small read-only PO reference; the Sublet box gets (a) one row per operation line with a GP PO: its PD line, the sublet
   * description(s) from the w/Sublet upload, the PO(s) and the 'sublet done' tick, and (b) the Sublet jobs raised as their own
   * lines, with their description, PO and tick ("No PO" when there is none). Rows in PD line order. The Sublet box (created
   * when the vehicle has PO lines but no Sublet jobs) carries data-pdc-sublet-state none / ordered / done and the ticked count,
   * the same rule as the board's Sublet station box. Idempotent; never moves or recategorises an operation line.
   * state: { vehicleId, payload (get_pdc_sublet_lines_439 result or null), known (true when the vehicle's POs are known) }.
   */
  function decorateOperations(html, state = {}) {
    if (typeof html !== 'string' || !html.includes('authenticated-operation-station') || html.includes('data-pdc-sublet-box')) return html;
    const payload = state.payload && state.payload.ok !== false ? state.payload : null;
    const lines = Array.isArray(payload?.lines) ? payload.lines : [];
    const known = Boolean(payload) || state.known === true;
    const canTick = payload?.can_tick === true;
    const vid = idKey(state.vehicleId || payload?.vehicle_id);
    const bySource = new Map(), byLabel = new Map(), used = new Set(), linked = [], standardLines = [];
    for (const line of lines) {
      const sid = sourceId(line.line_identity);
      if (sid) bySource.set(sid, line);
      const label = lineLabel(line.operation_no);
      if (label) byLabel.set(label, byLabel.has(label) ? null : line);
    }
    const liLabels = new Map();
    for (const m of html.matchAll(LI)) { const lab = (m[3].match(LABEL) || [])[1]; if (lab) liLabels.set(unescape(lab), (liLabels.get(unescape(lab)) || 0) + 1); }
    const find = (sid, body) => {
      let line = bySource.get(sourceId(sid));
      if (!line) {
        const lab = unescape((body.match(LABEL) || [])[1] || '');
        const candidate = lab && liLabels.get(lab) === 1 ? byLabel.get(lab) : null;
        if (candidate && !sourceId(candidate.line_identity)) line = candidate;
      }
      return line && !used.has(line) ? line : null;
    };
    // Operation lines outside the Sublet box: PO reference only; the line goes to the Sublet box as a linked row.
    let out = html.replace(SECTION, (all, open, station, inner, close) => station.toUpperCase() === 'SUBLET' ? all : open + inner.replace(LI, (li, sid, attrs, body) => {
      const line = find(sid, body);
      if (!line) {
        // r747: a Pit and weigh (or other standard sublet) line without a GP PO is still a sublet; list it under Standard.
        if (standardSublet(body)) standardLines.push({ label: unescape((body.match(LABEL) || [])[1] || ''), op: unescape(((body.match(SPAN) || [])[2] || '').replace(/<[^>]*>/g, '')).trim(), category: unescape(((open.match(/data-operation-category="([^"]*)"/) || [])[1]) || '') });
        return li;
      }
      used.add(line);
      linked.push({ line, op: unescape(((body.match(SPAN) || [])[2] || '').replace(/<[^>]*>/g, '')).trim(), category: unescape(((open.match(/data-operation-category="([^"]*)"/) || [])[1]) || '') });
      const ref = isNewPo(line, vid, state.seen) ? refHtml(line).replace('class="pdc-sublet-po-ref ', 'class="pdc-sublet-po-ref is-new ') : refHtml(line);
      return `<li data-operation-source-id="${sid}"${attrs}>${addToLine(body, ref)}</li>`;
    }) + close);
    // Sublet jobs raised as their own lines: description + PO + tick, or "No PO".
    // r494b (F107): no 'Hours not stated' in the Sublet box (Craig 22 Oct 18:55); stated hours stay.
    let subletFound = false, noPo = 0;
    out = out.replace(SECTION, (all, open, station, inner, close) => {
      if (station.toUpperCase() !== 'SUBLET') return all;
      subletFound = true;
      return open + inner.replace(LI, (li, sid, attrs, rawBody) => {
        const body = stripNoHours(rawBody);
        if (body !== rawBody) li = `<li data-operation-source-id="${sid}"${attrs}>${body}</li>`;
        const line = find(sid, body);
        if (line) {
          used.add(line);
          const withDesc = body.replace(SPAN, (s, a, text, b) => `${a}${text}<small class="pdc-sublet-own-desc">${descriptionHtml(line)}</small>${b}`);
          return `<li data-operation-source-id="${sid}"${attrs} data-pdc-sublet-row="own">${addToLine(withDesc, inlineHtml(line, vid, canTick))}</li>`;
        }
        if (known) noPo += 1;
        return known ? `<li data-operation-source-id="${sid}"${attrs} data-pdc-sublet-po-to-raise data-pdc-sublet-row="own">${addToLine(body, NO_PO)}</li>` : li;
      }) + close;
    });
    // PO lines not visible above (e.g. filtered) still get their Sublet box row.
    for (const line of lines) if (!used.has(line)) linked.push({ line, op: String(line.description || ''), category: String(line.category || '').toLowerCase() });
    if (!known) return out;
    const catName = key => ({ bus_mechanical: 'Bus 4x4 Mechanical', bus_accessories: 'Bus 4x4 Accessories', bus_electrical: 'Bus 4x4 Electrical', bus_qa: 'Bus 4x4 QA', bus4x4: 'Bus 4x4', bus_pit: 'Bus 4x4 Pit',
      tint: 'Tint', hoist: 'Hoist / GVM', fitting: 'Fitting', fabrication: 'Fabrication', electrical: 'Electrical', tyre: 'Tyres' }[key] || '');
    const rows = linked.map(({ line, op, category }) => {
      const label = lineLabel(line.operation_no) || `Line ${line.line_no ?? ''}`;
      const on = [op, catName(category)].filter(Boolean).join(' · ');
      return { n: lineNo(label), html: `<li class="pdc-sublet-linked" data-pdc-sublet-row="linked" data-line-key="${esc(line.line_key || '')}"><strong>${esc(label)}</strong>`
        + `<span>${descriptionHtml(line)}<small class="pdc-sublet-on">On operation line: ${esc(on || label)}</small>${isNewPo(line, vid, state.seen) ? newPoHtml(line, vid) : ''}</span><em class="pdc-sublet-kind">Op line PO</em>${inlineHtml(line, vid, canTick)}</li>` };
    }).concat(standardLines.map(x => standardLineRow({ ...x, catName })));
    // r494: whole line sublets with no GP PO count as open ('PO to raise').
    const total = lines.length + noPo, ticked = lines.filter(l => l.ticked === true).length;
    const boxState = total === 0 ? 'none' : ticked === total ? 'done' : 'ordered';
    const boxAttrs = ` data-pdc-sublet-box data-pdc-sublet-state="${boxState}" data-pdc-sublet-count="${ticked}/${total}"`;
    if (subletFound) {
      return out.replace(SECTION, (all, open, station, inner, close) => {
        if (station.toUpperCase() !== 'SUBLET') return all;
        const own = [...inner.matchAll(/<li data-operation-source-id=[\s\S]*?<\/li>/g)].map(m => ({ n: lineNo(unescape((m[0].match(/<strong>([^<]*)<\/strong>/) || [])[1] || '')), html: m[0] }));
        const sorted = groupRowsHtml(own.concat(rows).sort((a, b) => a.n - b.n).map(r => r.html));
        const body = inner.replace(/(<ol\b[^>]*>)[\s\S]*<\/ol>/, (m, ol) => `${ol}${sorted}</ol>`);
        return open.slice(0, -1) + boxAttrs + '>' + body + close;
      });
    }
    if (!rows.length) return out;
    // No Sublet jobs: a Sublet box for the operation-line POs, after the last category box.
    const section = `<section class="authenticated-operation-station" data-operation-station="SUBLET" data-operation-category="sublet" style="--station-colour:#8c671d;--station-tint:#fbf5e5"${boxAttrs}>`
      + `<header><strong>Sublet</strong><small>${rows.length} sublet${rows.length === 1 ? '' : 's'} on operation lines</small></header><ol aria-label="Sublet jobs">${groupRowsHtml(rows.sort((a, b) => a.n - b.n).map(r => r.html))}</ol></section>`;
    const last = out.lastIndexOf('</section>');
    return last >= 0 ? out.slice(0, last + 10) + section + out.slice(last + 10) : out;
  }
  const api = { indexBoard, entryFor, boxState, decorateStrip, lineLabel, cleanDescription, poDetails, inlineHtml, refHtml, decorateOperations,
    subletJobs, poToRaise, seenKey, isNewPo, newPoHtml, stripNoHours, STANDARD_SUBLETS, standardSublet, groupRowsHtml, VERSION };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_SUBLET_PO_VERSION) return;
  window.PDC_SUBLET_PO_VERSION = VERSION;
  let index = null, lastBody = '', loading = false;
  const cache = new Map(), inflight = new Set();
  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  async function rpc(name, body) {
    const config = window.PDC_SUPABASE_CONFIG, token = window.__pdcCachedAccessToken;
    if (!token || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: config.publishableKey, Authorization: 'Bearer ' + token }, body: JSON.stringify(body || {})
    });
    const text = await response.text();
    if (!response.ok) { let m = text; try { m = JSON.parse(text).message || text; } catch (_) { /* raw */ } throw new Error(String(m || response.status)); }
    return { text, data: JSON.parse(text || 'null') };
  }
  const rerender = () => { try { if (typeof refreshAllViews === 'function') refreshAllViews(); else if (typeof renderAll === 'function') renderAll(); } catch (_) { /* next render */ } };
  /** Re-render only the open rows' operation summaries (keeps open rows and scroll in place). */
  const refreshSummaries = () => {
    try {
      if (typeof refreshAuthenticatedOperationSummaryRow !== 'function' || !document.querySelectorAll) return;
      document.querySelectorAll('[data-incoming-row][open]').forEach(row => { try { refreshAuthenticatedOperationSummaryRow(row); } catch (_) { /* next render */ } });
    } catch (_) { /* next render */ }
  };
  async function load(force) {
    if (String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'fitter') return; // r616 (F231): Fitters bay only
    if (loading || !window.__pdcCachedAccessToken || (!force && document.visibilityState === 'hidden')) return;
    loading = true;
    try {
      const { text, data } = await rpc('get_pdc_sublet_po_board_439', {});
      if (text === lastBody) return;
      lastBody = text; index = indexBoard(data);
      for (const entry of cache.values()) entry.stale = true;
      rerender(); refreshSummaries();
    } catch (_) { /* keep the last good board; the next poll retries */ }
    finally { loading = false; }
  }
  async function fetchLines(vid, redraw) {
    if (!vid || inflight.has(vid)) return;
    inflight.add(vid);
    try {
      const { data } = await rpc('get_pdc_sublet_lines_439', { p_vehicle_id: vid });
      cache.set(vid, { payload: data, stale: false });
      refreshSummaries();
      // r494c (F107b): the board never asks for these lines; when a slide-out / Manage sublets load changes this vehicle's
      // 'PO to raise' count, one debounced board redraw picks it up (no redraw per response, no loop).
      if (redraw !== false) raiseChanged(vid);
      // r494 (F107): the Manage sublets screen redraws from the same lines.
      try { window.dispatchEvent(new CustomEvent('pdc-sublet-lines', { detail: { vehicleId: vid } })); } catch (_) { /* no listener */ }
    } catch (_) { const c = cache.get(vid); if (c) c.stale = false; /* keep what is shown; the next board change retries */ }
    finally { inflight.delete(vid); }
  }
  // r494 (F107): read access for the per-vehicle Manage sublets screen (pdc-vehicle-sublets.js). Ticks still go through
  // the change listener below (set_pdc_sublet_line_tick_439); nothing here writes.
  window.PDC_SUBLET_PO = Object.freeze({ ...api, lines: vid => cache.get(String(vid || '').trim().toLowerCase())?.payload || null,
    fetch: vid => fetchLines(String(vid || '').trim().toLowerCase()), seen: () => seen, ack: keys => ack(keys) });
  const notify = (message, tone) => { try { if (typeof pdcNotify === 'function') pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  // r494 (F107): 'PO raised for this line' notes this user has acknowledged ('Got it'), kept in this browser only.
  const SEEN_KEY = () => 'pdc.sublet-new-po-seen.v1:' + String(window.PDC_AUTH_CONTEXT?.userId || '');
  let seen = new Set();
  try { seen = new Set(JSON.parse(localStorage.getItem(SEEN_KEY()) || '[]').filter(x => typeof x === 'string').slice(-2000)); } catch (_) { seen = new Set(); }
  const ack = keys => {
    for (const k of String(keys || '').split(' ').filter(Boolean)) seen.add(k);
    try { localStorage.setItem(SEEN_KEY(), JSON.stringify([...seen].slice(-2000))); } catch (_) { /* private mode: this page only */ }
    refreshSummaries();
    try { window.dispatchEvent(new CustomEvent('pdc-sublet-lines', { detail: {} })); } catch (_) { /* no listener */ }
  };
  // r494: whole line sublets with no GP PO yet: orange 'PO to raise' on the board's Sublet box.
  // r494c (F107b, site slow 22 Oct): r494 called get_pdc_sublet_lines_439 here for every vehicle with Sublet lines and a
  // GP PO, and redrew the whole board after each answer (N calls and N full redraws per render). Now the board works it
  // out from data it already has (its Sublet lines + the board entry, or lines already loaded for an opened vehicle):
  // no RPC and no redraw from inside a render.
  const shown = new Map(); // vehicle id -> { vehicle, entry, count } last drawn on the board
  const raiseFor = (vehicle, entry) => {
    if (!index || !subletJobs(vehicle).length) return 0;
    const vid = entry ? idKey(entry.vehicle_id) : '', cached = vid ? cache.get(vid) : null;
    const count = poToRaise(vehicle, entry, cached?.payload).count;
    if (vid) shown.set(vid, { vehicle, entry, count });
    return count;
  };
  let redrawTimer = 0;
  function raiseChanged(vid) {
    const last = shown.get(vid);
    if (!last || redrawTimer) return;
    if (poToRaise(last.vehicle, last.entry, cache.get(vid)?.payload).count === last.count) return;
    redrawTimer = setTimeout(() => { redrawTimer = 0; rerender(); }, 250);
  }
  if (typeof incomingWorkChecklistHtml === 'function') {
    const prior = incomingWorkChecklistHtml;
    incomingWorkChecklistHtml = (vehicle, ...args) => { const entry = entryFor(index, vehicle); return decorateStrip(prior(vehicle, ...args), entry, raiseFor(vehicle, entry)); };
  }
  if (typeof authenticatedEmailOperationLinesHtml === 'function') {
    const prior = authenticatedEmailOperationLinesHtml;
    authenticatedEmailOperationLinesHtml = function (vehicle = {}, ...args) {
      const html = prior.call(this, vehicle, ...args);
      if (!html || !index) return html;
      const entry = entryFor(index, vehicle);
      if (!entry) return decorateOperations(html, { known: true });
      const vid = idKey(entry.vehicle_id), cached = cache.get(vid);
      if (!cached || cached.stale) fetchLines(vid);
      // r494b (F107): no 'seen' list = no 'PO raised for this line' note or highlight (the GP number shows it).
      return decorateOperations(html, { vehicleId: vid, payload: cached?.payload || null });
    };
  }
  document.addEventListener('click', event => {
    const button = event.target?.closest?.('[data-pdc-sublet-ack]');
    if (!button) return;
    event.preventDefault(); event.stopPropagation();
    ack(button.dataset.pdcSubletAck);
  }, true);
  // The tick sits inside a line that may open the line editor or a booking: keep its clicks to itself.
  for (const type of ['click', 'dblclick', 'mousedown', 'pointerdown', 'touchstart', 'keydown']) {
    document.addEventListener(type, event => {
      if (event.target?.closest?.('.pdc-sublet-po-inline')) event.stopPropagation();
    }, true);
  }
  document.addEventListener('change', async event => {
    const input = event.target;
    if (!input?.classList?.contains('pdc-sublet-po-tick')) return;
    event.stopPropagation();
    const box = input.closest('.pdc-sublet-po-inline');
    const vid = box?.dataset?.pdcSubletVehicle;
    if (!box || !vid) return;
    const want = input.checked;
    input.disabled = true;
    try {
      const key = (crypto?.randomUUID?.()) || '00000000-0000-4000-8000-' + String(Date.now()).padStart(12, '0').slice(-12);
      await rpc('set_pdc_sublet_line_tick_439', { p_vehicle_id: vid, p_line_key: box.dataset.lineKey,
        p_expected_version: Number(box.dataset.version) || 0, p_ticked: want, p_idempotency_key: key });
      notify(want ? 'Ticked sublet done' : 'Sublet done unticked', 'success');
    } catch (error) {
      input.checked = !want;
      const m = String(error.message || '');
      notify(/VERSION_CONFLICT/.test(m) ? 'Someone else changed this line; reloaded.' : /UNAUTHORIZED/.test(m) ? 'Only controllers, administrators and fitters can tick sublet done.' : `Sublet done not saved: ${m}`, 'error');
    }
    await fetchLines(vid);
    load(true);
  }, true);
  const style = document.createElement('style');
  // r439c (F55): readable lines at 100% zoom. Label and hours take only their own width, the description the rest with
  // word-gap wrapping (long words break only as a last resort), and boxes wrap onto more rows instead of narrowing
  // below ~16.5rem. Scoped overrides here because styles.css is a frozen baseline; Review keeps its own layout.
  const OPS = '.authenticated-email-operations .authenticated-operation-station';
  const LINE = OPS + ':not([data-operation-station="REVIEW"]) li';
  const SUB = OPS + '[data-operation-station="SUBLET"]'; // r494b (F107)
  style.textContent = '.authenticated-email-operations .authenticated-operation-station-grid{grid-template-columns:repeat(auto-fill,minmax(min(100%,16.5rem),1fr))}'
    + LINE + '{grid-template-columns:max-content minmax(0,1fr) max-content;column-gap:.45rem;row-gap:.25rem}'
    + OPS + ' li span{min-width:0;overflow-wrap:break-word;word-break:normal}'
    + '@media (max-width:700px){.authenticated-email-operations .authenticated-operation-station-grid{grid-template-columns:1fr}}'
    + '@media (max-width:440px){' + LINE + '{grid-template-columns:auto minmax(0,1fr)}}'
    + '.pdc-sublet-po-count{font-size:9px;font-weight:700;margin-left:2px;opacity:.85}'
    + '.pdc-sublet-po-inline{display:inline-flex;flex-wrap:wrap;align-items:center;gap:4px;vertical-align:middle}'
    + '.authenticated-email-operations li>.pdc-sublet-po-inline,.authenticated-email-operations li>.pdc-sublet-po-nopo{grid-column:2/-1;justify-self:start;margin:0}'
    + '.pdc-sublet-po-chip{display:inline-block;white-space:nowrap;padding:0 5px;border-radius:4px;background:#fff7ed;border:1px solid #fdba74;color:#9a3412;font-size:11px;font-weight:650;line-height:16px}'
    + '.pdc-sublet-po-inline.is-done .pdc-sublet-po-chip{background:#f0fdf4;border-color:#86efac;color:#166534}'
    + '.pdc-sublet-po-tick{width:15px;height:15px;margin:0;cursor:pointer;accent-color:#15803d}.pdc-sublet-po-tick:disabled{cursor:default}'
    + '.pdc-sublet-po-nopo{color:#94a3b8;font-size:10.5px;font-weight:650;white-space:nowrap}'
    + '.pdc-sublet-po-unplaced{margin-top:6px;font-size:11.5px}.pdc-sublet-po-unplaced>div{padding:2px 0}'
    // r444 (F57): read-only PO reference on operation lines; descriptions in the Sublet box.
    + '.pdc-sublet-po-ref{display:inline-block;white-space:nowrap;padding:0 5px;border-radius:4px;border:1px dashed #fdba74;color:#9a3412;font-size:10.5px;font-weight:650;line-height:15px;cursor:help}'
    + '.pdc-sublet-po-ref.is-done{border-color:#86efac;color:#166534}'
    + '.authenticated-email-operations li>.pdc-sublet-po-ref{grid-column:2/-1;justify-self:start;margin:0}'
    + '.authenticated-email-operations .pdc-sublet-desc{display:block;font-weight:650;color:#1f2937;text-transform:none;letter-spacing:normal;font-size:12px}.pdc-sublet-desc+.pdc-sublet-desc{margin-top:2px}'
    + '.pdc-sublet-desc-po{font-weight:700;color:#9a3412;margin-right:3px}.pdc-sublet-desc-missing{font-weight:500;color:#94a3b8}'
    + '.authenticated-email-operations .pdc-sublet-on,.authenticated-email-operations .pdc-sublet-own-desc{display:block;font-size:10.5px;color:#64748b;font-weight:500;text-transform:none;letter-spacing:normal}.authenticated-email-operations .pdc-sublet-own-desc .pdc-sublet-desc{font-size:11.5px;color:#334155}'
    + '.pdc-sublet-kind{color:#94a3b8;font-style:normal;font-size:10px}'
    // r494 (F107): 'PO to raise' (whole line sublet without a GP PO) and 'PO raised for this line' (new GP PO on a line).
    + '.authenticated-email-operations .pdc-sublet-po-nopo{display:inline-block;padding:0 5px;border-radius:4px;background:#fff7ed;border:1px solid #fb923c;color:#c2410c;font-weight:700}'
    + '.pdc-sublet-new-po{display:inline-block;margin-top:2px;padding:0 6px;border-radius:4px;background:#fef3c7;border:1px solid #f59e0b;color:#92400e;font-size:10.5px;font-weight:700;text-transform:none;letter-spacing:normal}'
    + '.pdc-sublet-new-ack{margin-left:4px;font-size:10px;padding:0 6px;border:1px solid #cbd5e1;border-radius:4px;background:#fff;color:#334155;cursor:pointer;line-height:15px}'
    + '.pdc-sublet-po-ref.is-new{background:#fef3c7;border-style:solid;border-color:#f59e0b;color:#92400e}'
    + '.incoming-work-check.pdc-station-sublet.pdc-sublet-po-box .pdc-sublet-po-count{white-space:nowrap}'
    + '.pdc-sublet-po-raise{display:block;font-size:8px;line-height:9px;font-weight:800;letter-spacing:0;text-transform:uppercase;white-space:normal;text-align:center;color:#c2410c}'
    // r494b (F107, Craig 22 Oct 18:55): the vehicle's Sublet box is uniform: one text size, and every line's right side is
    // one chip of the same width and height (GP PO number or 'PO to raise'), lined up with the ticks.
    + SUB + ' li,' + SUB + ' li :is(strong,span,small,b,i,em){font-size:12px!important;line-height:18px;letter-spacing:normal;text-transform:none}'
    + SUB + ' li .pdc-sublet-desc,' + SUB + ' li .pdc-sublet-own-desc .pdc-sublet-desc{font-weight:650;color:#1f2937}'
    + SUB + ' li .pdc-sublet-on,' + SUB + ' li .pdc-sublet-own-desc{color:#64748b;font-weight:500}'
    + SUB + ' .pdc-sublet-kind{display:none}'
    + SUB + ' .pdc-sublet-po-chip,' + SUB + ' .pdc-sublet-po-nopo{display:inline-block;box-sizing:border-box;min-width:8.2em;padding:0 6px;border:1px solid #fdba74;border-radius:4px;background:#fff7ed;color:#9a3412;font-weight:700;text-align:center;white-space:nowrap}'
    + SUB + ' .pdc-sublet-po-nopo{border-color:#fb923c;color:#c2410c;margin-right:19px!important}'
    + SUB + ' .pdc-sublet-po-inline.is-done .pdc-sublet-po-chip{background:#f0fdf4;border-color:#86efac;color:#166534}'
    // r747 (F351): two groups in the Sublet box, each with a heading row and its own done count.
    + SUB + ' li.pdc-sublet-group{display:flex!important;align-items:center;gap:.5rem;margin-top:.35rem;padding:.25rem .55rem!important;background:#e2e8f0;border-top:2px solid #94a3b8;border-bottom:1px solid #cbd5e1}'
    + SUB + ' li.pdc-sublet-group:first-child{margin-top:0;border-top:0}'
    + SUB + ' li.pdc-sublet-group>strong{color:#1e293b;font-weight:800!important}'
    + SUB + ' li.pdc-sublet-group>span{flex:1;min-width:0;color:#64748b;font-size:10.5px!important;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}'
    + SUB + ' li.pdc-sublet-group>em{font-style:normal;font-weight:800!important;padding:0 .4rem;border-radius:999px;font-size:10.5px!important}'
    + SUB + ' li.pdc-sublet-group>em.is-ordered{background:#ffedd5;color:#9a3412;border:1px solid #fdba74}'
    + SUB + ' li.pdc-sublet-group>em.is-done{background:#dcfce7;color:#166534;border:1px solid #86efac}'
    + SUB + ' li.pdc-sublet-standard-line .pdc-sublet-kind{display:inline-block;box-sizing:border-box;min-width:8.2em;padding:0 6px;border:1px dashed #cbd5e1;border-radius:4px;color:#64748b;text-align:center;margin-right:19px!important}';
  document.head.appendChild(style);
  load();
  setInterval(load, 2 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  // r490: the 4 s retry is only for a page that had no session yet; skip it once the board has loaded.
  setTimeout(() => { if (!index) load(); }, 4000);
  const warmup = setInterval(() => { if (index) clearInterval(warmup); else load(); }, 20000);
})();
