/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/*
 * r642 (F257): Sublet page for Malaga Motor Trimmers (MMT). Craig, 28 Oct 2026.
 * Lists every vehicle at PMB with an MMT sublet line that has a GP PO: PO, key, stock, customer, vehicle, the line.
 * Two ticks per line: Built (seat covers made), then Complete. Complete is the board's 'sublet done' tick, so the
 * vehicle's Sublet box ticks off too. Reads get_pdc_mmt_sublet_board_642; writes set_pdc_mmt_sublet_tick_642.
 * Loads once when the page opens and after each tick. No polling.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.28.r642';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const FILTERS = Object.freeze({ todo: 'To build', built: 'Built', complete: 'Complete · to invoice', all: 'All' });
  const ERRORS = Object.freeze({
    not_authorized: 'Your login cannot tick MMT sublets.',
    build_first: 'Tick Built first.',
    complete_first: 'Untick Complete first.',
    complete_first_invoice: 'Tick Complete first.',
    already_invoiced: 'Already invoiced.',
    stale: 'Changed by someone else. Reloaded.',
    not_an_mmt_line: 'That line is no longer an MMT sublet.',
  });
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const ddmm = iso => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || '')); return m ? `${m[3]}/${m[2]}` : ''; };
  const lineId = line => `${line.vehicle_id}|${line.line_key}`;

  /** Which filter a line falls in. */
  function stage(line) {
    if (line?.complete) return 'complete';
    if (line?.built) return 'built';
    return 'todo';
  }
  function filterLines(lines, filter, search) {
    const q = String(search || '').trim().toLowerCase();
    return (Array.isArray(lines) ? lines : []).filter(line => {
      if (filter && filter !== 'all' && stage(line) !== filter) return false;
      if (!q) return true;
      // r642: search box matches PO number, key or stock number (key exact, ignoring a leading K and zeros).
      const key = String(line.key_number ?? '').replace(/^0+/, '').toLowerCase();
      const qKey = q.replace(/^k/, '').replace(/^0+/, '');
      return (qKey && key === qKey)
        || String(line.po_number ?? '').toLowerCase().includes(q)
        || String(line.stock_number ?? '').toLowerCase().includes(q);
    });
  }
  function counts(lines) {
    const out = { todo: 0, built: 0, complete: 0, all: 0 };
    for (const line of Array.isArray(lines) ? lines : []) { out[stage(line)] += 1; out.all += 1; }
    return out;
  }

  /** Complete bucket: a reminder to invoice. Ticking Invoiced removes the line from the page. */
  function invoiceHtml(line, canTick, pending) {
    if (!line?.complete) return '';
    return `<button type="button" class="mmt-invoice" data-mmt-invoice="${esc(lineId(line))}"${!canTick || pending ? ' disabled' : ''} title="Tick once MMT has invoiced this job. It then leaves this page.">Invoiced</button>`;
  }
  function tickHtml(line, kind, canTick, pending) {
    const on = kind === 'built' ? line.built === true : line.complete === true;
    const blocked = kind === 'complete' ? !line.built : line.complete === true;
    const disabled = !canTick || pending || blocked;
    const by = kind === 'built' ? line.built_by_email : line.complete_by_email;
    const at = kind === 'built' ? line.built_at : line.complete_at;
    const title = on ? `Ticked ${ddmm(at)}${by ? ` by ${by}` : ''}` : kind === 'complete' && !line.built ? 'Tick Built first' : kind === 'built' ? 'Seat covers built' : 'Fitted and complete';
    return `<label class="mmt-tick${on ? ' is-on' : ''}" title="${esc(title)}"><input type="checkbox" data-mmt-tick="${esc(kind)}" data-mmt-line="${esc(lineId(line))}"${on ? ' checked' : ''}${disabled ? ' disabled' : ''}><span>${kind === 'built' ? 'Built' : 'Complete'}</span></label>`;
  }

  /** Days at PMG: whole days since the vehicle got its key number. */
  function daysHtml(line) {
    const n = Number(line?.days_at_pmg);
    if (line?.days_at_pmg === null || line?.days_at_pmg === undefined || !Number.isFinite(n) || n < 0) return '';
    const tone = n >= 14 ? ' is-old' : n >= 7 ? ' is-mid' : '';
    return `<span class="mmt-days${tone}" title="Days at PMG since key number ${esc(ddmm(line.key_at))}">${n}d</span>`;
  }
  /** One QC-style card: key badge and stock, vehicle, customer, PO and job line, then the two ticks. */
  function rowHtml(line, canTick, pendingSet, errors) {
    const id = lineId(line);
    const pending = pendingSet?.has(id);
    const err = errors?.get(id);
    const key = String(line.key_number ?? '').trim();
    const pill = line.complete ? '<span class="qc-phone-pill is-invoice">To invoice</span>' : line.built ? '<span class="qc-phone-pill is-built">Built</span>' : '<span class="qc-phone-pill">To build</span>';
    return `<article class="mmt-card is-${stage(line)}">`
      + `<div class="mmt-card-top">${key ? `<span class="mmt-key-badge">K${esc(key)}</span>` : ''}${daysHtml(line)}<strong>${esc(line.stock_number || '—')}</strong>${pill}</div>`
      + `<div class="qc-phone-model">${esc(line.vehicle || 'Vehicle')}</div>`
      + `<div class="qc-phone-muted">${esc(line.customer || 'Customer unavailable')}</div>`
      + `<div class="mmt-card-po"><span>PO</span><strong>${esc(line.po_number || '—')}</strong></div>`
      + `<div class="mmt-card-line">${esc(line.description || '')}</div>`
      + `<div class="mmt-card-ticks">${tickHtml(line, 'built', canTick, pending)}${tickHtml(line, 'complete', canTick, pending)}</div>`
      + (line.complete ? `<div class="mmt-invoice-row"><span>Invoice when back in the office</span>${invoiceHtml(line, canTick, pending)}</div>` : '')
      + (err ? `<small class="mmt-error">${esc(err)}</small>` : '')
      + `</article>`;
  }

  /** Desktop table row (website view). Phones get the cards. */
  function tableRowHtml(line, canTick, pendingSet, errors) {
    const id = lineId(line);
    const pending = pendingSet?.has(id);
    const err = errors?.get(id);
    const key = String(line.key_number ?? '').trim();
    return `<tr class="mmt-row is-${stage(line)}">`
      + `<td class="mmt-po"><strong>${esc(line.po_number || '—')}</strong></td>`
      + `<td class="mmt-keycell">${key ? `<span class="mmt-key-badge is-small">K${esc(key)}</span>` : '—'}${daysHtml(line)}</td>`
      + `<td>${esc(line.stock_number || '—')}</td>`
      + `<td>${esc(line.customer || '—')}</td>`
      + `<td>${esc(line.vehicle || '—')}</td>`
      + `<td class="mmt-desc">${esc(line.description || '')}${err ? `<small class="mmt-error">${esc(err)}</small>` : ''}</td>`
      + `<td class="mmt-ticks">${tickHtml(line, 'built', canTick, pending)}${tickHtml(line, 'complete', canTick, pending)}${invoiceHtml(line, canTick, pending)}</td>`
      + `</tr>`;
  }

  function panelHtml(payload, view) {
    const lines = payload?.lines || [];
    const c = counts(lines);
    const shown = filterLines(lines, view.filter, view.search);
    const chips = Object.entries(FILTERS).map(([key, label]) =>
      `<button type="button" class="mmt-filter${view.filter === key ? ' is-active' : ''}" data-mmt-filter="${key}">${esc(label)} <span>${c[key]}</span></button>`).join('');
    const body = shown.length
      ? `<div class="mmt-desktop table-wrap"><table class="data-table mmt-table"><thead><tr><th>PO</th><th>Key · days at PMG</th><th>Stock</th><th>Customer</th><th>Vehicle</th><th>Job line</th><th>Ticks</th></tr></thead><tbody>${shown.map(line => tableRowHtml(line, payload.can_tick === true, view.pending, view.errors)).join('')}</tbody></table></div>`
        + `<div class="mmt-cards">${shown.map(line => rowHtml(line, payload.can_tick === true, view.pending, view.errors)).join('')}</div>`
      : `<p class="mmt-empty">${lines.length ? 'Nothing matches.' : 'No MMT sublets at PMB right now.'}</p>`;
    return `<div class="mmt-summary">${c.todo} to build · ${c.built} built · ${c.complete} to invoice</div>`
      + `<input type="search" inputmode="search" class="mmt-search" data-mmt-search placeholder="Search PO, key or stock number" value="${esc(view.search || '')}" aria-label="Search PO, key or stock number">`
      + `<div class="mmt-toolbar">${chips}</div>`
      + (payload.can_tick ? '' : '<p class="mmt-note">Read only. Only the MMT login, controllers, administrators and fitters can tick.</p>')
      + body;
  }

  // ---- browser only below ----
  const state = { payload: null, loading: false, error: '', view: { filter: 'todo', search: '', pending: new Set(), errors: new Map() } };
  const host = () => (typeof document !== 'undefined' ? document.getElementById('mmt-sublet-content') : null);

  async function rpc(name, body) {
    const config = root.PDC_SUPABASE_CONFIG;
    const token = typeof root.getPdcSupabaseAccessToken === 'function' ? root.getPdcSupabaseAccessToken() : '';
    if (!root.PDC_AUTH_CONTEXT?.userId || !token || config?.projectRef !== PROJECT) throw Error('Sign in to see MMT sublets.');
    const response = await fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(() => ({}));
    if (response.status === 404) throw Error('The MMT page is not on this database yet.');
    if (!response.ok) throw Error(data?.message || 'Could not load MMT sublets.');
    return data;
  }

  function render() {
    const el = host();
    if (!el) return;
    if (state.error && !state.payload) { el.innerHTML = `<p class="mmt-error">${esc(state.error)}</p>`; return; }
    if (!state.payload) { el.innerHTML = '<p class="mmt-empty">Loading…</p>'; return; }
    if (state.payload.ok === false) { el.innerHTML = `<p class="mmt-error">${esc(ERRORS[state.payload.error] || 'Not available.')}</p>`; return; }
    const focused = typeof document !== 'undefined' && document.activeElement?.matches?.('[data-mmt-search]');
    el.innerHTML = panelHtml(state.payload, state.view);
    if (focused) { const input = el.querySelector('[data-mmt-search]'); input?.focus(); input?.setSelectionRange?.(input.value.length, input.value.length); }
  }

  async function load() {
    if (state.loading) return;
    state.loading = true;
    try { state.payload = await rpc('get_pdc_mmt_sublet_board_642', {}); state.error = ''; }
    catch (error) { state.error = error?.message || 'Could not load MMT sublets.'; }
    finally { state.loading = false; render(); }
  }

  async function tick(id, kind, ticked) {
    const line = (state.payload?.lines || []).find(entry => lineId(entry) === id);
    if (!line || state.view.pending.has(id)) return;
    state.view.pending.add(id); state.view.errors.delete(id); render();
    try {
      const result = await rpc('set_pdc_mmt_sublet_tick_642', {
        p_vehicle_id: line.vehicle_id, p_line_key: line.line_key, p_kind: kind, p_ticked: ticked,
        p_expected_version: kind === 'complete' ? line.complete_version : line.built_version,
      });
      if (result?.ok !== true) state.view.errors.set(id, ERRORS[result?.error] || 'Not saved. Try again.');
    } catch (error) {
      state.view.errors.set(id, error?.message || 'Not saved. Try again.');
    } finally {
      state.view.pending.delete(id);
      await load();
    }
  }

  function wire(el) {
    if (!el || el.dataset.mmtWired) return;
    el.dataset.mmtWired = '1';
    el.addEventListener('change', event => {
      const box = event.target.closest?.('[data-mmt-tick]');
      if (box) void tick(box.dataset.mmtLine, box.dataset.mmtTick, box.checked);
    });
    el.addEventListener('click', event => {
      const invoice = event.target.closest?.('[data-mmt-invoice]');
      if (invoice) { void tick(invoice.dataset.mmtInvoice, 'invoiced', true); return; }
      const chip = event.target.closest?.('[data-mmt-filter]');
      if (chip) { state.view.filter = chip.dataset.mmtFilter; render(); }
    });
    el.addEventListener('input', event => {
      if (event.target.matches?.('[data-mmt-search]')) { state.view.search = event.target.value; render(); }
    });
  }

  const api = { VERSION, FILTERS, daysHtml, tableRowHtml, invoiceHtml, stage, filterLines, counts, tickHtml, rowHtml, panelHtml, lineId };
  if (typeof module === 'object' && module.exports) { module.exports = api; return; }
  root.PdcMmtSublet = Object.assign(api, {
    open() { wire(host()); render(); void load(); },
    close() {},
    reset() { state.payload = null; state.error = ''; state.view.pending.clear(); state.view.errors.clear(); host()?.replaceChildren(); },
  });
  root.addEventListener?.('pdc-auth-locked', () => root.PdcMmtSublet.reset());

  // r643 (F258): phones are a QC-only client (pdc-qc-mobile.js turns every view into QC except Fitters bay).
  // That file is shared byte for byte with Department 135, so the exemption lives here: this wrapper loads before
  // pdc-qc-mobile.js (deferred script vs DOMContentLoaded), so it sits inside it and turns its 'qc' back into
  // 'mmt-sublet' when the MMT page was asked for (menu tap, pmgpdc.au/mmt) or the MMT login is signed in.
  if (typeof root.showView === 'function' && typeof document !== 'undefined') {
    const phone = root.matchMedia?.('(max-width: 900px), (pointer: coarse) and (max-width: 1024px)');
    let wantMmt = root.location?.hash === '#/mmt-sublet';
    document.addEventListener('click', event => {
      const nav = event.target.closest?.('[data-view]');
      if (nav) wantMmt = nav.dataset.view === 'mmt-sublet';
    }, true);
    root.addEventListener('hashchange', () => { if (root.location.hash === '#/mmt-sublet') wantMmt = true; });
    const inner = root.showView;
    root.showView = function mmtPhoneShowView(view, options) {
      const mmtLogin = typeof root.pdcIsMmtSession === 'function' && root.pdcIsMmtSession();
      const next = view === 'qc' && phone?.matches && (wantMmt || mmtLogin) ? 'mmt-sublet' : view;
      return inner.call(this, next, options);
    };
  }
})(typeof window !== 'undefined' ? window : globalThis);
