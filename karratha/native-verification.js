(function (root) {
  'use strict';
  const PROJECT = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
  const SHA = /^[0-9a-f]{64}$/;
  const MD5 = /^[0-9a-f]{32}$/;
  const bool = value => typeof value === 'boolean' ? value : null;
  const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
  const timestamp = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value)) ? value : null;
  function sequenceState(value) {
    if (!value || count(value.last_value) === null || count(value.log_cnt) === null || bool(value.is_called) === null) return null;
    return { last_value: value.last_value, log_cnt: value.log_cnt, is_called: value.is_called };
  }
  function project(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return { ok: false, phase: 'invalid_response' };
    const result = { ok: value.ok === true, phase: /^[a-z0-9_-]{1,80}$/.test(value.phase || '') ? value.phase : 'unavailable' };
    if (/^[A-Z0-9]{5}$/.test(value.failure_code || '')) result.failure_code = value.failure_code;
    for (const key of ['candidate_sha256','compact_installer_sha256','fixture_sha256']) if (SHA.test(value[key] || '')) result[key] = value[key];
    for (const key of ['genuine_website_transport','native_planner_gate_unchanged','synthetic_rows_rolled_back','readiness_still_false','photo_object_bytes_upload_download_tested','raw_rest_rls_tested_by_this_rpc']) if (bool(value[key]) !== null) result[key] = value[key];
    const definition = value.installed_definition_proof;
    if (definition && typeof definition === 'object') {
      result.installed_definition_proof = { ok: definition.ok === true };
      for (const key of ['expected_methods','present_methods','exact_body_count','exact_definition_count']) if (count(definition[key]) !== null) result.installed_definition_proof[key] = definition[key];
      if (Array.isArray(definition.mismatches)) result.installed_definition_proof.mismatch_count = definition.mismatches.length;
    }
    const native = value.native_acceptance;
    if (native && typeof native === 'object') {
      result.native_acceptance = { ok: native.ok === true };
      for (const key of ['native_public_facades','checks']) if (count(native[key]) !== null) result.native_acceptance[key] = native[key];
      for (const key of ['photo_receipt_and_policy_linkage','photo_object_bytes_upload_download_tested','no_backdated_work','persisted']) if (bool(native[key]) !== null) result.native_acceptance[key] = native[key];
    }
    const fitter = value.fitter_request_path_acceptance;
    if (fitter && typeof fitter === 'object') {
      result.fitter_request_path_acceptance = { ok: fitter.ok === true };
      for (const key of ['checks','own_aliases']) if (count(fitter[key]) !== null) result.fitter_request_path_acceptance[key] = fitter[key];
      for (const key of ['old_paths_denied','native_post_write_gate_preserved','genuine_actor_retained','metadata_path_trial','separate_fitter_browser_session_tested']) if (bool(fitter[key]) !== null) result.fitter_request_path_acceptance[key] = fitter[key];
    }
    const protectedProof = value.protected_fence?.protected;
    if (protectedProof && typeof protectedProof === 'object') {
      result.protected_fence = { ok: protectedProof.ok === true };
      for (const key of ['catalogue_digest','catalog_digest']) if (MD5.test(protectedProof[key] || '') || SHA.test(protectedProof[key] || '')) result.protected_fence[key] = protectedProof[key];
      for (const key of ['before_sha256','after_sha256']) if (SHA.test(protectedProof[key] || '')) result.protected_fence[key] = protectedProof[key];
      for (const key of ['catalogue_objects','protected_relations','own_relations_restored','own_sequence_gaps_reported']) if (count(protectedProof[key]) !== null) result.protected_fence[key] = protectedProof[key];
      if (bool(protectedProof.shared_sequences_reset) !== null) result.protected_fence.shared_sequences_reset = protectedProof.shared_sequences_reset;
      const allocator = value.protected_fence.concurrent_cron_allocator;
      if (allocator && typeof allocator === 'object') {
        const safe = {};
        for (const key of ['before_state','after_state']) { const state = sequenceState(allocator[key]); if (state) safe[key] = state; }
        for (const key of ['captured_from','captured_to']) if (timestamp(allocator[key]) !== null) safe[key] = allocator[key];
        for (const key of ['first_runid','last_runid']) if (allocator[key] === null || count(allocator[key]) !== null) safe[key] = allocator[key];
        if (bool(allocator.requires_external_proof) !== null) safe.requires_external_proof = allocator.requires_external_proof;
        if (Array.isArray(allocator.protected_job_ids)) {
          safe.protected_job_ids = allocator.protected_job_ids.slice(0,100).filter(value => count(value) !== null);
          safe.protected_job_id_count = allocator.protected_job_ids.length;
          if (allocator.protected_job_ids.length > 100) safe.protected_job_ids_truncated = true;
        }
        if (Object.keys(safe).length) result.protected_fence.concurrent_cron_allocator = safe;
      }
      const advances = value.protected_fence.own_sequence_advances;
      if (Array.isArray(advances)) {
        const safe = advances.slice(0,10).flatMap(row => {
          const before = sequenceState(row?.before_state), after = sequenceState(row?.after_state);
          return /^karratha135_[a-z][a-z0-9_]{0,46}$/.test(row?.schema_name || '') && /^[a-z][a-z0-9_]{0,62}$/.test(row?.table_name || '') && before && after ? [{ schema_name: row.schema_name, table_name: row.table_name, before_state: before, after_state: after }] : [];
        });
        if (safe.length) { result.protected_fence.own_sequence_advances = safe; result.protected_fence.own_sequence_advance_count = advances.length; if (advances.length > 10) result.protected_fence.own_sequence_advances_truncated = true; }
      }
    }
    return result;
  }
  function passed(value) {
    return value?.ok === true && value.genuine_website_transport === true && value.native_planner_gate_unchanged === true
      && value.synthetic_rows_rolled_back === true && value.readiness_still_false === true
      && value.installed_definition_proof?.ok === true && value.native_acceptance?.ok === true && value.protected_fence?.protected?.ok === true;
  }
  // A page-local SDK boundary. This never installs or relaxes board transport.
  function guardedFetch(fetcher) {
    return async (input, options = {}) => {
      const url = new URL(typeof input === 'string' || input instanceof URL ? String(input) : input.url, PROJECT);
      const method = String(options.method || input?.method || 'GET').toUpperCase();
      if (url.origin !== PROJECT || url.username || url.password || url.hash) throw new Error('Verification route is unavailable.');
      const user = url.pathname === '/auth/v1/user' && method === 'GET' && !url.search;
      const refresh = url.pathname === '/auth/v1/token' && method === 'POST' && url.searchParams.get('grant_type') === 'refresh_token' && [...url.searchParams.keys()].every(key => key === 'grant_type');
      const verify = url.pathname === '/rest/v1/rpc/k135_verify_native_fixture' && method === 'POST' && !url.search;
      if (!user && !refresh && !verify) throw new Error('Verification route is unavailable.');
      return fetcher(input, { ...options, redirect: 'error' });
    };
  }
  if (typeof module === 'object' && module.exports) { module.exports = { project, passed, guardedFetch }; return; }
  // The only RPC called here is the explicitly approved no-argument fixture.
  let generation = 0, pending = false, client;
  function init() {
    const button = document.getElementById('verify-native');
    const status = document.getElementById('verification-status');
    const output = document.getElementById('verification-result');
    const clear = () => { output.hidden = true; output.textContent = ''; };
    const config = root.KARRATHA_CONFIG;
    if (config?.environment !== 'staging' || config?.centreCode !== 'KARRATHA' || config?.authStorageKey !== 'karratha-pdc-auth-v1' || config?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || config?.url !== PROJECT || !root.supabase?.createClient) {
      button.disabled = true; status.textContent = 'The verification connection is not ready.'; return;
    }
    try {
      client = root.supabase.createClient(config.url, config.publishableKey, { auth: { storageKey: 'karratha-pdc-auth-v1', persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }, global: { fetch: guardedFetch(root.fetch.bind(root)) } });
    } catch (_) { button.disabled = true; status.textContent = 'The verification connection is unavailable.'; return; }
    client.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT' || event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED') {
        generation++; clear(); status.textContent = event === 'SIGNED_OUT' ? 'Sign in to Karratha, then return here.' : 'Sign-in changed. Run verification when ready.';
      }
    });
    async function signedIn() {
      const user = await client.auth.getUser();
      if (user.error || !user.data?.user?.id) return false;
      const session = await client.auth.getSession();
      return !session.error && session.data?.session?.user?.id === user.data.user.id;
    }
    button.addEventListener('click', async () => {
      if (pending) return;
      pending = true; button.disabled = true; clear(); status.textContent = 'Checking your existing Karratha sign-in…';
      let requestGeneration = generation;
      try {
        if (!await signedIn()) { status.textContent = 'Sign in to Karratha, then return here.'; return; }
        if (generation !== requestGeneration) return;
        status.textContent = 'Running the isolated verification…';
        const response = await client.rpc('k135_verify_native_fixture', {});
        if (generation !== requestGeneration) return;
        if (response.error) { status.textContent = 'Verification could not complete. Check administrator approval and try again.'; return; }
        const safe = project(response.data);
        output.textContent = JSON.stringify(safe, null, 2); output.hidden = false;
        status.textContent = passed(response.data) ? 'Verification passed. Operational access remains closed.' : 'Verification needs review. Operational access remains closed.';
      } catch (_) {
        if (generation === requestGeneration) status.textContent = 'Verification could not complete. Check the connection and try again.';
      } finally { pending = false; button.disabled = false; }
    });
    (async () => {
      const initialGeneration = generation;
      try { const present = await signedIn(); if (generation === initialGeneration) status.textContent = present ? 'Existing Karratha sign-in found. Ready to verify.' : 'Sign in to Karratha, then return here.'; }
      catch (_) { if (generation === initialGeneration) status.textContent = 'Sign in to Karratha, then return here.'; }
    })();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true }); else init();
}(typeof window !== 'undefined' ? window : globalThis));
