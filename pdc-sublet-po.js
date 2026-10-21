/* r439 (F50): sublet purchase orders. Sublet contractors come on site, so no line changes category, bay or booking.
   r439b: each line with a GP PO shows its PO chip and a 'sublet done' tick inline on its own line in the vehicle
   drop-down's operations boxes (whatever its category); Sublet-box lines without a GP PO show a muted "No PO". The vehicle's Sublet box is
   orange while a GP PO exists and not all of those lines are ticked, green once they all are, and unchanged (neutral)
   when the vehicle has no GP PO. Controllers, administrators and fitters tick (the server checks again); others read. */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r439c';
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
  function boxState(entry) {
    if (!entry || !(Number(entry.total) > 0)) return null;
    const total = Number(entry.total) || 0, ticked = Number(entry.ticked) || 0, withPo = Number(entry.with_po) || 0;
    const count = `${ticked}/${total}`;
    if (entry.state === 'done') return { cls: 'is-complete', marker: '✓', count, title: `Sublet: all ${total} GP PO line${total === 1 ? '' : 's'} ticked sublet done` };
    if (entry.state === 'ordered') return { cls: 'is-ordered', marker: '!', count, title: `Sublet: ${withPo} line${withPo === 1 ? '' : 's'} with a GP PO, ${ticked} of ${total} ticked sublet done` };
    return null;
  }
  const BOX = /<(span|button)([^>]*\bclass="incoming-work-check pdc-station-sublet\b[^"]*")([^>]*)>((?:\s*<span\b[^>]*>[^<]*<\/span>)*\s*)<\/\1>/;
  /** Recolour the Sublet station box in a strip. A Sublet already marked complete on the board stays green. Idempotent. */
  function decorateStrip(html, entry) {
    const s = boxState(entry);
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
      if (s.marker && !complete) body = body.replace(/(<span class="incoming-work-box"[^>]*>)[\s\S]*?(<\/span>)/, `$1${s.marker}$2`);
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
  /** Compact inline PO chip(s) + 'sublet done' tick for one line (no caption; the tick carries a title and aria-label). */
  function inlineHtml(line, vehicleId, canTick) {
    const pos = Array.isArray(line?.po_numbers) ? line.po_numbers : [];
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
  const NO_PO = ' <span class="pdc-sublet-po-nopo" title="No GP purchase order on this Sublet line">No PO</span>';
  const SECTION = /(<section class="authenticated-operation-station" data-operation-station="([^"]*)"[^>]*>)([\s\S]*?)(<\/section>)/g;
  const LI = /<li data-operation-source-id="([^"]*)"([^>]*)>([\s\S]*?)<\/li>/g;
  const LABEL = /^\s*<strong>([^<]*)<\/strong>/;
  const unescape = text => String(text).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  // r439c (F55): the chip/tick (or "No PO") is its own grid item after the hours, so it takes a second row under the
  // description instead of widening the hours column (inside the nowrap hours it starved the description).
  function addToLine(body, extra) {
    if (/pdc-sublet-po-(inline|nopo)/.test(body)) return body;
    const em = body.indexOf('</em>');
    return em >= 0 ? body.slice(0, em + 5) + extra + body.slice(em + 5) : body + extra;
  }
  /**
   * Put each GP PO line's PO chip and 'sublet done' tick inline on its own line in the operations summary (whatever its
   * category box); Sublet-box lines without a GP PO get a muted "No PO" once the vehicle's POs are known. A PO line that
   * cannot be placed on a visible line is listed under the boxes so nothing disappears. Idempotent; never moves a line.
   * state: { vehicleId, payload (get_pdc_sublet_lines_439 result or null), known (true when the vehicle's POs are known) }.
   */
  function decorateOperations(html, state = {}) {
    if (typeof html !== 'string' || !html.includes('authenticated-operation-station')) return html;
    const payload = state.payload && state.payload.ok !== false ? state.payload : null;
    const lines = Array.isArray(payload?.lines) ? payload.lines : [];
    const known = Boolean(payload) || state.known === true;
    const canTick = payload?.can_tick === true;
    const vid = idKey(state.vehicleId || payload?.vehicle_id);
    const bySource = new Map(), byLabel = new Map(), used = new Set();
    for (const line of lines) {
      const sid = sourceId(line.line_identity);
      if (sid) bySource.set(sid, line);
      const label = lineLabel(line.operation_no);
      if (label) byLabel.set(label, byLabel.has(label) ? null : line);
    }
    const liLabels = new Map();
    for (const m of html.matchAll(LI)) { const lab = (m[3].match(LABEL) || [])[1]; if (lab) liLabels.set(unescape(lab), (liLabels.get(unescape(lab)) || 0) + 1); }
    let out = html.replace(SECTION, (all, open, station, inner, close) => open + inner.replace(LI, (li, sid, attrs, body) => {
      let line = bySource.get(sourceId(sid));
      if (!line) {
        const lab = unescape((body.match(LABEL) || [])[1] || '');
        const candidate = lab && liLabels.get(lab) === 1 ? byLabel.get(lab) : null;
        if (candidate && !sourceId(candidate.line_identity)) line = candidate;
      }
      if (line && !used.has(line)) { used.add(line); return `<li data-operation-source-id="${sid}"${attrs}>${addToLine(body, inlineHtml(line, vid, canTick))}</li>`; }
      if (station.toUpperCase() === 'SUBLET' && known) return `<li data-operation-source-id="${sid}"${attrs}>${addToLine(body, NO_PO)}</li>`;
      return li;
    }) + close);
    const rest = lines.filter(line => !used.has(line));
    if (rest.length && !out.includes('pdc-sublet-po-unplaced')) {
      const extra = `<div class="pdc-sublet-po-unplaced"><b>Sublet POs on lines not shown above</b>${rest.map(line => `<div><strong>${esc(lineLabel(line.operation_no) || `Line ${line.line_no ?? ''}`)}</strong> <span>${esc(line.description || '')}</span>${inlineHtml(line, vid, canTick)}</div>`).join('')}</div>`;
      const end = out.lastIndexOf('</div>');
      out = end >= 0 ? out.slice(0, end) + extra + out.slice(end) : out + extra;
    }
    return out;
  }
  const api = { indexBoard, entryFor, boxState, decorateStrip, lineLabel, inlineHtml, decorateOperations, VERSION };
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
  async function fetchLines(vid) {
    if (!vid || inflight.has(vid)) return;
    inflight.add(vid);
    try {
      const { data } = await rpc('get_pdc_sublet_lines_439', { p_vehicle_id: vid });
      cache.set(vid, { payload: data, stale: false });
      refreshSummaries();
    } catch (_) { const c = cache.get(vid); if (c) c.stale = false; /* keep what is shown; the next board change retries */ }
    finally { inflight.delete(vid); }
  }
  const notify = (message, tone) => { try { if (typeof pdcNotify === 'function') pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  if (typeof incomingWorkChecklistHtml === 'function') {
    const prior = incomingWorkChecklistHtml;
    incomingWorkChecklistHtml = (vehicle, ...args) => decorateStrip(prior(vehicle, ...args), entryFor(index, vehicle));
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
      return decorateOperations(html, { vehicleId: vid, payload: cached?.payload || null });
    };
  }
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
    + '.pdc-sublet-po-unplaced{margin-top:6px;font-size:11.5px}.pdc-sublet-po-unplaced>div{padding:2px 0}';
  document.head.appendChild(style);
  load();
  setInterval(load, 2 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setTimeout(load, 4000);
  const warmup = setInterval(() => { if (index) clearInterval(warmup); else load(); }, 20000);
})();
