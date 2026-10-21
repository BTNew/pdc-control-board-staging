/* r439 (F50): sublet purchase orders. Sublet contractors come on site, so no line changes category, bay or booking.
   Each line with a GP PO shows its PO and a 'sublet done' tick on the vehicle drop-down. The vehicle's Sublet box is
   orange while a GP PO exists and not all of those lines are ticked, green once they all are, and unchanged (neutral)
   when the vehicle has no GP PO. Controllers, administrators and fitters tick (the server checks again); others read. */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r439';
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
  /** The drop-down section: one row per line with a GP PO (any category), its PO, status and 'sublet done' tick (read only without can_tick). */
  function linesHtml(payload) {
    if (!payload || payload.ok === false) return '<b>Sublet POs</b><small>Sublet POs could not be loaded.</small>';
    const lines = Array.isArray(payload.lines) ? payload.lines : [];
    if (!lines.length) return '<b>Sublet POs</b><small>No GP PO lines on this vehicle.</small>';
    const canTick = payload.can_tick === true;
    const rows = lines.map(line => {
      const pos = Array.isArray(line.po_numbers) ? line.po_numbers : [];
      const status = line.ticked ? 'Sublet done' : line.completed ? 'Ordered · line completed' : 'Ordered';
      const tone = line.ticked ? 'done' : 'ordered';
      const by = line.ticked && line.ticked_at ? `<small>${esc(line.ticked_by_email || '')} ${esc(when(line.ticked_at))}</small>` : '';
      const disabled = !canTick || !line.tickable ? ' disabled' : '';
      const tip = !canTick ? 'Read only: controllers, administrators and fitters tick sublet done' : line.ticked ? 'Untick (sublet not done)' : 'Tick when the sublet contractor has done this line';
      return `<tr class="pdc-sublet-po-line is-${tone}" data-line-key="${esc(line.line_key || '')}" data-version="${esc(Number(line.version) || 0)}">`
        + `<td>${esc(line.job_card_number || '')}${line.line_no != null ? ` · ${esc(line.line_no)}` : ''}</td>`
        + `<td>${esc(line.description || '')}</td><td>${esc(line.category || '')}</td>`
        + `<td>${pos.length ? pos.map(po => `<span class="pdc-sublet-po-chip">${esc(po)}</span>`).join(' ') : ''}</td>`
        + `<td><span class="pdc-sublet-po-status">${status}</span></td>`
        + `<td><label title="${esc(tip)}"><input type="checkbox" class="pdc-sublet-po-tick"${line.ticked ? ' checked' : ''}${disabled} aria-label="${esc(`Line ${line.line_no ?? ''} sublet done`)}"> Sublet done</label>${by}</td></tr>`;
    }).join('');
    const total = Number(payload.total) || lines.length, ticked = Number(payload.ticked) || 0;
    return `<b>Sublet POs</b><small>${ticked} of ${total} ticked sublet done${canTick ? '' : ' · read only'}</small>`
      + `<table class="pdc-sublet-po-table"><thead><tr><th>Line</th><th>Description</th><th>Category</th><th>PO</th><th>Status</th><th>Sublet done</th></tr></thead><tbody>${rows}</tbody></table>`;
  }
  function placeholderHtml(vehicleId) {
    return `<div class="tune-service-location-job pdc-sublet-po-detail" data-pdc-sublet-vehicle="${esc(vehicleId)}"><b>Sublet POs</b><small>Open to load…</small></div>`;
  }
  /** Add the drop-down section only when the vehicle has a line with a GP PO (a board entry). */
  function decorateDetail(html, vehicleId, entry) {
    if (typeof html !== 'string' || !entry || !UUID.test(idKey(vehicleId)) || html.includes('pdc-sublet-po-detail')) return html;
    return html.replace('<div class="incoming-vehicle-detail-grid">', '<div class="incoming-vehicle-detail-grid">' + placeholderHtml(idKey(vehicleId)));
  }
  const api = { indexBoard, entryFor, boxState, decorateStrip, linesHtml, decorateDetail, placeholderHtml, VERSION };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_SUBLET_PO_VERSION) return;
  window.PDC_SUBLET_PO_VERSION = VERSION;
  let index = null, lastBody = '', loading = false;
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
  async function load(force) {
    if (loading || !window.__pdcCachedAccessToken || (!force && document.visibilityState === 'hidden')) return;
    loading = true;
    try {
      const { text, data } = await rpc('get_pdc_sublet_po_board_439', {});
      if (text === lastBody) return;
      lastBody = text; index = indexBoard(data);
      rerender();
    } catch (_) { /* keep the last good board; the next poll retries */ }
    finally { loading = false; }
  }
  const notify = (message, tone) => { try { if (typeof pdcNotify === 'function') pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  async function fill(box) {
    const vid = box?.dataset?.pdcSubletVehicle;
    if (!vid || box.dataset.loading === '1') return;
    box.dataset.loading = '1';
    try { box.innerHTML = linesHtml((await rpc('get_pdc_sublet_lines_439', { p_vehicle_id: vid })).data); }
    catch (error) { box.innerHTML = `<b>Sublet POs</b><small>${esc(error.message || 'Could not load')}</small>`; }
    finally { box.dataset.loading = ''; }
  }
  if (typeof incomingWorkChecklistHtml === 'function') {
    const prior = incomingWorkChecklistHtml;
    incomingWorkChecklistHtml = (vehicle, ...args) => {
      const html = prior(vehicle, ...args);
      return decorateStrip(html, entryFor(index, vehicle));
    };
  }
  if (typeof incomingVehicleDetailRow === 'function') {
    const prior = incomingVehicleDetailRow;
    incomingVehicleDetailRow = (vehicle, ...args) => {
      const html = prior(vehicle, ...args);
      const entry = entryFor(index, vehicle);
      return decorateDetail(html, entry?.vehicle_id || vehicleIds(vehicle)[0], entry);
    };
  }
  document.addEventListener('toggle', event => {
    const details = event.target;
    if (!details?.open || !details.querySelector) return;
    details.querySelectorAll('.pdc-sublet-po-detail').forEach(fill);
  }, true);
  document.addEventListener('change', async event => {
    const input = event.target;
    if (!input?.classList?.contains('pdc-sublet-po-tick')) return;
    const row = input.closest('tr'), box = input.closest('.pdc-sublet-po-detail');
    if (!row || !box) return;
    const want = input.checked;
    input.disabled = true;
    try {
      const key = (crypto?.randomUUID?.()) || '00000000-0000-4000-8000-' + String(Date.now()).padStart(12, '0').slice(-12);
      const { data } = await rpc('set_pdc_sublet_line_tick_439', { p_vehicle_id: box.dataset.pdcSubletVehicle, p_line_key: row.dataset.lineKey,
        p_expected_version: Number(row.dataset.version) || 0, p_ticked: want, p_idempotency_key: key });
      notify(want ? 'Ticked sublet done' : 'Sublet done unticked', 'success');
      if (data?.vehicle_state?.state) lastBody = '';
    } catch (error) {
      input.checked = !want;
      const m = String(error.message || '');
      notify(/VERSION_CONFLICT/.test(m) ? 'Someone else changed this line; reloaded.' : /UNAUTHORIZED/.test(m) ? 'Only controllers, administrators and fitters can tick sublet done.' : `Sublet done not saved: ${m}`, 'error');
    }
    await fill(box);
    load(true);
  });
  const style = document.createElement('style');
  style.textContent = '.pdc-sublet-po-count{font-size:9px;font-weight:700;margin-left:2px;opacity:.85}'
    + '.pdc-sublet-po-detail{grid-column:1/-1}.pdc-sublet-po-table{width:100%;border-collapse:collapse;font-size:11.5px;margin-top:3px}'
    + '.pdc-sublet-po-table th,.pdc-sublet-po-table td{text-align:left;padding:2px 5px;border-bottom:1px solid #e5e7eb;vertical-align:top}'
    + '.pdc-sublet-po-table td small{display:block;color:#6b7280;font-size:10px}'
    + '.pdc-sublet-po-chip{display:inline-block;padding:0 5px;border-radius:4px;background:#fff7ed;border:1px solid #fdba74;color:#9a3412;font-weight:650}'
    + '.pdc-sublet-po-line.is-done .pdc-sublet-po-status{color:#15803d;font-weight:700}'
    + '.pdc-sublet-po-line.is-ordered .pdc-sublet-po-status{color:#c2410c;font-weight:700}';
  document.head.appendChild(style);
  load();
  setInterval(load, 2 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setTimeout(load, 4000);
  const warmup = setInterval(() => { if (index) clearInterval(warmup); else load(); }, 20000);
})();
