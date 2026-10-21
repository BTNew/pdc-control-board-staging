/* r436 (F47): parts ETA from parts-staff emails, shown next to the parts location on board vehicle rows. Read only. */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r436';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const iso = value => /^\d{4}-\d{2}-\d{2}/.test(String(value || '')) ? String(value).slice(0, 10) : '';
  const ddmm = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}` : ''; };
  const ddmmyy = value => { const d = iso(value); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(2, 4)}` : ''; };
  const stockKey = value => String(value ?? '').trim().toUpperCase();
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
  /** Label, tooltip and colour for one vehicle: latest ETA plus a count; overdue (before today, Perth) is red, due today amber. */
  function summarise(entry, today) {
    if (!entry || !iso(entry.latest_eta)) return null;
    const parts = Array.isArray(entry.parts) ? entry.parts : [];
    const count = Number(entry.count) || parts.length || 1;
    const overdue = parts.filter(p => today && iso(p.eta_date) && iso(p.eta_date) < today).length;
    const dueToday = parts.some(p => today && iso(p.eta_date) === today);
    const state = overdue ? 'overdue' : dueToday ? 'due' : 'ok';
    const label = `Parts ETA ${ddmm(entry.latest_eta)}${count > 1 ? ` · ${count} parts` : ''}`;
    const lines = parts.map(p => {
      const bits = [`${p.part || 'Part'}: ${ddmmyy(p.eta_date)}`];
      if (today && iso(p.eta_date) < today) bits.push('OVERDUE');
      if (p.line_no) bits.push(`line ${p.line_no}`);
      if (p.ro) bits.push(`R/O ${p.ro}`);
      if (p.bay) bits.push(`bay ${p.bay}`);
      if (p.notes) bits.push(String(p.notes));
      return bits.join(' · ');
    });
    const title = [`Parts ETA (Perth), latest ${ddmmyy(entry.latest_eta)}${overdue ? `, ${overdue} overdue` : ''}`, ...lines].join('\n');
    return { label, title, state, count, overdue };
  }
  function chipHtml(summary) {
    if (!summary) return '';
    return `<span class="pdc-parts-eta pdc-parts-eta-${summary.state}" title="${esc(summary.title)}" aria-label="${esc(summary.title)}">${esc(summary.label)}</span>`;
  }
  /** Put the chip beside the parts location (Tune Tag) on a board row; without a parts location, at the right of the vehicle name. */
  function decorateRow(html, summary) {
    const chip = chipHtml(summary);
    if (!chip || typeof html !== 'string' || html.includes('class="pdc-parts-eta ')) return html;
    const location = /(<span class="tune-parts-location"[^>]*>[\s\S]*?<\/span>)/;
    if (location.test(html)) return html.replace(location, (_, loc) => `<span class="pdc-parts-eta-wrap">${loc}${chip}</span>`);
    return html.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)/, (_, start) => `${start}<span class="pdc-parts-eta-wrap">${chip}</span>`);
  }
  function detailHtml(entry, today) {
    const s = summarise(entry, today);
    if (!s) return '';
    const rows = (entry.parts || []).map(p => `<span class="${today && iso(p.eta_date) < today ? 'pdc-parts-eta-overdue' : ''}">${esc(p.part)}: ${esc(ddmmyy(p.eta_date))}${p.line_no ? ` · line ${esc(p.line_no)}` : ''}${p.bay ? ` · bay ${esc(p.bay)}` : ''}</span>`).join('');
    return `<div class="tune-service-location-job pdc-parts-eta-detail"><b>Parts ETA</b>${rows}<small>From parts staff emails (Perth dates)</small></div>`;
  }
  if (typeof module !== 'undefined') module.exports = { indexBoard, entryFor, summarise, chipHtml, decorateRow, detailHtml, ddmm, ddmmyy, VERSION };
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_PARTS_ETA_VERSION) return;
  window.PDC_PARTS_ETA_VERSION = VERSION;
  let index = null, lastBody = '', loading = false;
  async function load() {
    const config = window.PDC_SUPABASE_CONFIG, token = window.__pdcCachedAccessToken;
    if (loading || !token || config?.url?.replace(/\/$/, '') !== `https://${PROJECT}.supabase.co` || document.visibilityState === 'hidden') return;
    loading = true;
    try {
      const response = await fetch(config.url.replace(/\/$/, '') + '/rest/v1/rpc/get_pdc_parts_eta_board', {
        method: 'POST', headers: { 'Content-Type': 'application/json', apikey: config.publishableKey, Authorization: 'Bearer ' + token }, body: '{}'
      });
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
      return decorateRow(html, summarise(entry, index.today))
        .replace('<div class="incoming-vehicle-detail-grid">', '<div class="incoming-vehicle-detail-grid">' + detailHtml(entry, index.today));
    };
  }
  const style = document.createElement('style');
  style.textContent = '.incoming-card-main:has(.pdc-parts-eta-wrap){display:grid!important;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:6px!important}'
    + '.pdc-parts-eta-wrap{display:flex;flex-direction:column;align-items:flex-end;gap:2px;min-width:0}'
    + '.pdc-parts-eta{font-size:10.5px;font-weight:650;line-height:1.2;white-space:nowrap;padding:1px 5px;border-radius:4px;background:#e0f2fe;color:#075985}'
    + '.pdc-parts-eta-due{background:#fef3c7;color:#92400e}.pdc-parts-eta-overdue{background:#fee2e2;color:#b91c1c}'
    + '.pdc-parts-eta-detail span{display:block}.pdc-parts-eta-detail span.pdc-parts-eta-overdue{background:none;font-weight:650}';
  document.head.appendChild(style);
  load();
  setInterval(load, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  setTimeout(load, 4000);
  const warmup = setInterval(() => { if (index) clearInterval(warmup); else load(); }, 20000);
})();
