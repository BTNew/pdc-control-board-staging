'use strict';

// Staging-only, authenticated, read-only review of Craig's supplied PMB key list.
// This module never writes vehicles, work items, parts, bookings or browser storage.
(() => {
  const state = { status: 'idle', rows: [], work: new Map(), parts: new Map(), error: '' };
  const byId = id => document.getElementById(id);
  const clean = value => String(value ?? '').trim();
  const html = value => clean(value).replace(/[&<>"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[char]));
  const review = row => row?.source_payload?.key_list_review || {};
  const receipt = row => clean(review(row).receipt_id);
  const location = row => clean(row.current_location || review(row)?.location?.value || 'Unconfirmed');
  const confidence = row => clean(review(row)?.location?.confidence || 'low');
  const confidenceLabel = value => ({
    authoritative_existing: 'Existing staging location',
    high: 'High-confidence source evidence',
    medium: 'Best guess — review',
    low: 'Low-confidence guess — review',
  }[value] || 'Review required');
  const workLabel = key => ({
    bus4x4: 'Bus4x4', tint: 'Tint', fabrication: 'Fabrication', hoist: 'Hoist', fitting: 'Fitting',
    electrical: 'Electrical', tyre: 'Tyre', pitInspection: 'Pit inspection', sublet: 'Sublet',
  }[key] || key);

  function setStatus(message) {
    const count = byId('key-list-review-count');
    if (count) count.textContent = message;
  }

  async function fetchInBatches(client, table, columns, ids) {
    const rows = [];
    for (let index = 0; index < ids.length; index += 80) {
      const batch = ids.slice(index, index + 80);
      const result = await client.from(table).select(columns).in('vehicle_id', batch).limit(1000);
      if (result.error) throw result.error;
      rows.push(...(result.data || []));
    }
    return rows;
  }

  function populateLocations() {
    const select = byId('key-list-review-location');
    if (!select) return;
    const selected = select.value;
    const values = [...new Set(state.rows.map(location))].sort((a, b) => a.localeCompare(b, 'en-AU', { numeric: true }));
    select.innerHTML = '<option value="">All locations</option>' + values.map(value => `<option value="${html(value)}">${html(value)}</option>`).join('');
    if (values.includes(selected)) select.value = selected;
  }

  function filteredRows() {
    const query = clean(byId('key-list-review-search')?.value).toLowerCase();
    const selectedLocation = clean(byId('key-list-review-location')?.value);
    const selectedConfidence = clean(byId('key-list-review-confidence')?.value);
    return state.rows.filter(row => {
      const meta = review(row);
      const haystack = [row.key_number, row.pmb_key_tag, row.stock_number, row.toyota_order_number, row.model, location(row), meta.source_dealer, meta.identity_review_reason].join(' ').toLowerCase();
      return (!query || haystack.includes(query))
        && (!selectedLocation || location(row) === selectedLocation)
        && (!selectedConfidence || confidence(row) === selectedConfidence);
    });
  }

  function actualWork(row) {
    return (state.work.get(row.id) || [])
      .filter(item => item.required)
      .sort((a, b) => workLabel(a.work_key).localeCompare(workLabel(b.work_key)))
      .map(item => `${workLabel(item.work_key)}${item.completed ? ' ✓' : ''}`);
  }

  function partsLabel(row) {
    const item = state.parts.get(row.id);
    if (!item || !item.parts_required) return 'Not required / unknown';
    if (item.parts_received) return 'Received ✓';
    if (item.parts_ordered) return 'Ordered';
    return 'Required — not ordered';
  }

  function renderSummary() {
    const host = byId('key-list-review-summary');
    if (!host) return;
    if (state.status !== 'ready') {
      host.innerHTML = state.status === 'error'
        ? `<div class="scan-line"><span>Load failed</span><strong>${html(state.error)}</strong></div>`
        : '<div class="scan-line"><span>Review data</span><strong>Loading…</strong></div>';
      return;
    }
    const locations = {};
    state.rows.forEach(row => { const key = location(row); locations[key] = (locations[key] || 0) + 1; });
    const identityReview = state.rows.filter(row => review(row).identity_review_required).length;
    const ambiguous = state.rows.filter(row => review(row).ambiguous_hoist_exclusion).length;
    host.innerHTML = `
      <div class="scan-line"><span>Key-list rows</span><strong>${state.rows.length}</strong></div>
      <div class="scan-line"><span>Proposed locations</span><strong>${html(Object.entries(locations).map(([key, value]) => `${key} ${value}`).join(' · '))}</strong></div>
      <div class="scan-line"><span>Identity review</span><strong>${identityReview}</strong></div>
      <div class="scan-line"><span>Protected Hoist exclusions</span><strong>${ambiguous}</strong></div>`;
  }

  function render() {
    renderSummary();
    const host = byId('key-list-review-content');
    if (!host) return;
    if (state.status === 'loading') {
      host.innerHTML = '<div class="empty-state compact-empty"><strong>Loading authenticated staging review…</strong></div>';
      return;
    }
    if (state.status === 'error') {
      host.innerHTML = `<div class="empty-state compact-empty"><strong>Review unavailable</strong><span>${html(state.error)}</span></div>`;
      return;
    }
    if (state.status !== 'ready') {
      host.innerHTML = '<div class="empty-state compact-empty"><strong>Sign in to load the review</strong></div>';
      return;
    }
    const rows = filteredRows();
    setStatus(`${rows.length} of ${state.rows.length} rows`);
    if (!rows.length) {
      host.innerHTML = '<div class="empty-state compact-empty"><strong>No matching key-list rows</strong><span>Clear the review filters to show all rows.</span></div>';
      return;
    }
    host.innerHTML = `<div class="parts-table-wrap"><table class="data-table compact-table key-list-review-table">
      <thead><tr><th>Key</th><th>Stock</th><th>Order</th><th>Vehicle</th><th>Proposed location</th><th>Evidence</th><th>Work required</th><th>Parts</th><th>Review note</th></tr></thead>
      <tbody>${rows.map(row => {
        const meta = review(row);
        const work = actualWork(row);
        const note = meta.ambiguous_hoist_exclusion
          ? 'Protected legacy Hoist ambiguity — operational fields unchanged'
          : (meta.identity_review_required ? (meta.identity_review_reason || 'Identity requires review') : (meta.location?.basis || 'Source-backed proposal'));
        return `<tr data-key-list-review-row="${html(row.id)}">
          <td>${html(row.key_number || row.pmb_key_tag || '—')}</td>
          <td>${html(row.stock_number || '—')}</td>
          <td>${html(row.toyota_order_number || '—')}</td>
          <td>${html(row.model || '—')}</td>
          <td><strong>${html(location(row))}</strong></td>
          <td>${html(confidenceLabel(confidence(row)))}</td>
          <td>${html(work.length ? work.join(' · ') : 'No required work recorded')}</td>
          <td>${html(partsLabel(row))}</td>
          <td>${html(note)}</td>
        </tr>`;
      }).join('')}</tbody></table></div>`;
  }

  async function load() {
    const client = window.PDC_SUPABASE;
    if (!window.PDC_AUTH_CONTEXT || !client || typeof client.from !== 'function') {
      state.status = 'idle'; state.rows = []; state.work = new Map(); state.parts = new Map(); state.error = '';
      setStatus('Not loaded'); render(); return;
    }
    state.status = 'loading'; state.error = ''; setStatus('Loading…'); render();
    try {
      const vehicles = await client.from('vehicles')
        .select('id,stock_number,toyota_order_number,key_number,pmb_key_tag,model,lifecycle_state,visible_on_board,current_location,source_payload')
        .not('source_payload->key_list_review->>receipt_id', 'is', null)
        .order('stock_number', { ascending: true, nullsFirst: false })
        .limit(1000);
      if (vehicles.error) throw vehicles.error;
      const rows = vehicles.data || [];
      const ids = rows.map(row => row.id);
      const [workRows, partsRows] = ids.length ? await Promise.all([
        fetchInBatches(client, 'vehicle_work_items', 'vehicle_id,work_key,required,completed', ids),
        fetchInBatches(client, 'vehicle_parts_updates', 'vehicle_id,parts_required,parts_ordered,parts_received', ids),
      ]) : [[], []];
      const work = new Map();
      workRows.forEach(item => { const bucket = work.get(item.vehicle_id) || []; bucket.push(item); work.set(item.vehicle_id, bucket); });
      state.parts = new Map(partsRows.map(item => [item.vehicle_id, item]));
      state.rows = rows; state.work = work; state.status = 'ready';
      populateLocations(); render();
    } catch (error) {
      state.status = 'error'; state.error = clean(error?.message || error || 'Unknown read error'); setStatus('Load failed'); render();
    }
  }

  function bind() {
    byId('key-list-review-refresh')?.addEventListener('click', load);
    ['key-list-review-search', 'key-list-review-location', 'key-list-review-confidence'].forEach(id => {
      byId(id)?.addEventListener(id.endsWith('search') ? 'input' : 'change', render);
    });
    document.querySelector('.nav-item[data-view="backend"]')?.addEventListener('click', () => {
      if (state.status === 'idle' || state.status === 'error') load(); else render();
    });
  }

  window.PDC_KEY_LIST_REVIEW = Object.freeze({ load, render, getState: () => ({ status: state.status, count: state.rows.length }) });
  window.addEventListener('pdc-auth-ready', load);
  window.addEventListener('pdc-auth-locked', () => { state.status = 'idle'; state.rows = []; state.work = new Map(); state.parts = new Map(); render(); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind, { once: true }); else bind();
  setTimeout(() => { if (window.PDC_AUTH_CONTEXT) load(); }, 0);
})();
