/* Authenticated, fail-closed compatibility guard for the generated staging artifact. */
(() => {
  'use strict';
  const PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
  const CONTRACT = 'pdc-control-board-staging-hardening-phase1';
  let state = Object.freeze({ status: 'pending', compatible: false, reason: 'compatibility_not_checked' });
  const api = {
    state: () => state,
    canMutate: () => state.compatible === true,
    async refresh(getAccessToken = null) {
      const config = window.PDC_SUPABASE_CONFIG || {};
      const token = typeof getAccessToken === 'function' ? getAccessToken() : (window.__pdcCachedAccessToken || window.PDC_AUTH_CONTEXT?.accessToken || '');
      if (String(config.url || '').replace(/^https:\/\//, '').split('.')[0] !== PROJECT_REF || !token) {
        state = Object.freeze({ status: 'blocked', compatible: false, reason: 'staging_identity_or_auth_unavailable' });
        return state;
      }
      try {
        const response = await fetch(`https://${PROJECT_REF}.supabase.co/rest/v1/rpc/get_pdc_staging_release_compatibility`, {
          method: 'POST', headers: { apikey: String(config.publishableKey || ''), Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_release_contract: CONTRACT }),
        });
        const body = await response.json();
        const data = body?.data || {};
        const compatible = response.ok && body?.ok === true && body?.code === 'compatible'
          && data.project_ref === PROJECT_REF && data.release_contract === CONTRACT && Number(data.database_migration_head) >= 306;
        state = Object.freeze({ status: compatible ? 'compatible' : 'blocked', compatible, reason: compatible ? '' : String(body?.code || `HTTP ${response.status}`), data: compatible ? data : null });
      } catch (_) {
        state = Object.freeze({ status: 'blocked', compatible: false, reason: 'release_compatibility_unavailable' });
      }
      window.dispatchEvent(new CustomEvent('pdc-staging-release-compatibility', { detail: state }));
      return state;
    },
  };
  window.PDC_STAGING_RELEASE_COMPATIBILITY = Object.freeze(api);
  window.addEventListener('pdc-auth-ready', () => { void api.refresh(() => window.__pdcCachedAccessToken || ''); });
  window.addEventListener('pdc-auth-locked', () => { state = Object.freeze({ status: 'blocked', compatible: false, reason: 'session_ended' }); });
})();
