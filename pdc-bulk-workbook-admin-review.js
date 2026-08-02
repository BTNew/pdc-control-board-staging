(function initPdcBulkWorkbookAdminReview(root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.createPdcBulkWorkbookAdminReview = api.createPdcBulkWorkbookAdminReview;
})(typeof window !== 'undefined' ? window : globalThis, function buildPdcBulkWorkbookAdminReview() {
  'use strict';

  const DEFAULT_LIMIT = 25;

  function defaultEscape(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function unwrapResponse(response) {
    if (!response || response.ok !== true) {
      const code = String(response && response.code || 'review_unavailable');
      const messages = {
        unauthorized: 'Administrator access is required.',
        invalid_review_request: 'The review request was invalid. Clear the search and try again.',
        preview_not_found: 'No guarded Excel Preview is available yet.',
      };
      throw new Error(messages[code] || 'The guarded Excel review is temporarily unavailable.');
    }
    return response.data && typeof response.data === 'object' ? response.data : {};
  }

  function reasonLabel(code) {
    const labels = {
      missing_authoritative_work_key: 'Workshop department required',
      multiple_current_identity_matches: 'Multiple current identity matches',
      partial_identity_disagreement: 'JC / Stock identity disagreement',
      operational_identity_conflict: 'Operational identity conflict',
      operational_exact_without_current_navision: 'No current Navision record',
      no_current_match: 'No current identity match',
    };
    return labels[String(code || '')] || 'Review required';
  }

  function hoursLabel(operation = {}) {
    const value = operation.estimated_hours;
    if (value === null || value === undefined || value === '') return 'Hours not supplied';
    const numeric = Number(value);
    return Number.isFinite(numeric) ? `${numeric.toFixed(2)} h` : 'Hours not supplied';
  }

  function operationHtml(operation, escape) {
    const department = operation && operation.work_key
      ? `<span class="badge ready">${escape(operation.work_key)}</span>`
      : '<span class="badge warning">Department required</span>';
    return `<li class="admin-import-operation">
      <span class="admin-import-operation-number">${escape(operation && operation.operation_no || '—')}</span>
      <span class="admin-import-operation-description">${escape(operation && operation.description || 'No description')}</span>
      <span class="admin-import-operation-hours">${escape(hoursLabel(operation))}</span>
      ${department}
    </li>`;
  }

  function rowHtml(row, escape) {
    const operations = Array.isArray(row && row.operations) ? row.operations : [];
    return `<article class="admin-import-row">
      <header class="admin-import-row-header">
        <div><span class="muted-label">JC Number</span><strong>${escape(row && row.job_card_number || '—')}</strong></div>
        <div><span class="muted-label">Stock Number</span><strong>${escape(row && row.stock_number || '—')}</strong></div>
        <div><span class="muted-label">Excel row</span><strong>${escape(row && row.row_no || '—')}</strong></div>
        <span class="badge warning">${escape(reasonLabel(row && row.reason_code))}</span>
      </header>
      <ol class="admin-import-operations">${operations.map(operation => operationHtml(operation, escape)).join('')}</ol>
    </article>`;
  }

  function summaryHtml(data, escape) {
    const accepted = Number(data.accepted_count || 0);
    const applied = Boolean(data.applied);
    return `<div class="admin-import-summary-grid">
      <div class="summary-card"><span>Excel vehicles</span><strong>${escape(data.row_count || 0)}</strong></div>
      <div class="summary-card"><span>Operations</span><strong>${escape(data.operation_count || 0)}</strong></div>
      <div class="summary-card"><span>Ready to import</span><strong>${escape(accepted)}</strong></div>
      <div class="summary-card warning"><span>Quarantined vehicles</span><strong>${escape(data.quarantine_count || 0)}</strong></div>
    </div>
    <div class="admin-import-safety-status ${accepted > 0 && !applied ? 'ready' : 'warning'}" role="status">
      <strong>${applied ? 'Operational import applied' : accepted > 0 ? 'Eligible rows await a separately confirmed Apply' : 'Review only — no live Workshop records were created'}</strong>
      <span>${accepted > 0 ? 'Only rows accepted by the guarded Preview can become operational.' : 'Assign authoritative Workshop departments and rerun Preview before any row can be applied.'}</span>
    </div>`;
  }

  function createPdcBulkWorkbookAdminReview(options = {}) {
    const client = options.client;
    const getAuthContext = typeof options.getAuthContext === 'function' ? options.getAuthContext : () => null;
    const escape = typeof options.escapeHtml === 'function' ? options.escapeHtml : defaultEscape;
    const limit = Number.isInteger(options.limit) && options.limit > 0 ? Math.min(options.limit, 100) : DEFAULT_LIMIT;
    let search = '';
    let offset = 0;
    let generation = 0;
    let destroyed = false;
    let host = null;

    function isAdministrator() {
      const context = getAuthContext() || {};
      return context.role === 'administrator';
    }

    function deniedHtml() {
      return '<div class="empty-state compact-empty"><strong>Administrator access required</strong><span>This page contains protected Excel import evidence.</span></div>';
    }

    function loadingHtml() {
      return '<div class="empty-state compact-empty"><strong>Loading Excel import review…</strong><span>Reading the latest guarded staging Preview.</span></div>';
    }

    function wire(data) {
      if (!host || destroyed) return;
      const form = host.querySelector('[data-admin-import-search-form]');
      const input = host.querySelector('[data-admin-import-search]');
      const clear = host.querySelector('[data-admin-import-clear]');
      const previous = host.querySelector('[data-admin-import-previous]');
      const next = host.querySelector('[data-admin-import-next]');
      if (form) form.addEventListener('submit', event => {
        event.preventDefault();
        search = String(input && input.value || '').trim().slice(0, 100);
        offset = 0;
        load();
      });
      if (clear) clear.addEventListener('click', () => {
        search = '';
        offset = 0;
        load();
      });
      if (previous) previous.addEventListener('click', () => {
        offset = Math.max(0, offset - limit);
        load();
      });
      if (next) next.addEventListener('click', () => {
        offset += limit;
        load();
      });
      if (input && search) {
        input.value = search;
      }
      if (data && data.total_matches === 0 && input) input.focus();
    }

    function renderData(data) {
      const rows = Array.isArray(data.rows) ? data.rows : [];
      const total = Number(data.total_matches || 0);
      const first = total ? Number(data.offset || 0) + 1 : 0;
      const last = total ? Math.min(total, Number(data.offset || 0) + rows.length) : 0;
      host.innerHTML = `${summaryHtml(data, escape)}
        <section class="panel admin-import-review-panel">
          <div class="panel-header">
            <div><h2>Excel import rows</h2><p>Protected Administrator view of the latest guarded workbook Preview. These rows are evidence, not active vehicle cards.</p></div>
            <div class="admin-import-preview-meta"><span>Preview</span><code>${escape(data.preview_id || '—')}</code></div>
          </div>
          <form class="admin-import-search" data-admin-import-search-form role="search">
            <label><span>Find JC, Stock or operation</span><input type="search" maxlength="100" value="${escape(search)}" data-admin-import-search placeholder="Search the Excel Preview" /></label>
            <button class="primary" type="submit">Find</button>
            <button class="small-button" type="button" data-admin-import-clear>Clear</button>
          </form>
          <div class="admin-import-result-meta" aria-live="polite">Showing ${escape(first)}–${escape(last)} of ${escape(total)} matching vehicles</div>
          <div class="admin-import-row-list">${rows.length ? rows.map(row => rowHtml(row, escape)).join('') : '<div class="empty-state compact-empty"><strong>No matching Excel rows</strong><span>Clear the search to show all quarantined rows.</span></div>'}</div>
          <div class="admin-import-pagination">
            <button class="small-button" type="button" data-admin-import-previous ${data.has_previous ? '' : 'disabled'}>Previous</button>
            <span>Page ${escape(total ? Math.floor(Number(data.offset || 0) / limit) + 1 : 1)}</span>
            <button class="small-button" type="button" data-admin-import-next ${data.has_next ? '' : 'disabled'}>Next</button>
          </div>
        </section>`;
      wire(data);
    }

    async function load() {
      const requestGeneration = ++generation;
      if (!host || destroyed) return;
      if (!isAdministrator()) {
        host.innerHTML = deniedHtml();
        return;
      }
      if (!client || typeof client.rpc !== 'function') {
        host.innerHTML = '<div class="empty-state compact-empty"><strong>Import review unavailable</strong><span>The shared staging connection is not ready.</span></div>';
        return;
      }
      host.innerHTML = loadingHtml();
      const { data, error } = await client.rpc('read_pdc_bulk_workbook_review', {
        p_preview_id: null,
        p_search: search,
        p_limit: limit,
        p_offset: offset,
      });
      if (destroyed || requestGeneration !== generation || !host) return;
      if (error) {
        host.innerHTML = '<div class="empty-state compact-empty"><strong>Could not load Excel import review</strong><span>The guarded staging service did not return a page. Try again.</span></div>';
        return;
      }
      try {
        renderData(unwrapResponse(data));
      } catch (errorResponse) {
        host.innerHTML = `<div class="empty-state compact-empty"><strong>Could not load Excel import review</strong><span>${escape(errorResponse.message)}</span></div>`;
      }
    }

    function render(nextHost) {
      host = nextHost || host;
      destroyed = false;
      return load();
    }

    function destroy() {
      destroyed = true;
      generation += 1;
      if (host) host.replaceChildren();
      host = null;
    }

    return Object.freeze({ render, destroy });
  }

  return Object.freeze({ createPdcBulkWorkbookAdminReview, unwrapResponse, reasonLabel, hoursLabel });
});
