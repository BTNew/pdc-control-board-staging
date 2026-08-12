'use strict';

/* Staging-only, server-authoritative AI Intake client. */
const PDC_AI_INTAKE_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const PDC_AI_INTAKE_REVISION_TABLE = 'pdc_ai_intake_revision';

function pdcAiIntakeProjectRef(url = '') {
  const match = String(url || '').trim().match(/^https:\/\/([a-z0-9]+)\.supabase\.co(?:\/|$)/i);
  return match ? match[1].toLowerCase() : '';
}

function createPdcAiIntakeRpcClient(config = {}, fetchImpl = null) {
  const url = String(config.url || '').replace(/\/$/, '');
  const key = String(config.publishableKey || '');
  const projectRef = pdcAiIntakeProjectRef(url);
  if (projectRef !== PDC_AI_INTAKE_STAGING_PROJECT_REF) {
    throw new Error(`AI Intake adjustments are staging-only; expected ${PDC_AI_INTAKE_STAGING_PROJECT_REF}, received ${projectRef || 'unknown project'}.`);
  }
  if (!key) throw new Error('AI Intake requires the staging publishable key.');
  const request = fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  if (!request) throw new Error('AI Intake has no fetch implementation.');

  async function rpc(accessToken, name, params = {}) {
    if (!accessToken) return { ok: false, status: 401, ambiguous: false, body: { ok: false, code: 'not_authenticated' } };
    let response;
    try {
      response = await request(`${url}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { apikey: key, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(params),
      });
    } catch (error) {
      return { ok: false, status: 0, ambiguous: true, body: null, error };
    }
    let body = null;
    try { body = await response.json(); } catch (_error) { body = null; }
    // A proxy/gateway may emit these statuses after the RPC transaction has
    // committed. They are not proof of rejection and must retain the exact
    // idempotency attempt for authoritative reconciliation/same-key retry.
    const ambiguousStatus = response.status === 408
      || response.status === 425
      || response.status === 429
      || (response.status >= 500 && response.status <= 599);
    return {
      ok: response.ok && body != null,
      status: response.status,
      ambiguous: ambiguousStatus || (response.ok && body == null),
      body,
    };
  }
  return { projectRef, rpc };
}

function createPdcAiIntakeService(options = {}) {
  const config = options.config || {};
  const client = options.client || createPdcAiIntakeRpcClient(config, options.fetchImpl);
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const subscribeRealtime = typeof options.subscribeRealtime === 'function' ? options.subscribeRealtime : null;
  if (pdcAiIntakeProjectRef(config.url) !== PDC_AI_INTAKE_STAGING_PROJECT_REF || client.projectRef !== PDC_AI_INTAKE_STAGING_PROJECT_REF) {
    throw new Error('AI Intake service refused a non-staging project.');
  }

  async function call(name, params) {
    const response = await client.rpc(getAccessToken(), name, params);
    if (response.ambiguous) {
      return { ok: false, code: 'outcome_unknown', outcomeUnknown: true, status: response.status, data: null };
    }
    if (!response.ok || !response.body || response.body.ok === false) {
      const code = response.body?.code || response.body?.error || response.body?.message || `HTTP ${response.status}`;
      return { ok: false, code, status: response.status, data: response.body || null };
    }
    return { ok: true, status: response.status, data: response.body?.data || response.body };
  }

  function snapshot(status = 'pending', pageSize = 100) {
    const normalized = String(status || 'pending').toLowerCase();
    if (!['pending', 'applied', 'rejected', 'all'].includes(normalized)) {
      return Promise.resolve({ ok: false, code: 'invalid_status' });
    }
    return call('get_pdc_ai_intake_snapshot', {
      p_status: normalized,
      p_page_size: Math.max(1, Math.min(250, Number(pageSize) || 100)),
    });
  }

  function decide(proposal = {}, decision = '', reason = '', idempotencyKey = '') {
    const normalized = String(decision || '').toLowerCase();
    const trimmedReason = String(reason || '').trim();
    const action = String(proposal.action_type || '').toLowerCase();
    const key = String(idempotencyKey || '').trim();
    const inboxRevision = Number(proposal.inbox_revision);
    const navisionRevision = proposal.navision_revision == null ? null : Number(proposal.navision_revision);
    if (!proposal.proposal_id || !Number.isInteger(Number(proposal.version)) || Number(proposal.version) < 1) {
      return Promise.resolve({ ok: false, code: 'invalid_proposal' });
    }
    if (!Number.isInteger(inboxRevision) || inboxRevision < 1) return Promise.resolve({ ok: false, code: 'invalid_inbox_revision' });
    if (!['board_activate_only', 'review_only'].includes(action)) return Promise.resolve({ ok: false, code: 'invalid_action' });
    if (!/^pdc-ai-intake-[a-zA-Z0-9_-]{16,160}$/.test(key)) return Promise.resolve({ ok: false, code: 'invalid_idempotency_key' });
    if (!/^[A-F0-9]{16}$/.test(String(proposal.fingerprint || ''))) {
      return Promise.resolve({ ok: false, code: 'invalid_fingerprint' });
    }
    if (!['apply', 'reject'].includes(normalized)) return Promise.resolve({ ok: false, code: 'invalid_decision' });
    if (normalized === 'apply' && (action !== 'board_activate_only' || !Number.isInteger(navisionRevision) || navisionRevision < 1)) {
      return Promise.resolve({ ok: false, code: 'invalid_navision_revision' });
    }
    if (trimmedReason.length < 10 || trimmedReason.length > 500) return Promise.resolve({ ok: false, code: 'decision_reason_required' });
    return call('decide_pdc_ai_intake_proposal', {
      p_idempotency_key: key,
      p_proposal_id: proposal.proposal_id,
      p_expected_version: Number(proposal.version),
      p_expected_inbox_revision: inboxRevision,
      p_expected_action: action,
      p_decision: normalized,
      p_fingerprint: proposal.fingerprint,
      p_expected_navision_revision: normalized === 'apply' ? navisionRevision : null,
      p_reason: trimmedReason,
    });
  }

  function monitorStatus() {
    return call('get_pdc_email_monitor_status', {});
  }

  function subscribe(onRevision) {
    if (!subscribeRealtime) return { unsubscribe() {} };
    return subscribeRealtime(PDC_AI_INTAKE_REVISION_TABLE, event => {
      if (typeof onRevision === 'function') onRevision(event?.new?.revision ?? null, event);
    });
  }

  return { projectRef: PDC_AI_INTAKE_STAGING_PROJECT_REF, authority: 'supabase_staging_ai_intake_only', snapshot, decide, monitorStatus, subscribe };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { PDC_AI_INTAKE_STAGING_PROJECT_REF, PDC_AI_INTAKE_REVISION_TABLE, pdcAiIntakeProjectRef, createPdcAiIntakeRpcClient, createPdcAiIntakeService };
}
if (typeof window !== 'undefined') {
  window.PDC_AI_INTAKE_SERVICE = { PDC_AI_INTAKE_STAGING_PROJECT_REF, PDC_AI_INTAKE_REVISION_TABLE, createPdcAiIntakeRpcClient, createPdcAiIntakeService };
}
