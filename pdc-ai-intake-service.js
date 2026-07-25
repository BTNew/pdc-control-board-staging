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
    if (!accessToken) return { ok: false, status: 401, body: { ok: false, code: 'not_authenticated' } };
    const response = await request(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    });
    let body = null;
    try { body = await response.json(); } catch (_error) { body = null; }
    return { ok: response.ok, status: response.status, body };
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

  function decide(proposal = {}, decision = '', reason = '') {
    const normalized = String(decision || '').toLowerCase();
    const trimmedReason = String(reason || '').trim();
    if (!proposal.proposal_id || !Number.isInteger(Number(proposal.version)) || Number(proposal.version) < 1) {
      return Promise.resolve({ ok: false, code: 'invalid_proposal' });
    }
    if (!/^[A-F0-9]{16}$/.test(String(proposal.fingerprint || ''))) {
      return Promise.resolve({ ok: false, code: 'invalid_fingerprint' });
    }
    if (!['apply', 'reject'].includes(normalized)) return Promise.resolve({ ok: false, code: 'invalid_decision' });
    if (trimmedReason.length < 10 || trimmedReason.length > 500) return Promise.resolve({ ok: false, code: 'decision_reason_required' });
    return call('decide_pdc_ai_intake_proposal', {
      p_proposal_id: proposal.proposal_id,
      p_expected_version: Number(proposal.version),
      p_fingerprint: proposal.fingerprint,
      p_decision: normalized,
      p_reason: trimmedReason,
    });
  }

  function subscribe(onRevision) {
    if (!subscribeRealtime) return { unsubscribe() {} };
    return subscribeRealtime(PDC_AI_INTAKE_REVISION_TABLE, event => {
      if (typeof onRevision === 'function') onRevision(event?.new?.revision ?? null, event);
    });
  }

  return { projectRef: PDC_AI_INTAKE_STAGING_PROJECT_REF, authority: 'supabase_staging_ai_intake_only', snapshot, decide, subscribe };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { PDC_AI_INTAKE_STAGING_PROJECT_REF, PDC_AI_INTAKE_REVISION_TABLE, pdcAiIntakeProjectRef, createPdcAiIntakeRpcClient, createPdcAiIntakeService };
}
if (typeof window !== 'undefined') {
  window.PDC_AI_INTAKE_SERVICE = { PDC_AI_INTAKE_STAGING_PROJECT_REF, PDC_AI_INTAKE_REVISION_TABLE, createPdcAiIntakeRpcClient, createPdcAiIntakeService };
}
