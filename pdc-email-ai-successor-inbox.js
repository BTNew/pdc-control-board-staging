'use strict';

/*
 * STAGING-only, read-only UI for the PDC Email AI transaction successor.
 * It consumes one protected read RPC and never exposes raw evidence or writes.
 */
const PDC_EMAIL_AI_SUCCESSOR_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const PDC_EMAIL_AI_SUCCESSOR_INBOX_RPC = 'get_pdc_email_ai_transaction_successor_inbox_v2';
const PDC_EMAIL_AI_SUCCESSOR_REVISION_TABLE = 'pdc_email_ai_successor_ui_revision';
const ALLOWED_READ_ROLES = new Set(['viewer', 'operator', 'administrator']);
const FORBIDDEN_KEY = /(raw[_-]?body|parsed[_-]?text|extracted[_-]?text|storage[_-]?path|access[_-]?token|refresh[_-]?token|password|secret|credential|authorization|api[_-]?key|private[_-]?key|windows[_-]?log|log[_-]?path)/i;
const MAX_DETAIL_JSON = 50000;

function pdcEmailAiSuccessorProjectRef(url = '') {
  const match = String(url || '').trim().match(/^https:\/\/([a-z0-9]+)\.supabase\.co(?:\/|$)/i);
  return match ? match[1].toLowerCase() : '';
}

function text(value, fallback = '—') {
  if (value === null || value === undefined || value === '') return fallback;
  return String(value);
}

function escapeHtml(value) {
  return text(value, '').replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[character]));
}

function safeJson(value) {
  const encoded = JSON.stringify(value ?? null, null, 2) || 'null';
  return escapeHtml(encoded.slice(0, MAX_DETAIL_JSON));
}

function assertSafeProjection(value, path = '$') {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertSafeProjection(entry, `${path}[${index}]`));
    return value;
  }
  if (!value || typeof value !== 'object') return value;
  Object.entries(value).forEach(([key, entry]) => {
    if (FORBIDDEN_KEY.test(key)) throw new Error(`unsafe_snapshot:${path}.${key}`);
    assertSafeProjection(entry, `${path}.${key}`);
  });
  return value;
}

function cloneSafe(value) {
  const cloned = JSON.parse(JSON.stringify(value ?? null));
  assertSafeProjection(cloned);
  return cloned;
}

function normalizeAction(action = {}) {
  return {
    action_type: text(action.action_type, 'unknown_action'),
    instruction_id: text(action.instruction_id, '—'),
    canonical_rpc: text(action.canonical_rpc, 'Not dispatched'),
    disposition: text(action.disposition, 'BLOCKED_EXACT_REASON'),
    reason: text(action.reason, 'No reason supplied'),
    before: action.before ?? action.before_state ?? null,
    requested: action.requested ?? action.payload ?? null,
    result: action.result ?? action.after ?? action.after_state ?? null,
    expected: action.expected ?? action.verification?.expected ?? null,
    actual: action.actual ?? action.verification?.actual ?? null,
    verification: action.verification ?? { checked: false, parity: false },
    evidence_refs: Array.isArray(action.evidence_refs) ? action.evidence_refs : [],
    action_receipt_id: text(action.action_receipt_id, '—'),
    action_key: text(action.action_key, '—'),
  };
}

function normalizeVehicleResult(vehicle = {}) {
  return {
    vehicle_id: text(vehicle.vehicle_id, 'unresolved'),
    stock: text(vehicle.stock ?? vehicle.stock_number, 'Unresolved stock'),
    vehicle: text(vehicle.vehicle ?? vehicle.vehicle_description, 'Vehicle identity unavailable'),
    location: text(vehicle.location ?? vehicle.current_location, '—'),
    identity_status: text(vehicle.identity_status, vehicle.vehicle_id === 'unresolved' ? 'UNRESOLVED' : 'MATCHED'),
    actions: (Array.isArray(vehicle.actions) ? vehicle.actions : []).map(normalizeAction),
    readback: vehicle.readback ?? null,
  };
}

function normalizeSuccessorInboxSnapshot(raw = {}) {
  try {
    const source = cloneSafe(raw);
    if (source?.ok === false) return { ok: false, code: text(source.code, 'snapshot_unavailable'), revision: null, items: [] };
    const items = Array.isArray(source?.items) ? source.items : [];
    return {
      ok: true,
      code: text(source.code, 'snapshot'),
      revision: source.revision ?? null,
      has_more: source.has_more === true,
      next_cursor: source.next_cursor ?? null,
      items: items.map(item => ({
        intake_uid: text(item.intake_uid ?? item.provider_uid, '—'),
        provider_uid: text(item.provider_uid, '—'),
        source_receipt_id: text(item.source_receipt_id ?? item.intake_id, '—'),
        message_id: text(item.message_id, '—'),
        thread_id: text(item.thread_id, '—'),
        received_at: item.received_at ?? item.source_received_at ?? null,
        sender: text(item.sender ?? item.sender_address, 'Unknown sender'),
        subject: text(item.subject, 'Email received'),
        attachment_summary: item.attachment_summary ?? { count: 0, names: [] },
        job_card_summary: item.job_card_summary ?? { job_card_number: '', operation_count: 0, extraction_status: 'not_extracted' },
        disposition: text(item.disposition, 'RECEIVED_WAITING'),
        verification_status: text(item.verification_status, 'NOT_RUN'),
        summary: item.summary ?? { before: '—', requested: '—', result: '—' },
        transaction: item.transaction ? {
          transaction_id: text(item.transaction.transaction_id, '—'),
          source_receipt_id: text(item.transaction.source_receipt_id, item.source_receipt_id),
          source_digest: text(item.transaction.source_digest, '—'),
          evidence_digest: text(item.transaction.evidence_digest, '—'),
          plan_hash: text(item.transaction.plan_hash, '—'),
          disposition: text(item.transaction.disposition, item.disposition),
          plan: item.transaction.plan ?? item.transaction.typed_plan ?? null,
          typed_plan: item.transaction.typed_plan ?? item.transaction.plan ?? null,
          versions: item.transaction.versions ?? {},
          readback: item.transaction.readback ?? null,
          readback_parity: item.transaction.readback_parity ?? false,
          response: item.transaction.response ?? null,
        } : null,
        vehicle_results: (Array.isArray(item.vehicle_results) ? item.vehicle_results : []).map(normalizeVehicleResult),
        retry_state: item.retry_state ?? { attempts: 0, retry_class: null, next_attempt_at: null, quarantine: false, last_error_code: null },
        quarantine: item.quarantine ?? null,
      })),
    };
  } catch (_error) {
    return { ok: false, code: 'unsafe_snapshot', revision: null, items: [] };
  }
}

function createPdcEmailAiSuccessorInboxClient(options = {}) {
  const config = options.config || {};
  const url = String(config.url || '').replace(/\/$/, '');
  const key = String(config.publishableKey || '');
  const projectRef = pdcEmailAiSuccessorProjectRef(url);
  if (projectRef !== PDC_EMAIL_AI_SUCCESSOR_STAGING_PROJECT_REF) {
    throw new Error(`Successor AI Intake is staging-only; received ${projectRef || 'unknown project'}.`);
  }
  if (!key) throw new Error('Successor AI Intake requires the staging publishable key.');
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const request = options.fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  if (!request) throw new Error('Successor AI Intake has no fetch implementation.');

  async function snapshot({ cursor = null, pageSize = 100 } = {}) {
    const accessToken = String(getAccessToken() || '');
    if (!accessToken) return { ok: false, code: 'not_authenticated', data: null };
    const boundedSize = Math.max(1, Math.min(250, Number(pageSize) || 100));
    let response;
    try {
      response = await request(`${url}/rest/v1/rpc/${PDC_EMAIL_AI_SUCCESSOR_INBOX_RPC}`, {
        method: 'POST',
        headers: { apikey: key, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_cursor: cursor, p_page_size: boundedSize }),
      });
    } catch (_error) {
      return { ok: false, code: 'snapshot_unavailable', data: null, ambiguous: true };
    }
    let body = null;
    try { body = await response.json(); } catch (_error) { body = null; }
    if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || `HTTP ${response.status}`, data: null };
    const normalized = normalizeSuccessorInboxSnapshot(body.data || body);
    return normalized.ok ? { ok: true, status: response.status, data: normalized } : { ok: false, code: normalized.code, data: null };
  }

  return { projectRef, snapshot, rpc: PDC_EMAIL_AI_SUCCESSOR_INBOX_RPC };
}

function successorInboxSummary(snapshot = {}) {
  const items = Array.isArray(snapshot.items) ? snapshot.items : [];
  return {
    emailCount: items.length,
    vehicleCount: items.reduce((total, item) => total + (Array.isArray(item.vehicle_results) ? item.vehicle_results.length : 0), 0),
    actionCount: items.reduce((total, item) => total + (item.vehicle_results || []).reduce((count, vehicle) => count + (vehicle.actions || []).length, 0), 0),
  };
}

function receivedLabel(value) {
  if (!value) return 'Received time unavailable';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? text(value) : date.toLocaleString();
}

function statusClass(value = '') {
  const normalized = String(value).toUpperCase();
  if (normalized.includes('SUCCESS') || normalized.includes('VERIFIED') || normalized.includes('APPLIED')) return 'is-success';
  if (normalized.includes('PARTIAL') || normalized.includes('BLOCKED') || normalized.includes('AMBIGUOUS') || normalized.includes('QUARANTINE')) return 'is-warning';
  if (normalized.includes('FAILED') || normalized.includes('ERROR')) return 'is-error';
  return 'is-neutral';
}

function compactSummary(summary = {}) {
  return `<span>${escapeHtml(text(summary.before))}</span><b>→</b><span>${escapeHtml(text(summary.requested))}</span><b>→</b><span>${escapeHtml(text(summary.result))}</span>`;
}

function attachmentSummaryHtml(summary = {}) {
  const names = Array.isArray(summary.names) ? summary.names : [];
  const label = `${Number(summary.count) || names.length || 0} attachment${(Number(summary.count) || names.length || 0) === 1 ? '' : 's'}`;
  return `${escapeHtml(label)}${names.length ? ` · ${escapeHtml(names.slice(0, 4).join(', '))}` : ''}`;
}

function actionHtml(action = {}) {
  const verification = action.verification || {};
  return `<article class="successor-action-row ${statusClass(action.disposition)}">
    <div class="successor-action-heading"><strong>${escapeHtml(action.action_type)}</strong><span class="successor-status-pill ${statusClass(action.disposition)}">${escapeHtml(action.disposition)}</span></div>
    <div class="successor-action-meta"><span>Instruction ${escapeHtml(action.instruction_id)}</span><span>RPC ${escapeHtml(action.canonical_rpc)}</span><span>Verification ${escapeHtml(verification.parity === true ? 'PASS' : verification.checked === true ? 'CHECKED' : 'NOT PROVEN')}</span></div>
    <div class="successor-value-triplet"><div><small>Old</small><code>${safeJson(action.before)}</code></div><div><small>Requested</small><code>${safeJson(action.requested)}</code></div><div><small>Result</small><code>${safeJson(action.result ?? action.actual)}</code></div></div>
    <p class="successor-action-reason">${escapeHtml(action.reason)}</p>
    <details class="successor-nested-detail"><summary>Action receipt, expected/actual and evidence refs</summary><dl class="successor-detail-list"><dt>Expected</dt><dd><code>${safeJson(action.expected)}</code></dd><dt>Actual</dt><dd><code>${safeJson(action.actual)}</code></dd><dt>Receipt</dt><dd>${escapeHtml(action.action_receipt_id)}</dd><dt>Action key</dt><dd>${escapeHtml(action.action_key)}</dd><dt>Evidence refs</dt><dd><code>${safeJson(action.evidence_refs)}</code></dd></dl></details>
  </article>`;
}

function vehicleResultHtml(vehicle = {}) {
  const actions = Array.isArray(vehicle.actions) ? vehicle.actions : [];
  return `<section class="successor-vehicle-result" data-vehicle-id="${escapeHtml(vehicle.vehicle_id)}">
    <header><div><span class="successor-label">Vehicle result</span><h4>${escapeHtml(vehicle.stock)} · ${escapeHtml(vehicle.vehicle)}</h4></div><div class="successor-vehicle-status"><span>${escapeHtml(vehicle.identity_status)}</span><small>Location ${escapeHtml(vehicle.location)}</small></div></header>
    <div class="successor-action-list">${actions.length ? actions.map(actionHtml).join('') : '<p class="successor-muted">No typed actions recorded for this vehicle.</p>'}</div>
    ${vehicle.readback ? `<details class="successor-nested-detail"><summary>Vehicle authoritative readback</summary><pre>${safeJson(vehicle.readback)}</pre></details>` : ''}
  </section>`;
}

function transactionDetailsHtml(item = {}) {
  const transaction = item.transaction;
  const retry = item.retry_state || {};
  if (!transaction) return `<div class="successor-waiting-detail"><strong>Successor processing not yet recorded</strong><span>This source receipt remains visible while natural intake/interpretation/command processing is pending.</span></div>`;
  const versions = transaction.versions || {};
  return `<div class="successor-technical-grid">
    <section><h4>Typed AI plan and versions</h4><dl class="successor-detail-list"><dt>Plan schema</dt><dd>${escapeHtml(transaction.plan?.schema_version || transaction.typed_plan?.schema_version || '—')}</dd><dt>Model</dt><dd>${escapeHtml(versions.model || '—')}</dd><dt>Prompt</dt><dd>${escapeHtml(versions.prompt || '—')}</dd><dt>Instruction set</dt><dd>${escapeHtml(versions.instruction_set || '—')}</dd><dt>Taxonomy</dt><dd>${escapeHtml(versions.taxonomy || '—')}</dd><dt>Rules</dt><dd>${escapeHtml(versions.rules || '—')}</dd><dt>Action contract</dt><dd>${escapeHtml(versions.action_contract || '—')}</dd><dt>Supabase action</dt><dd>${escapeHtml(versions.supabase_action || versions.supabase_action_version || '—')}</dd><dt>Transport</dt><dd>${escapeHtml(versions.transport || versions.transport_release_version || '—')}</dd></dl><pre>${safeJson(transaction.plan || transaction.typed_plan)}</pre></section>
    <section><h4>Immutable receipt and readback</h4><dl class="successor-detail-list"><dt>Transaction receipt</dt><dd>${escapeHtml(transaction.transaction_id)}</dd><dt>Source receipt</dt><dd>${escapeHtml(transaction.source_receipt_id)}</dd><dt>Provider UID</dt><dd>${escapeHtml(item.provider_uid)}</dd><dt>Message ID</dt><dd>${escapeHtml(item.message_id)}</dd><dt>Thread ID</dt><dd>${escapeHtml(item.thread_id)}</dd><dt>Attachment digests</dt><dd><code>${safeJson(item.attachment_summary?.digests || [])}</code></dd><dt>Source digest</dt><dd>${escapeHtml(transaction.source_digest)}</dd><dt>Evidence digest</dt><dd>${escapeHtml(transaction.evidence_digest)}</dd><dt>Plan hash</dt><dd>${escapeHtml(transaction.plan_hash)}</dd><dt>Disposition</dt><dd>${escapeHtml(transaction.disposition)}</dd><dt>Readback parity</dt><dd>${escapeHtml(transaction.readback_parity === true ? 'PASS' : 'NOT PROVEN')}</dd></dl><pre>${safeJson(transaction.readback || transaction.response)}</pre></section>
    <section><h4>Retry and quarantine</h4><dl class="successor-detail-list"><dt>Attempts</dt><dd>${escapeHtml(retry.attempts ?? 0)}</dd><dt>Retry class</dt><dd>${escapeHtml(retry.retry_class)}</dd><dt>Next retry</dt><dd>${escapeHtml(retry.next_attempt_at)}</dd><dt>Last error</dt><dd>${escapeHtml(retry.last_error_code)}</dd><dt>Quarantine</dt><dd>${escapeHtml(retry.quarantine === true || item.quarantine ? 'YES' : 'No')}</dd></dl>${item.quarantine ? `<pre>${safeJson(item.quarantine)}</pre>` : ''}</section>
  </div>`;
}

function successorEmailRowHtml(item = {}, index = 0) {
  const vehicles = Array.isArray(item.vehicle_results) ? item.vehicle_results : [];
  const summary = item.summary || {};
  const verification = item.verification_status || 'NOT_RUN';
  const key = `${item.source_receipt_id}|${index}`;
  return `<article class="successor-email-row ${statusClass(item.disposition)}" data-successor-email="${escapeHtml(key)}">
    <header class="successor-email-heading"><div><span class="successor-label">Email receipt · ${escapeHtml(item.intake_uid)}</span><h3>${escapeHtml(item.subject)}</h3></div><div class="successor-email-status"><time datetime="${escapeHtml(item.received_at || '')}">${escapeHtml(receivedLabel(item.received_at))}</time><span class="successor-status-pill ${statusClass(item.disposition)}">${escapeHtml(item.disposition)}</span><span class="successor-status-pill ${statusClass(verification)}">Verification ${escapeHtml(verification)}</span></div></header>
    <div class="successor-email-meta"><div><small>Sender</small><strong>${escapeHtml(item.sender)}</strong></div><div><small>Stock / vehicle</small><strong>${escapeHtml(vehicles.length ? vehicles.map(vehicle => `${vehicle.stock} · ${vehicle.vehicle}`).join(' · ') : 'Waiting for vehicle result')}</strong></div><div><small>Attachments / Job Card</small><strong>${attachmentSummaryHtml(item.attachment_summary)} · JC ${escapeHtml(item.job_card_summary?.job_card_number || '—')}</strong><small>${escapeHtml(`${item.job_card_summary?.operation_count ?? 0} operation lines · ${item.job_card_summary?.extraction_status || 'not_extracted'}`)}</small></div><div><small>Intake UID</small><strong>${escapeHtml(item.intake_uid)}</strong></div></div>
    <div class="successor-change-summary"><span class="successor-label">Before → requested → result</span><div>${compactSummary(summary)}</div></div>
    <div class="successor-vehicle-results">${vehicles.length ? vehicles.map(vehicleResultHtml).join('') : '<div class="successor-muted">No vehicle result yet. The email remains accounted for as a parent receipt.</div>'}</div>
    <details class="successor-email-details"><summary>Typed plan, all actions, receipts, retries and authoritative readback</summary>${transactionDetailsHtml(item)}</details>
  </article>`;
}

function renderSuccessorInbox(state = {}) {
  if (state.state === 'loading') return '<div class="successor-inbox-state is-loading" role="status" aria-live="polite"><strong>Loading successor AI Intake</strong><span>Reading the authenticated chronological STAGING receipt projection.</span></div>';
  if (state.state === 'error') return `<div class="successor-inbox-state is-error" role="alert"><strong>Successor AI Intake unavailable</strong><span>Nothing is being inferred or approved from an unavailable projection.</span><code>${escapeHtml(state.error || 'snapshot_unavailable')}</code></div>`;
  const snapshot = state.data || state;
  const items = Array.isArray(snapshot.items) ? snapshot.items : [];
  if (!items.length) return '<div class="successor-inbox-state is-empty"><strong>No successor emails received</strong><span>The live chronological receipt projection is empty. No processing is being claimed.</span></div>';
  const summary = successorInboxSummary(snapshot);
  return `<div class="successor-inbox-summary" aria-live="polite"><span>${summary.emailCount} email${summary.emailCount === 1 ? '' : 's'}</span><span>${summary.vehicleCount} vehicle result${summary.vehicleCount === 1 ? '' : 's'}</span><span>${summary.actionCount} typed action${summary.actionCount === 1 ? '' : 's'}</span><span>Revision ${escapeHtml(snapshot.revision)}</span></div><div class="successor-email-list">${items.map(successorEmailRowHtml).join('')}</div>${snapshot.has_more ? `<button class="small-button successor-load-more" type="button" data-successor-next-cursor="${escapeHtml(snapshot.next_cursor)}">Load older emails</button>` : ''}`;
}

function createPdcEmailAiSuccessorInboxController(options = {}) {
  const root = options.root;
  const client = options.client;
  const subscribeRealtime = options.subscribeRealtime;
  const getAuthority = typeof options.getAuthority === 'function' ? options.getAuthority : () => '';
  const state = { state: 'idle', realtimeState: 'connecting', data: { items: [], revision: null }, error: '', generation: 0, lifecycle: 0, subscription: null, cursor: null };
  if (!root || !client) throw new Error('Successor inbox requires a root and client.');

  function render() {
    const liveLabel = state.state === 'synchronized' && state.realtimeState === 'subscribed'
      ? `Live · revision ${state.data.revision ?? '—'}`
      : state.state === 'synchronized' ? `Refresh only · Realtime ${state.realtimeState}` : state.state;
    root.innerHTML = `<div class="successor-inbox-toolbar"><div><span class="eyebrow">Successor · evidence to typed plan to readback</span><h2 id="pdc-email-ai-successor-title">Chronological AI Intake</h2><p>Read-only projection of email receipts and controlled transaction results. This screen never writes business state.</p></div><div class="successor-inbox-actions"><span class="successor-inbox-state-pill ${escapeHtml(state.realtimeState)}">${escapeHtml(liveLabel)}</span><button class="small-button" id="pdc-successor-inbox-refresh" type="button">Refresh</button></div></div><div id="pdc-successor-inbox-content">${renderSuccessorInbox(state)}</div>`;
    root.querySelector('#pdc-successor-inbox-refresh')?.addEventListener('click', () => { void refresh(); });
    root.querySelector('.successor-load-more')?.addEventListener('click', event => { state.cursor = event.currentTarget.dataset.successorNextCursor || null; void refresh({ append: true }); });
  }

  async function refresh({ append = false } = {}) {
    const authority = String(getAuthority() || '');
    const lifecycle = state.lifecycle;
    if (!authority) { state.state = 'error'; state.error = 'not_authenticated'; state.data = { items: [], revision: null }; render(); return false; }
    if (!state.subscription) subscribe();
    const generation = ++state.generation;
    if (!append) state.state = 'loading';
    render();
    const response = await client.snapshot({ cursor: append ? state.cursor : null, pageSize: 100 });
    if (generation !== state.generation || lifecycle !== state.lifecycle || authority !== String(getAuthority() || '')) return false;
    if (!response.ok) { state.state = 'error'; state.error = response.code || 'snapshot_unavailable'; render(); return false; }
    const next = response.data;
    state.data = append ? { ...next, items: [...(state.data.items || []), ...(next.items || [])] } : next;
    state.state = 'synchronized'; state.error = ''; state.cursor = next.next_cursor || null; render(); return true;
  }

  function subscribe() {
    if (state.subscription || typeof subscribeRealtime !== 'function') return;
    const handle = subscribeRealtime(PDC_EMAIL_AI_SUCCESSOR_REVISION_TABLE, {
      onChange: () => { void refresh(); },
      onStatus: status => {
        const normalized = String(status || '').toUpperCase();
        state.realtimeState = normalized === 'SUBSCRIBED' ? 'subscribed' : normalized === 'CHANNEL_ERROR' || normalized === 'TIMED_OUT' || normalized === 'CLOSED' ? 'error' : 'connecting';
        render();
      },
    });
    if (handle) state.subscription = handle;
  }
  function unmount() {
    state.lifecycle += 1; state.generation += 1;
    try { state.subscription?.unsubscribe?.(); } catch (_error) { /* best effort */ }
    state.subscription = null;
  }
  function mount() { render(); if (getAuthority()) subscribe(); void refresh(); return controller; }
  const controller = { state, render, refresh, subscribe, unmount, mount };
  return controller;
}

function successorInboxAuthorityMarker(windowRef = window) {
  const context = windowRef.PDC_AUTH_CONTEXT || {};
  const role = String(context.role || '').trim().toLowerCase();
  const token = String(windowRef.__pdcCachedAccessToken || '');
  const user = String(context.userId || context.user?.id || context.email || '').trim();
  return ALLOWED_READ_ROLES.has(role) && token && user ? `${role}|${user}|${token}` : '';
}

function mountPdcEmailAiSuccessorInbox(windowRef = window, documentRef = document) {
  const root = documentRef.querySelector('#pdc-email-ai-successor-inbox');
  if (!root) return null;
  if (root.__successorInboxController) {
    if (successorInboxAuthorityMarker(windowRef)) {
      root.__successorInboxController.subscribe();
      void root.__successorInboxController.refresh();
    }
    return root.__successorInboxController;
  }
  const config = windowRef.PDC_SUPABASE_CONFIG || {};
  try {
    const client = createPdcEmailAiSuccessorInboxClient({ config, getAccessToken: () => windowRef.__pdcCachedAccessToken || null });
    const controller = createPdcEmailAiSuccessorInboxController({
      root,
      client,
      getAuthority: () => successorInboxAuthorityMarker(windowRef),
      subscribeRealtime: (tableName, handlers) => windowRef.PDC_SUPABASE && typeof windowRef.createPdcSupabaseTableRealtimeSubscription === 'function'
        ? windowRef.createPdcSupabaseTableRealtimeSubscription(tableName, handlers)
        : null,
    });
    root.__successorInboxController = controller;
    controller.mount();
    let realtimeRetryCount = 0;
    const mountedLifecycle = controller.state.lifecycle;
    const realtimeRetryTimer = windowRef.setInterval(() => {
      realtimeRetryCount += 1;
      if (root.__successorInboxController !== controller || controller.state.lifecycle !== mountedLifecycle || controller.state.subscription || realtimeRetryCount > 30) {
        windowRef.clearInterval(realtimeRetryTimer);
        return;
      }
      if (successorInboxAuthorityMarker(windowRef)) controller.subscribe();
    }, 1000);
    return controller;
  } catch (error) {
    root.innerHTML = renderSuccessorInbox({ state: 'error', error: error.message || 'successor_inbox_unavailable' });
    return null;
  }
}

const successorInboxApi = {
  PDC_EMAIL_AI_SUCCESSOR_STAGING_PROJECT_REF,
  PDC_EMAIL_AI_SUCCESSOR_INBOX_RPC,
  PDC_EMAIL_AI_SUCCESSOR_REVISION_TABLE,
  pdcEmailAiSuccessorProjectRef,
  normalizeSuccessorInboxSnapshot,
  createPdcEmailAiSuccessorInboxClient,
  successorInboxSummary,
  renderSuccessorInbox,
  createPdcEmailAiSuccessorInboxController,
  mountPdcEmailAiSuccessorInbox,
};

if (typeof module !== 'undefined' && module.exports) module.exports = successorInboxApi;
if (typeof window !== 'undefined') {
  window.PDC_EMAIL_AI_SUCCESSOR_INBOX = successorInboxApi;
  const boot = () => {
    mountPdcEmailAiSuccessorInbox(window, document);
    window.addEventListener('pdc-auth-ready', () => mountPdcEmailAiSuccessorInbox(window, document));
    window.addEventListener('pdc-auth-locked', () => {
      const controller = document.querySelector('#pdc-email-ai-successor-inbox')?.__successorInboxController;
      controller?.unmount?.();
      if (controller) { controller.state.state = 'error'; controller.state.error = 'not_authenticated'; controller.render(); }
    });
    window.addEventListener('pdc-auth-token-changed', () => {
      const controller = document.querySelector('#pdc-email-ai-successor-inbox')?.__successorInboxController;
      if (controller) {
        controller.subscribe();
        void controller.refresh();
      }
    });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
}
